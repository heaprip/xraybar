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
        for p in library.profiles {
            let i = action(p.name, #selector(selectProfile(_:)))
            i.representedObject = p.id
            i.state = p.id == library.profile?.id ? .on : .off
            menu.addItem(i)
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Routing"))
        for r in library.routingSets {
            let i = action(r.name, #selector(selectRouting(_:)))
            i.representedObject = r.id
            i.state = r.id == library.routing.id ? .on : .off
            menu.addItem(i)
        }

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

        menu.addItem(.separator())
        menu.addItem(action("Import from Clipboard", #selector(importClipboard)))
        menu.addItem(action("Import QR Code from Image…", #selector(importQRImage)))
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
                alert("Xray updated", "\(coreStatus). Checksums verified. Takes effect on the next Connect.")
            } catch {
                alert("Update failed", error.localizedDescription)
            }
            updating = false
        }
    }

    @objc private func selectDataSource(_ sender: NSMenuItem) {
        library.settings.dataSource = (sender.representedObject as? String).flatMap(Assets.DataSource.init)
        save()
        alert("Routing data source changed", "Choose Update Xray and Routing Data to download it.")
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

    @objc private func importQRImage() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image with a server QR code"
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        importQR(image)
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
