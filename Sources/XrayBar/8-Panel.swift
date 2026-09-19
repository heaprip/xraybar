// 8. Panel — the whole UI: the window under the menu bar icon, like Wi-Fi and Control Center.
// It stays open while choosing; a click outside or on the icon closes it. Frequent things are
// in the panel (connection, server, routing); everything else is in the "⋯" menu.

import SwiftUI

struct Panel: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Divider().padding(.vertical, 2)
            section("Server")
            if model.library.profiles.isEmpty {
                Text("No servers yet — use ⋯ › Import").foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            choices(model.library.profiles.map { ($0.id, $0.name, $0.address) },
                    selected: model.library.profile?.id, more: "Other Servers",
                    select: model.selectProfile, remove: model.removeProfile)
            Divider().padding(.vertical, 2)
            section("Routing")
            choices(model.library.routingSets.map { ($0.id, $0.name, "\($0.rules.count) rules") },
                    selected: model.library.routing.id, more: "Other Routing Sets",
                    select: model.selectRouting, remove: model.removeRouting)
            Divider().padding(.vertical, 2)
            footer
        }
        .padding(8)
        .frame(width: 320)
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("XrayBar").font(.headline)
                    Text(model.statusText).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Connected", isOn: Binding(
                    get: { model.state == .connected || model.state == .connecting },
                    set: { $0 ? model.connect() : model.disconnect() }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(model.state == .connecting || model.state == .disconnecting)
            }
            if model.changedWhileConnected && model.state == .connected {
                notice("Changes apply after reconnecting.", button: "Reconnect", action: model.reconnect)
            }
            if Session.needsRestore && model.tick >= 0 {
                notice("The last connection did not shut down cleanly.", button: "Restore", action: model.restore)
            }
        }
        .padding(.horizontal, 8).padding(.top, 4)
    }

    private var footer: some View {
        HStack {
            Text(model.xrayTitle).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Menu { moreMenu } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 8).padding(.bottom, 2)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 2)
    }

    private func notice(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.subheadline)
            Spacer()
            Button(button, action: action).controlSize(.small)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Choices with a checkmark, like the Wi-Fi panel: up to four inline; beyond that the
    /// selected one inline and the rest in a pop-up. A name used twice shows its detail.
    /// Right-click (or Control-click) a choice to remove it.
    private func choices(_ items: [(id: UUID, name: String, detail: String)], selected: UUID?, more: String,
                         select: @escaping (UUID) -> Void, remove: @escaping (UUID) -> Void) -> some View {
        let names = Dictionary(grouping: items, by: \.name)
        let inline = items.count > 4 ? items.filter { $0.id == selected } : items
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(inline, id: \.id) { c in
                Button { select(c.id) } label: {
                    HStack {
                        Image(systemName: "checkmark").opacity(c.id == selected ? 1 : 0).font(.body.weight(.semibold))
                        Text(c.name).lineLimit(1)
                        Spacer()
                        if names[c.name]!.count > 1 { Text(c.detail).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                .buttonStyle(RowStyle(highlighted: model.hovered == c.id))
                .onHover { model.hovered = $0 ? c.id : (model.hovered == c.id ? nil : model.hovered) }
                .contextMenu { Button("Remove “\(c.name)”…", role: .destructive) { remove(c.id) } }
            }
            if items.count > 4 {
                Menu(more) {
                    ForEach(items.filter { $0.id != selected }, id: \.id) { c in
                        Button(names[c.name]!.count > 1 ? "\(c.name)  \(c.detail)" : c.name) { select(c.id) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
    }

    // MARK: "⋯" — everything that is not needed every day

    @ViewBuilder private var moreMenu: some View {
        Button("Import Link or QR Code from Clipboard", action: model.importClipboard)
        Button("Import from v2rayN…", action: model.importV2rayN)
        Button("Share Server…", action: model.shareServer).disabled(model.library.profile == nil)
        Divider()
        Menu(model.xrayTitle) {
            Section("Version") {
                ForEach(model.xrayVersions, id: \.path) { v in
                    Toggle(v.title, isOn: Binding(get: { v.path == model.library.settings.xrayPath },
                                                  set: { _ in model.selectXray(v.path) }))
                }
                if !Assets.installedXray().contains(Assets.testedXray) {
                    Button("Download \(Assets.testedXray) (tested with XrayBar)", action: model.downloadTestedXray)
                }
                Button("Check for Newer Versions…", action: model.checkNewerXray).disabled(model.updating)
            }
            Section("Routing Data") {
                Button("Update Routing Data", action: model.updateData).disabled(model.updating)
                Picker("Source", selection: Binding(get: { model.dataSource }, set: model.selectDataSource)) {
                    ForEach(Assets.DataSource.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Divider()
            let excluded = model.library.settings.routeExclusions ?? []
            Button(excluded.isEmpty ? "Exclude from Tunnel…" : "Exclude from Tunnel (\(excluded.count))…",
                   action: model.editExclusions)
        }
        Menu("Diagnostics") {
            Button("Show Xray Log", action: model.showLog)
            Toggle("Detailed Log", isOn: Binding(get: { model.library.settings.detailedLog == true },
                                                 set: { _ in model.toggleDetailedLog() }))
            Button("Show Data Folder", action: model.showDataFolder)
            if Helper.installed && model.tick >= 0 {
                Divider()
                Button("Uninstall Helper…", action: model.uninstallHelper)
            }
        }
        if !Helper.installed && model.tick >= 0 {
            Button("Use Touch ID to Connect…", action: model.installHelper)
        } else if Helper.outdated {
            Button("Update Helper…", action: model.installHelper)
        }
        if Bundle.main.bundlePath.hasSuffix(".app") {   // login items need an app bundle
            Toggle("Open at Login", isOn: Binding(get: { model.opensAtLogin }, set: { _ in model.toggleOpenAtLogin() }))
        }
        Divider()
        Button("Quit XrayBar", action: model.quit).keyboardShortcut("q")
    }
}

/// A full-width row that highlights under the pointer, like a menu item.
struct RowStyle: ButtonStyle {
    let highlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(highlighted || configuration.isPressed ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6))
    }
}
