// 8. Panel — the whole UI: the window under the menu bar icon, laid out like the system's
// Wi-Fi and Bluetooth panels: a title with a switch, rows with round icons (blue = the one in
// use), long lists expanding in place, and a plain row at the bottom for everything else.
// It stays open while choosing; a click outside or on the icon closes it.

import SwiftUI

struct Panel: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if model.changedWhileConnected && model.state == .connected {
                notice("Changes apply after reconnecting.", button: "Reconnect", action: model.reconnect)
            }
            if Session.needsRestore && model.tick >= 0 {
                notice("The last connection did not shut down cleanly.", button: "Restore", action: model.restore)
            }
            divider
            section("Server")
            if model.library.profiles.isEmpty {
                Text("No servers yet. Import one from XrayBar Options.").foregroundStyle(.secondary).padding(.horizontal, 12)
            }
            choices(model.library.profiles.map { ($0.id, $0.name, $0.address) }, icon: "server.rack",
                    selected: model.library.profile?.id, status: model.statusText, more: "Other Servers",
                    expanded: \.serversExpanded, select: model.selectProfile, remove: model.removeProfile)
            divider
            section("Routing")
            choices(model.library.routingSets.map { ($0.id, $0.name, "\($0.rules.count) rules") }, icon: "arrow.triangle.branch",
                    selected: model.library.routing.id, status: nil, more: "Other Routing Sets",
                    expanded: \.routingExpanded, select: model.selectRouting, remove: model.removeRouting)
            divider
            Menu { moreMenu } label: { Text("XrayBar Options").frame(maxWidth: .infinity, alignment: .leading) }
                .menuStyle(.button).buttonStyle(RowStyle(highlighted: model.hovered == Panel.optionsRow))
                .onHover { model.hovered = $0 ? Panel.optionsRow : nil }
        }
        .padding(.horizontal, 5).padding(.vertical, 8)
        .frame(width: 320)
        .background(Blur().ignoresSafeArea())
    }

    static let optionsRow = UUID()
    static let moreRows = (servers: UUID(), routing: UUID())

    // MARK: Parts

    /// Title and the connection switch, as in the Bluetooth and Wi-Fi panels.
    private var header: some View {
        HStack {
            Text("XrayBar").font(.headline)
            Spacer()
            Toggle("Connected", isOn: Binding(
                get: { model.state == .connected || model.state == .connecting },
                set: { $0 ? model.connect() : model.disconnect() }))
                .toggleStyle(.switch).labelsHidden()
                .disabled(model.state == .connecting || model.state == .disconnecting)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private var divider: some View { Divider().padding(.horizontal, 12).padding(.vertical, 4) }

    private func section(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.bottom, 2)
    }

    private func notice(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.subheadline)
            Spacer()
            Button(button, action: action).controlSize(.small)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 7)
    }

    /// Rows with a round icon; the selected one is blue and, for servers, shows the connection
    /// state. Up to four inline; beyond that the selected one, then "Other …", which expands in
    /// place like Wi-Fi's "Other Networks". A name used twice shows its detail. Right-click
    /// (or Control-click) a row to remove it.
    private func choices(_ items: [(id: UUID, name: String, detail: String)], icon: String, selected: UUID?,
                         status: String?, more: String, expanded: ReferenceWritableKeyPath<AppModel, Bool>,
                         select: @escaping (UUID) -> Void, remove: @escaping (UUID) -> Void) -> some View {
        let names = Dictionary(grouping: items, by: \.name)
        let isOpen = model[keyPath: expanded]
        let first = items.count <= 4 ? items : items.filter { $0.id == selected }
        let rest = items.count <= 4 || !isOpen ? [] : items.filter { $0.id != selected }
        let moreID = expanded == \AppModel.serversExpanded ? Panel.moreRows.servers : Panel.moreRows.routing
        func row(_ c: (id: UUID, name: String, detail: String)) -> some View {
            Button { select(c.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.id == selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(c.id == selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.name).lineLimit(1)
                        if c.id == selected, let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if names[c.name]!.count > 1 { Text(c.detail).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            .buttonStyle(RowStyle(highlighted: model.hovered == c.id))
            .onHover { model.hovered = $0 ? c.id : (model.hovered == c.id ? nil : model.hovered) }
            .contextMenu { Button("Remove “\(c.name)”…", role: .destructive) { remove(c.id) } }
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(first, id: \.id) { row($0) }
            if items.count > 4 {
                Button { model[keyPath: expanded].toggle() } label: {
                    HStack {
                        Text(more)
                        Spacer()
                        Image(systemName: "chevron.right").rotationEffect(.degrees(isOpen ? 90 : 0))
                            .foregroundStyle(.secondary).font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(RowStyle(highlighted: model.hovered == moreID))
                .onHover { model.hovered = $0 ? moreID : nil }
            }
            ForEach(rest, id: \.id) { row($0) }
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
            .padding(.horizontal, 7).padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .contentShape(Rectangle())
            .background(highlighted || configuration.isPressed ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The translucent, blurred material of the system's menu bar panels. MenuBarExtra's own
/// background follows the window's active state, and a menu bar app's window is rarely
/// active, so it looked opaque; this one stays active.
struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = TransparentWindowEffect()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    private final class TransparentWindowEffect: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isOpaque = false
            window?.backgroundColor = .clear
        }
    }
}
