// 6. Actions — what the UI can do: connect, choose, import, manage Xray and the helper.
// The menu (8-Menu.swift) only shows this model's state and calls these methods.

import AppKit
import CoreImage.CIFilterBuiltins
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    private(set) var library = Store.load()
    private(set) var state: Session.State = .disconnected
    private(set) var updating = false
    /// A server or routing change while connected: the menu offers Reconnect.
    private(set) var changedWhileConnected = false
    /// What the menu shows from disk, read after each change rather than while the menu draws.
    private(set) var installedXray = Assets.installedXray()
    private(set) var v2rayNXrayFound = false
    private(set) var helperInstalled = false
    private(set) var helperOutdated = false
    private(set) var needsRestore = false
    private(set) var opensAtLogin = false
    @ObservationIgnored let session = Session()

    init() {
        state = session.state
        session.onChange = { [weak self] in self?.stateChanged() }
        refresh()
        DispatchQueue.main.async { self.launched() }
    }

    private func refresh() {
        installedXray = Assets.installedXray()
        v2rayNXrayFound = FileManager.default.isExecutableFile(atPath: Settings.v2rayNXray)
        helperInstalled = Helper.installed
        helperOutdated = Helper.outdated
        needsRestore = Session.needsRestore
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// At launch: clean up after a session that died, or connect to the last used server so
    /// the user needs no click at all (Connect at Launch, on by default). Connecting still asks
    /// for authorization (Touch ID with the helper): root must not start xray unasked (D34).
    private func launched() {
        if Session.needsRestore { return offerRestore() }
        if connectsAtLaunch, library.profile != nil, state == .disconnected, Session.otherTunnel() == nil {
            connect()
        }
    }

    var connectsAtLaunch: Bool { library.settings.connectAtLaunch ?? true }

    func toggleConnectAtLaunch() {
        library.settings.connectAtLaunch = !connectsAtLaunch
        save()
    }

    var statusText: String {
        let name = library.profile?.name ?? ""
        switch state {
        case .connected: return String(format: L("Connected — %@"), name)
        case .connecting: return L("Connecting…")
        case .disconnecting: return L("Disconnecting…")
        case .disconnected, .failed: return L("Not Connected")
        }
    }

    var iconName: String {
        if helperOutdated { return "exclamationmark.shield" }   // root code is older than the app (D43)
        return switch state {
        case .connected: "shield.fill"
        case .connecting, .disconnecting: "shield.lefthalf.filled"
        case .disconnected, .failed: "shield"
        }
    }

    var dataSource: Assets.DataSource { library.settings.dataSource ?? .runetfreedom }

    /// Shown instead of the status line while Option is held, like the system Wi-Fi menu.
    var details: String {
        let s = library.settings
        let tunnel = state == .connected ? "utun77" : L("no tunnel")
        return "\(tunnel) · \(xrayTitle) · DNS \(s.systemDNS.joined(separator: ", ")) · \(helperInstalled ? "Touch ID" : L("password"))"
    }

    /// The xray Connect uses: the chosen version if installed, else the newest installed one.
    var xrayInUse: String? {
        let paths = installedXray.map { Assets.xrayPath($0) }
        return paths.first { $0 == library.settings.xrayBinary } ?? paths.first
    }

    /// The library as Connect sees it, with the xray actually used.
    private var connectable: Library {
        var l = library
        l.settings.xrayBinary = xrayInUse
        return l
    }

    /// "Xray v26.9.9": the version in use.
    var xrayTitle: String {
        xrayInUse.map { "Xray " + Self.xrayName(URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent) }
            ?? "Xray"
    }

    private static func xrayName(_ tag: String) -> String { tag == Assets.v2rayNTag ? L("from v2rayN") : tag }

    /// Installed versions as (path, title); "works" once it has carried traffic.
    var xrayVersions: [(path: String, title: String)] {
        installedXray.map { tag in
            let path = Assets.xrayPath(tag)
            let title = tag == Assets.testedXray ? String(format: L("%@ (tested with XrayBar)"), tag) : Self.xrayName(tag)
            return (path, path == library.settings.goodXray ? String(format: L("%@ — works"), title) : title)
        }
    }

    // MARK: State

    private func stateChanged() {
        state = session.state
        if state == .connecting { changedWhileConnected = false }
        refresh()
        trialIfNeeded()
        if case .failed(let message) = session.state { alert("Could not connect", message) }
    }

    // MARK: Actions

    func connect() { if helperCurrent() { session.connect(connectable) } }
    func disconnect() { session.disconnect() }
    func reconnect() { if helperCurrent() { session.reconnect(connectable) } }

    /// An installed helper runs its own root-owned copy of the session script, so fixes in an
    /// updated app do not reach root until the helper is updated too (D43). Connect asks first.
    private func helperCurrent() -> Bool {
        refresh()
        guard helperOutdated else { return true }
        NSApp.activate()
        let a = Self.newAlert()
        a.messageText = "Update the helper to connect"
        a.informativeText = "This version of XrayBar changes the code that runs as root. Until the helper is "
            + "updated, connecting would use its old copy. You will be asked for your password once."
        a.addButton(withTitle: "Update and Connect")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn && runHelperInstall()
    }
    func restore() { session.restore(); refresh() }

    /// A previous session ended without cleaning up (power loss, crash of the root script).
    private func offerRestore() {
        NSApp.activate()
        let a = Self.newAlert()
        a.messageText = "XrayBar did not shut down cleanly"
        a.informativeText = "Network settings from the last connection are still in place "
            + "(DNS, or Xray still running). Restore them now? You will be asked for your password."
        a.addButton(withTitle: "Restore")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { restore() }
    }

    func selectProfile(_ id: UUID) {
        guard id != library.profile?.id else { return }
        library.selectedProfile = id
        saveSelection()
    }

    func selectRouting(_ id: UUID) {
        guard id != library.routing.id else { return }
        library.selectedRouting = id
        saveSelection()
    }

    func removeProfile(_ id: UUID) {
        guard let p = library.profiles.first(where: { $0.id == id }), confirmRemove(p.name) else { return }
        library.profiles.removeAll { $0.id == id }
        save()
    }

    func removeRouting(_ id: UUID) {
        guard let r = library.routingSets.first(where: { $0.id == id }), confirmRemove(r.name) else { return }
        library.routingSets.removeAll { $0.id == id }
        save()
    }

    /// Removing the selected item selects the first remaining one on the next Connect.
    private func confirmRemove(_ name: String) -> Bool {
        NSApp.activate()
        let a = Self.newAlert()
        a.messageText = String(format: L("Remove “%@”?"), name)
        a.informativeText = "This cannot be undone. A running connection is not affected."
        a.addButton(withTitle: "Remove").hasDestructiveAction = true
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Downloads and verifies the routing data (7-Assets), then switches to it.
    func updateData() {
        updating = true
        let source = dataSource
        Task {
            do {
                try await Assets.updateData(source)
                library.settings.assetsDir = Assets.dir.path
                save()
                updating = false
                alert("Routing data updated", String(format: L("%@. Checksums verified. Takes effect on the next Connect."), source.title))
            } catch {
                updating = false
                alert("Update failed", error.localizedDescription)
            }
        }
    }

    // MARK: Xray versions (D23)

    func selectXray(_ path: String) {
        library.settings.xrayBinary = path
        saveSelection()
    }

    func downloadTestedXray() { install(Assets.testedXray) }

    func checkNewerXray() {
        updating = true
        Task {
            defer { updating = false }
            do {
                let installed = Assets.installedXray()
                let fresh = try await Assets.availableXray().filter { !installed.contains($0) }
                guard !fresh.isEmpty else { return alert("No newer versions", "All recent Xray releases are installed.") }
                let a = Self.newAlert()
                a.messageText = "Download Xray"
                a.informativeText = String(format: L("Releases newer than %@, from GitHub (Xray marks them all as pre-releases). "
                    + "Checked against each release's SHA-256. The first connection with it is a trial: if no traffic "
                    + "passes, you can switch back."), Assets.minimumXray.map(String.init).joined(separator: "."))
                let list = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
                list.addItems(withTitles: fresh)
                a.accessoryView = list
                a.addButton(withTitle: "Download and Use")
                a.addButton(withTitle: "Cancel")
                NSApp.activate()
                if a.runModal() == .alertFirstButtonReturn, let tag = list.titleOfSelectedItem { install(tag) }
            } catch {
                alert("Could not check for versions", error.localizedDescription)
            }
        }
    }

    private func install(_ tag: String) {
        updating = true
        Task {
            defer { updating = false }
            do {
                let binary = try await Assets.downloadXray(tag)
                defer { try? FileManager.default.removeItem(at: Assets.staging) }
                guard try installXray(tag, from: binary) else { return }
                alert(String(format: L("Xray %@ installed"), tag), "It is used from the next Connect. The previous version stays installed "
                      + "and can be chosen again in Xray Version.")
            } catch {
                alert(String(format: L("Could not install Xray %@"), tag), error.localizedDescription)
            }
        }
    }

    /// v2rayN's xray, copied into the root-owned store: the session never runs it where it is.
    func copyV2rayNXray() {
        do {
            guard try installXray(Assets.v2rayNTag, from: URL(fileURLWithPath: Settings.v2rayNXray)) else { return }
            alert("Xray from v2rayN copied", "It is used from the next Connect. Copy it again after v2rayN updates it.")
        } catch {
            alert("Could not copy Xray from v2rayN", error.localizedDescription)
        }
    }

    /// Root copies the binary into its store and checks the copy against the hash taken here, so
    /// the session only ever runs a root-owned xray (D38). One administrator prompt; false if cancelled.
    private func installXray(_ tag: String, from binary: URL) throws -> Bool {
        let hash = try Assets.sha256(binary)
        do {
            try session.runPrivileged(["--xray", tag, binary.path, hash], detached: false, script: "xraybar-install",
                                      prompt: String(format: L("XrayBar wants to install Xray %@."), Self.xrayName(tag)))
        } catch is CancellationError {
            return false
        }
        try? FileManager.default.removeItem(at: Assets.dir.appendingPathComponent("xray"))   // user-owned, before D38
        library.settings.xrayBinary = Assets.xrayPath(tag)
        save()
        refresh()
        return true
    }

    /// After connecting with an xray that has not carried traffic yet: one request through the
    /// tunnel. Success marks it as working; failure offers the way back (D23).
    private func trialIfNeeded() {
        guard session.state == .connected, let path = xrayInUse, path != library.settings.goodXray else { return }
        Task {
            if await Assets.probe() {
                library.settings.goodXray = path
                save()
            } else if let good = library.settings.goodXray, xrayVersions.contains(where: { $0.path == good }),
                      session.state == .connected {
                let a = Self.newAlert()
                a.messageText = "No traffic passes through the tunnel"
                a.informativeText = "Connected with an Xray version that has not been used before, but a test "
                    + "request did not get through. Switch back to the version that worked and reconnect?"
                a.addButton(withTitle: "Switch Back")
                a.addButton(withTitle: "Keep This Version")
                NSApp.activate()
                guard a.runModal() == .alertFirstButtonReturn else { return }
                library.settings.xrayBinary = good
                save()
                session.reconnect(connectable)
            }
        }
    }

    func selectDataSource(_ source: Assets.DataSource) {
        library.settings.dataSource = source
        save()
        alert("Routing data source changed", "Choose Update Routing Data to download it.")
    }

    /// Networks the system routes outside the tunnel, e.g. a work network reached by another VPN.
    func editExclusions() {
        NSApp.activate()
        let a = Self.newAlert()
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
        guard invalid.isEmpty else { return alert("Not saved", L("Not an IPv4 address or network:") + " " + invalid.joined(separator: ", ")) }
        library.settings.routeExclusions = entries
        saveSelection()
    }

    /// A standard login item (System Settings › General › Login Items), not a launch agent.
    func toggleOpenAtLogin() {
        defer { refresh() }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Could not change Open at Login", error.localizedDescription)
        }
    }

    // MARK: Helper (D28)

    /// Installs (or updates) the root-owned helper: one administrator prompt now, then Connect
    /// asks for Touch ID or the password through the system dialog.
    func installHelper() {
        NSApp.activate()
        let a = Self.newAlert()
        a.messageText = Helper.installed ? "Update the helper?" : "Use Touch ID to connect?"
        a.informativeText = "XrayBar installs a small helper that runs as root (in /Library/Application Support/XrayBar "
            + "and /Library/LaunchDaemons). After that, Connect asks for Touch ID or your password in a "
            + "system dialog, once while XrayBar runs. Diagnostics › Uninstall Helper removes it. You will be asked for your password once now."
        a.addButton(withTitle: Helper.installed ? "Update" : "Install")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn, runHelperInstall() else { return }
        alert("Helper installed", "Connect now asks for Touch ID or your password.")
    }

    /// One administrator prompt; false if cancelled or failed (then with an alert).
    private func runHelperInstall() -> Bool {
        guard let script = Helper.bundledScript else { return false }
        defer { refresh() }
        do {
            try session.runPrivileged([Helper.bundledHelper.path, script.path], detached: false, script: "xraybar-install")
            return true
        } catch is CancellationError {
            return false
        } catch {
            alert("Could not install the helper", error.localizedDescription)
            return false
        }
    }

    func uninstallHelper() {
        guard session.state != .connected, confirmRemove(L("XrayBar helper")) else {
            return session.state == .connected ? alert("Disconnect first", "The helper runs the current connection.") : ()
        }
        do {
            try session.runPrivileged(["--uninstall"], detached: false, script: "xraybar-install")
            refresh()
            alert("Helper removed", "Connect asks for your administrator password again.")
        } catch is CancellationError {
        } catch {
            alert("Could not remove the helper", error.localizedDescription)
        }
    }

    func toggleDetailedLog() {
        library.settings.detailedLog = !(library.settings.detailedLog ?? false)
        saveSelection()
    }

    /// A running session keeps its config; the menu offers Reconnect to apply the change.
    private func saveSelection() {
        save()
        if session.state == .connected { changedWhileConnected = true }
    }

    /// A copied vless:// link (one per line), or a copied image containing QR codes, e.g. a
    /// screenshot taken with ⌘⇧⌃4 (the system tool; XrayBar never captures the screen, D27).
    func importClipboard() {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            importLinks(text.split(whereSeparator: \.isNewline).map(String.init))
        } else if let image = NSImage(pasteboard: pasteboard) {
            importQR(image)
        } else {
            alert("Nothing to import", "Copy a vless:// link, or press ⌘⇧⌃4 and select a QR code on the "
                  + "screen (it goes to the clipboard), then choose this again.")
        }
    }

    private func importQR(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let codes = try? Import.qrCodes(in: cg), !codes.isEmpty
        else { return alert("No QR code found", "The copied image has no readable QR code. With ⌘⇧⌃4, "
                            + "select an area that includes the whole code.") }
        importLinks(codes)
    }

    private func importLinks(_ lines: [String]) {
        let links = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            let profiles = try links.map(Import.profile(fromLink:))
            guard !profiles.isEmpty else { return alert("Nothing to import", "Copy a vless:// link first.") }
            let known = profiles.filter { p in library.profiles.contains { $0.address == p.address && $0.port == p.port && $0.uuid == p.uuid } }
            Import.merge((profiles, []), into: &library)
            if library.selectedProfile == nil { library.selectedProfile = profiles.first?.id }
            save()
            // Name what was recognized, so a scan of an existing server still shows it worked.
            let new = profiles.filter { p in !known.contains { $0.uuid == p.uuid && $0.address == p.address } }
            alert(new.isEmpty ? "Already in your servers" : "Server added",
                  (new + known).map { "\($0.name) — \($0.address):\($0.port)" + (new.contains($0) ? "" : " " + L("(already added)")) }
                      .joined(separator: "\n"))
        } catch {
            alert("Import failed", error.localizedDescription)
        }
    }

    func importV2rayN() {
        do {
            let imported = try Import.fromV2rayN()
            let added = Import.merge(imported, into: &library)
            save()
            alert("Imported from v2rayN", String(format: L("%ld new item(s): %ld VLESS server(s), %ld routing set(s) found. "
                                                             + "v2rayN was only read, not changed."),
                                                 added, imported.profiles.count, imported.routing.count))
        } catch {
            alert("Import failed", error.localizedDescription)
        }
    }

    /// Option-alternate of Share Server…: the vless:// link straight to the clipboard.
    func copyServerLink() {
        guard let profile = library.profile else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Import.link(for: profile), forType: .string)
    }

    /// The selected server as a QR code and link, e.g. to add it on a phone.
    func shareServer() {
        guard let profile = library.profile else { return }
        let link = Import.link(for: profile)
        NSApp.activate()
        let a = Self.newAlert()
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

    /// The app icon, set explicitly: the bundle's icon, or the SF Symbol when run unbundled.
    static func newAlert() -> NSAlert {
        let a = LocalizedAlert()
        a.icon = NSApp.applicationIconImage
        return a
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

    func showLog() {
        guard FileManager.default.fileExists(atPath: Store.logFile.path) else {
            return alert("No log yet", "The log appears after the first connection.")
        }
        NSWorkspace.shared.open(Store.logFile)
    }

    func showDataFolder() {
        try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([Store.libraryFile])
    }

    /// The standard About panel: icon, name, version and build from Info.plist, copyright, credits.
    func showAbout() {
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                                    .foregroundColor: NSColor.secondaryLabelColor]
        let credits = NSMutableAttributedString(string: L("A menu-bar client for Xray-core's native TUN.") + "\n", attributes: small)
        credits.append(NSAttributedString(string: "github.com/heaprip/xraybar", attributes:
            small.merging([.link: URL(string: "https://github.com/heaprip/xraybar")!]) { $1 }))
        credits.append(NSAttributedString(string: "\n" + L("Xray-core is a separate program (MPL-2.0)."), attributes: small))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func quit() {
        session.disconnect()      // the root session also stops by itself when the app exits
        NSApp.terminate(nil)
    }

    private func save() {
        do { try Store.save(library) } catch { alert("Could not save", error.localizedDescription) }
    }

    private func alert(_ title: String, _ text: String) {
        appLog.notice("\(title, privacy: .public): \(text)")
        NSApp.activate()
        let a = Self.newAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

/// Every alert's title, text and buttons are translated just before it shows (D47), so the
/// English text above stays the one place to read; formatted texts are translated where built.
final class LocalizedAlert: NSAlert {
    override func runModal() -> NSApplication.ModalResponse {
        messageText = L(messageText)
        informativeText = L(informativeText)
        buttons.forEach { $0.title = L($0.title) }
        return super.runModal()
    }
}
