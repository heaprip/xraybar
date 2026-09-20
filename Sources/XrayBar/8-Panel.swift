// 8. Panel — the whole UI: the window under the menu bar icon, laid out like the system's
// Wi-Fi and Bluetooth panels: a title with a switch, rows with round icons (blue = the one in
// use), long lists expanding in place, and a plain row at the bottom for everything else.
// It stays open while choosing; a click outside or on the icon closes it.
//
// Geometry and colors follow MacControlCenterUI by Steffan Andrews (MIT,
// github.com/orchetect/MacControlCenterUI), which measures the macOS 26 Control Center.
// It is not used as a package: it needs Xcode's SwiftUI macro plugins (D31).

import SwiftUI

/// macOS 26 Control Center measurements (MacControlCenterUI "Menu Constants", "MenuWidth").
enum Metrics {
    static let width: CGFloat = 310
    static let contentInset: CGFloat = 14       // text and icons from the panel edge
    static let highlightInset: CGFloat = 6      // hover highlight from the panel edge
    static let itemPadding: CGFloat = 4         // above and below a row
    static let panelPadding: CGFloat = 6        // above the first and below the last row
    static let circle: CGFloat = 26             // round row icon
    static let corner: CGFloat = 10             // hover highlight, continuous corners
    static let iconRow: CGFloat = 30            // row heights: icon 26 + 4, text 18 + 4, section 20
    static let textRow: CGFloat = 22
    static let sectionRow: CGFloat = 20
}

struct Panel: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.changedWhileConnected && model.state == .connected {
                notice("Changes apply after reconnecting.", button: "Reconnect", action: model.reconnect)
            }
            if Session.needsRestore && model.tick >= 0 {
                notice("The last connection did not shut down cleanly.", button: "Restore", action: model.restore)
            }
            divider
            SectionTitle("Server")
            if model.library.profiles.isEmpty {
                Text("No servers yet. Import one from XrayBar Options.").foregroundStyle(.secondary)
                    .padding(.horizontal, Metrics.contentInset).padding(.vertical, Metrics.itemPadding)
            }
            choices(model.library.profiles.map { ($0.id, $0.name, $0.address) }, icon: "globe",
                    selected: model.library.profile?.id, status: transitionText, more: "Other Servers",
                    expanded: \.serversExpanded, select: model.selectProfile, remove: model.removeProfile)
            divider
            SectionTitle("Routing")
            choices(model.library.routingSets.map { ($0.id, $0.name, "\($0.rules.count) rules") }, icon: "arrow.triangle.branch",
                    selected: model.library.routing.id, status: nil, more: "Other Routing Sets",
                    expanded: \.routingExpanded, select: model.selectRouting, remove: model.removeRouting)
            divider
            Menu { moreMenu } label: { Text("XrayBar Options").frame(maxWidth: .infinity, alignment: .leading) }
                .menuStyle(.button).buttonStyle(RowStyle(highlighted: model.hovered == Panel.optionsRow))
                .onHover { model.hovered = $0 ? Panel.optionsRow : nil }
        }
        .padding(.vertical, Metrics.panelPadding)
        .frame(width: Metrics.width)
        .systemPanelBackground()
    }

    static let optionsRow = UUID()
    static let moreRows = (servers: UUID(), routing: UUID())

    // MARK: Parts

    /// Title (13 pt bold) and the connection switch, as in the Bluetooth and Wi-Fi panels.
    private var header: some View {
        HStack {
            Text("XrayBar").font(.system(size: 13, weight: .bold))
            Spacer()
            Toggle("Connected", isOn: Binding(
                get: { model.state == .connected || model.state == .connecting },
                set: { $0 ? model.connect() : model.disconnect() }))
                .toggleStyle(.switch).labelsHidden()
                .disabled(model.state == .connecting || model.state == .disconnecting)
        }
        .padding(.horizontal, Metrics.contentInset).padding(.vertical, Metrics.itemPadding)
    }

    /// Only in-between states are spelled out; connected or not is the switch and the blue icon.
    private var transitionText: String? {
        model.state == .connecting || model.state == .disconnecting ? model.statusText : nil
    }

    private var divider: some View {
        Divider().padding(.horizontal, Metrics.contentInset).padding(.vertical, 5)
    }

    private func notice(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.subheadline)
            Spacer()
            Button(button, action: action).controlSize(.small)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
        .padding(.horizontal, Metrics.highlightInset).padding(.vertical, Metrics.itemPadding)
    }

    /// Rows with a round icon; the one in use sits on a blue circle, the others are a plain
    /// glyph (Wi-Fi). Up to four inline; beyond that the selected one, then "Other …", which
    /// expands in place like Wi-Fi's "Other Networks". A name used twice shows its detail.
    /// Right-click (or Control-click) a row to remove it.
    private func choices(_ items: [(id: UUID, name: String, detail: String)], icon: String, selected: UUID?,
                         status: String?, more: String, expanded: ReferenceWritableKeyPath<AppModel, Bool>,
                         select: @escaping (UUID) -> Void, remove: @escaping (UUID) -> Void) -> some View {
        let names = Dictionary(grouping: items, by: \.name)
        let isOpen = model[keyPath: expanded]
        let first = items.count <= 4 ? items : items.filter { $0.id == selected }
        let rest = items.count <= 4 || !isOpen ? [] : items.filter { $0.id != selected }
        let moreID = expanded == \AppModel.serversExpanded ? Panel.moreRows.servers : Panel.moreRows.routing
        func row(_ c: (id: UUID, name: String, detail: String)) -> some View {
            HStack(spacing: 8) {
                Image(systemName: icon).resizable().scaledToFit().padding(6)
                    .foregroundStyle(c.id == selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: Metrics.circle, height: Metrics.circle)
                    .background(Circle().fill(c.id == selected ? Color.accentColor : .clear))
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.name).lineLimit(1)
                    if c.id == selected, let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if names[c.name]!.count > 1 { Text(c.detail).foregroundStyle(.secondary).lineLimit(1) }
            }
            .row(height: Metrics.iconRow, highlighted: model.hovered == c.id) { select(c.id) }
            .onHover { model.hovered = $0 ? c.id : (model.hovered == c.id ? nil : model.hovered) }
            .contextMenu { Button("Remove “\(c.name)”…", role: .destructive) { remove(c.id) } }
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(first, id: \.id) { row($0) }
            if items.count > 4 {
                // Like Wi-Fi's "Other Networks": a section title with a chevron, shaded while open.
                HStack {
                    SectionTitle.text(more)
                    Spacer()
                    Image(systemName: "chevron.right").resizable().scaledToFit().frame(width: 10, height: 10)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .row(height: Metrics.sectionRow + Metrics.itemPadding, highlighted: model.hovered == moreID || isOpen) {
                    model[keyPath: expanded].toggle()
                }
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

/// Section titles: 13 pt semibold, 60 % white in dark mode, 70 % black in light mode.
struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Self.text(title).padding(.horizontal, Metrics.contentInset).frame(height: Metrics.sectionRow)
    }

    static func text(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: 1, alpha: 0.6) : NSColor(white: 0, alpha: 0.7)
            }))
    }
}

/// A full-width row that highlights under the pointer, like Control Center rows: content 14 pt
/// from the edge, highlight 6 pt from the edge with 10 pt continuous corners.
struct RowStyle: ButtonStyle {
    let highlighted: Bool

    /// Control Center's hover color: white 30 % at 40 % opacity (dark), white 90 % at 20 % (light).
    static let hover = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.3, alpha: 0.4) : NSColor(white: 0.9, alpha: 0.2)
    })

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Metrics.contentInset - Metrics.highlightInset)
            .padding(.vertical, Metrics.itemPadding)
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            .contentShape(Rectangle())
            .background(highlighted || configuration.isPressed ? Self.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
            .padding(.horizontal, Metrics.highlightInset)
    }
}

extension View {
    /// A clickable Control Center row with a fixed height. Not a Button: inside a MenuBarExtra
    /// window macOS restyles buttons, and rows lost their padding (MacControlCenterUI does the
    /// same: content, onTapGesture, onHover).
    func row(height: CGFloat, highlighted: Bool, action: @escaping () -> Void) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .padding(.horizontal, Metrics.contentInset - Metrics.highlightInset)
            .contentShape(Rectangle())
            .background(highlighted ? RowStyle.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
            .padding(.horizontal, Metrics.highlightInset)
            .onTapGesture(perform: action)
    }

    /// The system draws the panel glass from the background style on macOS 26 and later
    /// (as MacControlCenterUI does); earlier systems get a plain material.
    @ViewBuilder func systemPanelBackground() -> some View {
        if #available(macOS 27, *) {
            backgroundStyle(.regularMaterial)
        } else if #available(macOS 26, *) {
            backgroundStyle(.ultraThinMaterial)
        } else {
            background(.regularMaterial)
        }
    }
}
