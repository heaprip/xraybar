// 6. Menu — the whole UI: one status item and its menu, laid out like the system's own
// menu extras (Wi-Fi, VPN): status on top, choices inline with checkmarks, actions below.

import AppKit

@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let session = Session()
    private var library = Store.load()

    override init() {
        super.init()
        item.menu = NSMenu()
        item.menu?.delegate = self
        session.onChange = { [weak self] in self?.stateChanged() }
        updateIcon()
    }

    // MARK: Building the menu (rebuilt every time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled(statusText))
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
        menu.addItem(action("Import Link from Clipboard", #selector(importClipboard)))
        menu.addItem(action("Import from v2rayN…", #selector(importV2rayN)))
        menu.addItem(.separator())
        menu.addItem(action("Show Xray Log", #selector(showLog)))
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
    @objc private func disconnect() { session.disconnect() }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        library.selectedProfile = sender.representedObject as? UUID
        saveSelection()
    }

    @objc private func selectRouting(_ sender: NSMenuItem) {
        library.selectedRouting = sender.representedObject as? UUID
        saveSelection()
    }

    /// A running session keeps its config; changes apply on the next Connect.
    private func saveSelection() {
        save()
        if session.state == .connected {
            alert("Reconnect to apply", "The change takes effect the next time you connect.")
        }
    }

    @objc private func importClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let links = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
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
