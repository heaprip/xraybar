// 6. Menu — the whole UI: one status item and its menu, laid out like the system's own
// menu extras (Wi-Fi, VPN): status on top, choices inline with checkmarks, actions below.

import AppKit
import CoreImage.CIFilterBuiltins

@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let session = Session()
    private var library = Store.load()
    private var updating = false

    override init() {
        super.init()
        item.menu = NSMenu()
        item.menu?.delegate = self
        session.onChange = { [weak self] in self?.stateChanged() }
        updateIcon()
        if Session.needsRestore { offerRestore() }
    }

    // MARK: Building the menu (rebuilt every time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled(statusText))
        if Session.needsRestore {
            menu.addItem(action("Restore Network Settings…", #selector(restore)))
        }
        switch session.state {
        case .connected, .connecting:
            menu.addItem(action("Disconnect", #selector(disconnect)))
        case .disconnecting:
            menu.addItem(disabled("Disconnect"))
        case .disconnected, .failed:
            menu.addItem(action("Connect", #selector(connect)))
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Server"))
        if library.profiles.isEmpty { menu.addItem(disabled("No servers — import one below")) }
        let servers = library.profiles.map { p in
            (p.id, p.name, p.name + "  " + p.address)   // the address tells same-named servers apart
        }
        addChoices(servers, selected: library.profile?.id, more: "Other Servers", to: menu,
                   #selector(selectProfile(_:)), remove: #selector(removeProfile(_:)))

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Routing"))
        let routing = library.routingSets.map { r in
            (r.id, r.name, r.name + "  (\(r.rules.count) rules)")
        }
        addChoices(routing, selected: library.routing.id, more: "Other Routing Sets", to: menu,
                   #selector(selectRouting(_:)), remove: #selector(removeRouting(_:)))

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Xray"))
        menu.addItem(disabled(coreStatus))
        menu.addItem(updating ? disabled("Updating…") : action("Update Xray and Routing Data", #selector(updateAssets)))
        let sources = NSMenu()
        for source in Assets.DataSource.allCases {
            let i = action(source.title, #selector(selectDataSource(_:)))
            i.representedObject = source.rawValue
            i.state = source == dataSource ? .on : .off
            sources.addItem(i)
        }
        let sourceItem = NSMenuItem(title: "Routing Data Source", action: nil, keyEquivalent: "")
        sourceItem.submenu = sources
        menu.addItem(sourceItem)
        let excluded = library.settings.routeExclusions ?? []
        menu.addItem(action(excluded.isEmpty ? "Exclude from Tunnel…" : "Exclude from Tunnel (\(excluded.count))…",
                            #selector(editExclusions)))

        menu.addItem(.separator())
        menu.addItem(action("Import from Clipboard", #selector(importClipboard)))
        menu.addItem(action("Scan QR Code on Screen…", #selector(scanScreen)))
        menu.addItem(action("Import from v2rayN…", #selector(importV2rayN)))
        if library.profile != nil { menu.addItem(action("Share Server…", #selector(shareServer))) }
        menu.addItem(.separator())
        menu.addItem(action("Show Xray Log", #selector(showLog)))
        let detailed = action("Detailed Log", #selector(toggleDetailedLog))
        detailed.state = library.settings.detailedLog == true ? .on : .off
        menu.addItem(detailed)
        menu.addItem(action("Show Data Folder", #selector(showDataFolder)))
        menu.addItem(.separator())
        menu.addItem(action("Quit XrayBar", #selector(quit), key: "q"))
    }

    /// Choices with a checkmark on the selected one, like the Wi-Fi menu: up to four inline;
    /// beyond that only the selected one inline and the rest in a submenu. A name that occurs
    /// more than once is shown with its detail (address or rule count) to tell them apart.
    /// Holding Option turns every choice into "Remove …" (the standard alternate-item pattern).
    private func addChoices(_ items: [(id: UUID, name: String, detailed: String)], selected: UUID?,
                            more: String, to menu: NSMenu, _ selector: Selector, remove: Selector) {
        let names = Dictionary(grouping: items, by: \.name)
        func add(_ c: (id: UUID, name: String, detailed: String), to menu: NSMenu) {
            let title = names[c.name]!.count > 1 ? c.detailed : c.name
            let i = action(title, selector)
            i.representedObject = c.id
            i.state = c.id == selected ? .on : .off
            menu.addItem(i)
            let alt = action("Remove “\(title)”…", remove)
            alt.representedObject = c.id
            alt.isAlternate = true
            alt.keyEquivalentModifierMask = .option
            menu.addItem(alt)
        }
        guard items.count > 4 else { return items.forEach { add($0, to: menu) } }
        items.filter { $0.id == selected }.forEach { add($0, to: menu) }
        let submenu = NSMenu()
        items.filter { $0.id != selected }.forEach { add($0, to: submenu) }
        let other = NSMenuItem(title: more, action: nil, keyEquivalent: "")
        other.submenu = submenu
        menu.addItem(other)
    }

    private var statusText: String {
        let name = library.profile?.name ?? ""
        switch session.state {
        case .connected: return "Connected — \(name)"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .disconnected, .failed: return "Not Connected"
        }
    }

    private var dataSource: Assets.DataSource { library.settings.dataSource ?? .runetfreedom }

    /// "Xray 26.9.9 · runetfreedom (Russia)", or where the xray in use comes from.
    private var coreStatus: String {
        guard library.settings.assetsDir == Assets.dir.path, let version = library.settings.coreVersion else {
            return "Using Xray from v2rayN"
        }
        return version.split(separator: " ").prefix(2).joined(separator: " ") + " · " + dataSource.title
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        i.target = self
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    // MARK: State

    private func stateChanged() {
        updateIcon()
        if case .failed(let message) = session.state { alert("Could not connect", message) }
    }

    private func updateIcon() {
        let symbol = switch session.state {
        case .connected: "shield.fill"
        case .connecting, .disconnecting: "shield.lefthalf.filled"
        case .disconnected, .failed: "shield"
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "XrayBar")
    }

    // MARK: Actions

    @objc private func connect() { session.connect(library) }
    @objc private func restore() { session.restore() }

    /// A previous session ended without cleaning up (power loss, crash of the root script).
    private func offerRestore() {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "XrayBar did not shut down cleanly"
        a.informativeText = "Network settings from the last connection are still in place "
            + "(DNS, or Xray still running). Restore them now? You will be asked for your password."
        a.addButton(withTitle: "Restore")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { session.restore() }
    }

    @objc private func disconnect() { session.disconnect() }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        library.selectedProfile = sender.representedObject as? UUID
        saveSelection()
    }

    @objc private func selectRouting(_ sender: NSMenuItem) {
        library.selectedRouting = sender.representedObject as? UUID
        saveSelection()
    }

    @objc private func removeProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let p = library.profiles.first(where: { $0.id == id }), confirmRemove(p.name) else { return }
        library.profiles.removeAll { $0.id == id }
        save()
    }

    @objc private func removeRouting(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let r = library.routingSets.first(where: { $0.id == id }), confirmRemove(r.name) else { return }
        library.routingSets.removeAll { $0.id == id }
        save()
    }

    /// Removing the selected item selects the first remaining one on the next Connect.
    private func confirmRemove(_ name: String) -> Bool {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "Remove “\(name)”?"
        a.informativeText = "This cannot be undone. A running connection is not affected."
        a.addButton(withTitle: "Remove").hasDestructiveAction = true
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Downloads and verifies Xray and the routing data (7-Assets), then switches to them.
    @objc private func updateAssets() {
        updating = true
        let source = dataSource
        Task {
            do {
                let version = try await Assets.update(dataSource: source)
                library.settings.assetsDir = Assets.dir.path
                library.settings.coreVersion = version
                save()
                updating = false
                alert("Xray updated", "\(coreStatus). Checksums verified. Takes effect on the next Connect.")
            } catch {
                updating = false
                alert("Update failed", error.localizedDescription)
            }
        }
    }

    @objc private func selectDataSource(_ sender: NSMenuItem) {
        library.settings.dataSource = (sender.representedObject as? String).flatMap(Assets.DataSource.init)
        save()
        alert("Routing data source changed", "Choose Update Xray and Routing Data to download it.")
    }

    /// Networks the system routes outside the tunnel, e.g. a work network reached by another VPN.
    @objc private func editExclusions() {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "Exclude from Tunnel"
        a.informativeText = "IPv4 addresses or networks, separated by commas, that bypass Xray entirely "
            + "(unlike “direct” rules, which still pass through it). Example: 10.8.0.0/16, 203.0.113.7"
        let field = NSTextField(string: (library.settings.routeExclusions ?? []).joined(separator: ", "))
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        field.placeholderString = "10.8.0.0/16, 203.0.113.7"
        a.accessoryView = field
        a.window.initialFirstResponder = field
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let entries = field.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let invalid = entries.filter { CIDR.parse($0) == nil }
        guard invalid.isEmpty else { return alert("Not saved", "Not an IPv4 address or network: " + invalid.joined(separator: ", ")) }
        library.settings.routeExclusions = entries
        saveSelection()
    }

    @objc private func toggleDetailedLog() {
        library.settings.detailedLog = !(library.settings.detailedLog ?? false)
        saveSelection()
    }

    /// A running session keeps its config; changes apply on the next Connect.
    private func saveSelection() {
        save()
        if session.state == .connected {
            alert("Reconnect to apply", "The change takes effect the next time you connect.")
        }
    }

    /// A copied vless:// link (one per line), or a copied image containing QR codes.
    @objc private func importClipboard() {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            importLinks(text.split(whereSeparator: \.isNewline).map(String.init))
        } else if let image = NSImage(pasteboard: pasteboard) {
            importQR(image)
        } else {
            alert("Nothing to import", "Copy a vless:// link or an image with a QR code first.")
        }
    }

    /// The system screenshot crosshair (as with ⌘⇧4): select the QR code, it is decoded and the
    /// temporary capture deleted at once. Escape cancels. Uses Apple's own screencapture tool,
    /// so XrayBar never captures the screen itself.
    @objc private func scanScreen() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("xraybar-qr-\(UUID()).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-i", "-x", file.path]   // interactive selection, no shutter sound
        capture.terminationHandler = { _ in
            Task { @MainActor in
                defer { try? FileManager.default.removeItem(at: file) }
                guard let image = NSImage(contentsOf: file) else { return }   // cancelled
                self.importQR(image)
            }
        }
        do { try capture.run() } catch { alert("Screen capture failed", error.localizedDescription) }
    }

    private func importQR(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let codes = try? Import.qrCodes(in: cg), !codes.isEmpty
        else { return alert("No QR code found", "The image does not contain a readable QR code.") }
        importLinks(codes)
    }

    private func importLinks(_ lines: [String]) {
        let links = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            let profiles = try links.map(Import.profile(fromLink:))
            guard !profiles.isEmpty else { return alert("Nothing to import", "Copy a vless:// link first.") }
            let added = Import.merge((profiles, []), into: &library)
            if library.selectedProfile == nil { library.selectedProfile = profiles.first?.id }
            save()
            alert("Imported", "\(added) new server(s).")
        } catch {
            alert("Import failed", error.localizedDescription)
        }
    }

    @objc private func importV2rayN() {
        do {
            let imported = try Import.fromV2rayN()
            let added = Import.merge(imported, into: &library)
            save()
            alert("Imported from v2rayN",
                  "\(added) new item(s): \(imported.profiles.count) VLESS server(s), \(imported.routing.count) routing set(s) found. v2rayN was only read, not changed.")
        } catch {
            alert("Import failed", error.localizedDescription)
        }
    }

    /// The selected server as a QR code and link, e.g. to add it on a phone.
    @objc private func shareServer() {
        guard let profile = library.profile else { return }
        let link = Import.link(for: profile)
        NSApp.activate()
        let a = NSAlert()
        a.messageText = profile.name
        a.informativeText = "Scan with another device. The code contains the server's credentials."
        a.accessoryView = NSImageView(image: Self.qrImage(link, size: 240))
        a.accessoryView?.frame = NSRect(x: 0, y: 0, width: 240, height: 240)
        a.addButton(withTitle: "Done")
        a.addButton(withTitle: "Copy Link")
        if a.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        }
    }

    static func qrImage(_ text: String, size: CGFloat) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return NSImage() }
        let scaled = code.transformed(by: CGAffineTransform(scaleX: size / code.extent.width, y: size / code.extent.height))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    @objc private func showLog() {
        guard FileManager.default.fileExists(atPath: Store.logFile.path) else {
            return alert("No log yet", "The log appears after the first connection.")
        }
        NSWorkspace.shared.open(Store.logFile)
    }

    @objc private func showDataFolder() {
        try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([Store.libraryFile])
    }

    @objc private func quit() {
        session.disconnect()      // the root session also stops by itself when the app exits
        NSApp.terminate(nil)
    }

    private func save() {
        do { try Store.save(library) } catch { alert("Could not save", error.localizedDescription) }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
