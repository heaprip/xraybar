// 8. Menu — the whole UI: a standard menu under the menu bar icon, as the HIG asks for menu
// bar extras (D34) and as Karabiner-Elements does: SwiftUI buttons and toggles that the
// system renders as a native NSMenu, with SF Symbols on the items.

import SwiftUI

struct AppMenu: View {
    let model: AppModel

    var body: some View {
        Text(model.statusText)
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
        if Session.needsRestore && model.tick >= 0 {
            Button("Restore Network Settings…", systemImage: "wrench.and.screwdriver", action: model.restore)
        }

        Section("Server") {
            if model.library.profiles.isEmpty { Text("No servers — import one below") }
            choices(model.library.profiles.map { ($0.id, $0.name, $0.address) },
                    selected: model.library.profile?.id, more: "Other Servers", select: model.selectProfile)
        }
        Section("Routing") {
            choices(model.library.routingSets.map { ($0.id, $0.name, "\($0.rules.count) rules") },
                    selected: model.library.routing.id, more: "Other Routing Sets", select: model.selectRouting)
        }

        Divider()
        Button("Import Link or QR Code from Clipboard", systemImage: "doc.on.clipboard", action: model.importClipboard)
        Button("Import from v2rayN…", systemImage: "square.and.arrow.down", action: model.importV2rayN)
        Button("Share Server…", systemImage: "qrcode", action: model.shareServer).disabled(model.library.profile == nil)
        Menu("Remove", systemImage: "trash") {
            Section("Servers") {
                ForEach(model.library.profiles) { p in Button(p.name + "…") { model.removeProfile(p.id) } }
            }
            Section("Routing Sets") {
                ForEach(model.library.routingSets) { r in Button(r.name + "…") { model.removeRouting(r.id) } }
            }
        }

        Divider()
        Menu(model.xrayTitle, systemImage: "cpu") { xrayMenu }
        Menu("Diagnostics", systemImage: "stethoscope") { diagnosticsMenu }
        if !Helper.installed && model.tick >= 0 {
            Button("Use Touch ID to Connect…", systemImage: "touchid", action: model.installHelper)
        } else if Helper.outdated {
            Button("Update Helper…", systemImage: "arrow.clockwise", action: model.installHelper)
        }
        Toggle("Connect at Launch", isOn: Binding(get: { model.connectsAtLaunch }, set: { _ in model.toggleConnectAtLaunch() }))
        if Bundle.main.bundlePath.hasSuffix(".app") {   // login items need an app bundle
            Toggle("Open at Login", isOn: Binding(get: { model.opensAtLogin }, set: { _ in model.toggleOpenAtLogin() }))
        }
        Divider()
        Button("Quit XrayBar", systemImage: "power", action: model.quit).keyboardShortcut("q")
    }

    /// Choices with the system checkmark: up to four inline; beyond that the selected one
    /// inline and the rest in a submenu (the Wi-Fi menu's "Other Networks"). A name used twice
    /// shows its detail (address or rule count).
    @ViewBuilder
    private func choices(_ items: [(id: UUID, name: String, detail: String)], selected: UUID?, more: String,
                         select: @escaping (UUID) -> Void) -> some View {
        let names = Dictionary(grouping: items, by: \.name)
        let title = { (c: (id: UUID, name: String, detail: String)) in
            names[c.name]!.count > 1 ? "\(c.name)  —  \(c.detail)" : c.name
        }
        let toggle = { (c: (id: UUID, name: String, detail: String)) in
            Toggle(title(c), isOn: Binding(get: { c.id == selected }, set: { _ in select(c.id) }))
        }
        if items.count <= 4 {
            ForEach(items, id: \.id) { toggle($0) }
        } else {
            ForEach(items.filter { $0.id == selected }, id: \.id) { toggle($0) }
            Menu(more) { ForEach(items.filter { $0.id != selected }, id: \.id) { toggle($0) } }
        }
    }

    @ViewBuilder private var xrayMenu: some View {
        Section("Version") {
            ForEach(model.xrayVersions, id: \.path) { v in
                Toggle(v.title, isOn: Binding(get: { v.path == model.library.settings.xrayPath },
                                              set: { _ in model.selectXray(v.path) }))
            }
            if !Assets.installedXray().contains(Assets.testedXray) {
                Button("Download \(Assets.testedXray) (tested with XrayBar)", action: model.downloadTestedXray)
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
        Button(excluded.isEmpty ? "Exclude from Tunnel…" : "Exclude from Tunnel (\(excluded.count))…",
               systemImage: "arrow.uturn.right", action: model.editExclusions)
    }

    @ViewBuilder private var diagnosticsMenu: some View {
        Button("Show Xray Log", systemImage: "doc.text", action: model.showLog)
        Toggle("Detailed Log", isOn: Binding(get: { model.library.settings.detailedLog == true },
                                             set: { _ in model.toggleDetailedLog() }))
        Button("Show Data Folder", systemImage: "folder", action: model.showDataFolder)
        if Helper.installed && model.tick >= 0 {
            Divider()
            Button("Uninstall Helper…", systemImage: "trash", action: model.uninstallHelper)
        }
    }
}
