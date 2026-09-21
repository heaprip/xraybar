// 8. Menu — the whole UI: a standard menu under the menu bar icon, as the HIG asks for menu
// bar extras (D34) and as Karabiner-Elements does: SwiftUI buttons and toggles that the
// system renders as a native NSMenu, with SF Symbols on the items.
// Holding Option reveals alternates, as in the system's own menus (D35): technical details
// under the status line, Remove on every server and routing set, Copy Server Link.

import SwiftUI

struct AppMenu: View {
    let model: AppModel

    var body: some View {
        Text(model.statusText)
            .modifierKeyAlternate(.option) { Text(model.details) }
        switch model.state {
        case .connected, .connecting:
            Button("Disconnect", systemImage: "stop.circle", action: model.disconnect)
        case .disconnecting:
            Button("Disconnect", systemImage: "stop.circle") {}.disabled(true)
        case .disconnected, .failed:
            Button("Connect", systemImage: "play.circle", action: model.connect)
                .disabled(model.library.profile == nil)
        }
        if model.changedWhileConnected && model.state == .connected {
            Button("Reconnect to Apply Changes", systemImage: "arrow.clockwise", action: model.reconnect)
        }
        if model.needsRestore {
            Button("Restore Network Settings…", systemImage: "wrench.and.screwdriver", action: model.restore)
        }
        if model.helperOutdated {   // near the top: until updated, root runs the old code (D43)
            Button("Update Helper (Required)…", systemImage: "exclamationmark.triangle.fill", action: model.installHelper)
        }

        Section("Server") {
            if model.library.profiles.isEmpty { Text("No servers — import one below") }
            choices(model.library.profiles.map { ($0.id, $0.name, $0.address) },
                    selected: model.library.profile?.id, more: "Other Servers",
                    select: model.selectProfile, remove: model.removeProfile)
        }
        Section("Routing") {
            choices(model.library.routingSets.map { ($0.id, $0.name, "\($0.rules.count) rules") },
                    selected: model.library.routing.id, more: "Other Routing Sets",
                    select: model.selectRouting, remove: model.removeRouting)
        }

        Divider()
        Button("Import Link or QR Code from Clipboard", systemImage: "doc.on.clipboard", action: model.importClipboard)
        Button("Import from v2rayN…", systemImage: "square.and.arrow.down", action: model.importV2rayN)
        Button("Share Server…", systemImage: "qrcode", action: model.shareServer)
            .modifierKeyAlternate(.option) {
                Button("Copy Server Link", systemImage: "link", action: model.copyServerLink)
            }
            .disabled(model.library.profile == nil)

        Divider()
        Menu(model.xrayTitle, systemImage: "cpu") { xrayMenu }
        Menu("Diagnostics", systemImage: "stethoscope") { diagnosticsMenu }
        if !model.helperInstalled {
            Button("Use Touch ID to Connect…", systemImage: "touchid", action: model.installHelper)
        }
        Toggle("Connect at Launch", isOn: Binding(get: { model.connectsAtLaunch }, set: { _ in model.toggleConnectAtLaunch() }))
        if Bundle.main.bundlePath.hasSuffix(".app") {   // login items need an app bundle
            Toggle("Open at Login", isOn: Binding(get: { model.opensAtLogin }, set: { _ in model.toggleOpenAtLogin() }))
        }
        Divider()
        Button("About XrayBar", systemImage: "info.circle", action: model.showAbout)
        Button("Quit XrayBar", systemImage: "power", action: model.quit).keyboardShortcut("q")
    }

    /// Choices with the system checkmark: up to four inline; beyond that the selected one
    /// inline and the rest in a submenu (the Wi-Fi menu's "Other Networks"). A name used twice
    /// shows its detail (address or rule count). With Option held, each becomes "Remove …".
    @ViewBuilder
    private func choices(_ items: [(id: UUID, name: String, detail: String)], selected: UUID?, more: String,
                         select: @escaping (UUID) -> Void, remove: @escaping (UUID) -> Void) -> some View {
        let names = Dictionary(grouping: items, by: \.name)
        let title = { (c: (id: UUID, name: String, detail: String)) in
            names[c.name]!.count > 1 ? "\(c.name)  —  \(c.detail)" : c.name
        }
        let toggle = { (c: (id: UUID, name: String, detail: String)) in
            Toggle(title(c), isOn: Binding(get: { c.id == selected }, set: { _ in select(c.id) }))
                .modifierKeyAlternate(.option) {
                    Button("Remove “\(title(c))”…", systemImage: "trash", role: .destructive) { remove(c.id) }
                }
        }
        if items.count <= 4 {
            ForEach(items, id: \.id) { toggle($0) }
        } else {
            ForEach(items.filter { $0.id == selected }, id: \.id) { toggle($0) }
            Menu(L(more)) { ForEach(items.filter { $0.id != selected }, id: \.id) { toggle($0) } }
        }
    }

    @ViewBuilder private var xrayMenu: some View {
        Section("Version") {
            ForEach(model.xrayVersions, id: \.path) { v in
                Toggle(v.title, isOn: Binding(get: { v.path == model.xrayInUse },
                                              set: { _ in model.selectXray(v.path) }))
            }
            if !model.installedXray.contains(Assets.testedXray) {
                Button("Download \(Assets.testedXray) (tested with XrayBar)", action: model.downloadTestedXray)
            }
            if model.v2rayNXrayFound {
                Button("Copy Xray from v2rayN…", action: model.copyV2rayNXray)
            }
            Button("Check for Newer Versions…", systemImage: "arrow.down.circle", action: model.checkNewerXray)
                .disabled(model.updating)
        }
        Section("Routing Data") {
            Button("Update Routing Data", systemImage: "arrow.triangle.2.circlepath", action: model.updateData)
                .disabled(model.updating)
            Picker("Source", selection: Binding(get: { model.dataSource }, set: model.selectDataSource)) {
                ForEach(Assets.DataSource.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        Divider()
        let excluded = model.library.settings.routeExclusions ?? []
        Button(excluded.isEmpty ? L("Exclude from Tunnel…") : String(format: L("Exclude from Tunnel (%ld)…"), excluded.count),
               systemImage: "arrow.uturn.right", action: model.editExclusions)
    }

    @ViewBuilder private var diagnosticsMenu: some View {
        Button("Show Xray Log", systemImage: "doc.text", action: model.showLog)
        Toggle("Detailed Log", isOn: Binding(get: { model.library.settings.detailedLog == true },
                                             set: { _ in model.toggleDetailedLog() }))
        Button("Show Data Folder", systemImage: "folder", action: model.showDataFolder)
        if model.helperInstalled {
            Divider()
            Button("Uninstall Helper…", systemImage: "trash", action: model.uninstallHelper)
        }
    }
}
