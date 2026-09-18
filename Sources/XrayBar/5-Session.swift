// 5. Session — connect and disconnect.
//
// Connect: write config -> validate it with xray -> run xraybar-session.sh as root through
// the standard administrator prompt. From then on the root script owns xray, routes and DNS.
// Disconnect: create the stop file; the script stops xray and restores DNS by itself.
// The app never signals a process it did not start and never looks processes up by name (D5).

import AppKit

@MainActor
final class Session {
    enum State: Equatable {
        case disconnected, connecting, connected, disconnecting
        case failed(String)
    }

    private(set) var state: State = .disconnected
    var onChange: () -> Void = {}
    private var timer: Timer?
    private var connectStarted = Date.distantPast
    /// Set by `reconnect`: connect again with this library once the old session is gone.
    private var pendingConnect: Library?

    init() {
        if Self.runningPID() != nil { state = .connected }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
    }

    // MARK: Connect

    func connect(_ library: Library) {
        guard let profile = library.profile else { return fail("Add a profile first.") }
        if let other = Self.otherTunnel() {
            return fail("Another VPN or TUN (\(other)) already routes all traffic, for example v2rayN in TUN mode. "
                        + "Turn it off, then connect again.")
        }
        do {
            let config = XrayConfig.make(profile: profile, routing: library.routing, settings: library.settings)
            try Store.write(XrayConfig.data(config), to: Store.configFile)
            try validate(XrayConfig.validationCopy(config), settings: library.settings)
            try? FileManager.default.removeItem(at: Store.stopFile)
            let s = library.settings
            try runPrivileged([s.xrayPath, s.assetsDir, Store.configFile.path, Store.stopFile.path,
                               String(ProcessInfo.processInfo.processIdentifier)] + s.systemDNS)
            connectStarted = Date()
            set(.connecting)
        } catch is CancellationError {
            set(.disconnected)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Xray new enough for native TUN routing, and `xray run -test` on the config (with TUN
    /// swapped out: creating a utun needs root).
    private func validate(_ config: XrayConfig.JSON, settings: Settings) throws {
        let line = try Assets.versionLine(ofXray: settings.xrayPath)
        guard Assets.version(line).lexicographicallyPrecedes(Assets.minimumXray) == false else {
            throw NSError(domain: "XrayBar", code: 4, userInfo: [NSLocalizedDescriptionKey:
                "\(line.split(separator: " ").prefix(2).joined(separator: " ")) is too old for native TUN on macOS "
                + "(needs \(Assets.minimumXray.map(String.init).joined(separator: ".")) or newer). "
                + "Choose one in Xray Version."])
        }

        let file = Store.dir.appendingPathComponent("config.test.json")
        try Store.write(XrayConfig.data(config), to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let xray = Process()
        xray.executableURL = URL(fileURLWithPath: settings.xrayPath)
        xray.arguments = ["run", "-test", "-c", file.path]
        xray.environment = ["XRAY_LOCATION_ASSET": settings.assetsDir]
        let output = Pipe()
        xray.standardOutput = output
        xray.standardError = output
        try xray.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        xray.waitUntilExit()
        guard xray.terminationStatus == 0 else {
            throw NSError(domain: "XrayBar", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Xray rejected the configuration:\n" + text.split(separator: "\n").suffix(3).joined(separator: "\n")])
        }
    }

    /// The only path to root. Every argument is single-quoted for the shell; the whole
    /// command is then escaped into an AppleScript string. A session runs detached.
    private func runPrivileged(_ arguments: [String], detached: Bool = true) throws {
        guard let script = Bundle.module.url(forResource: "xraybar-session", withExtension: "sh") else {
            throw NSError(domain: "XrayBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "Session script missing"])
        }
        let command = "/bin/bash " + ([script.path] + arguments).map(Self.shellQuoted).joined(separator: " ")
            + (detached ? " >/dev/null 2>&1 &" : "")
        let source = "do shell script \"\(Self.appleScriptEscaped(command))\" with administrator privileges"

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            if error[NSAppleScript.errorNumber] as? Int == -128 {   // user pressed Cancel
                throw CancellationError()
            }
            throw NSError(domain: "XrayBar", code: 3, userInfo: [NSLocalizedDescriptionKey:
                error[NSAppleScript.errorMessage] as? String ?? "Administrator prompt failed"])
        }
    }

    nonisolated static func shellQuoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    nonisolated static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: Leftovers of a session that died (power loss, killed script)

    /// DNS still overridden with nothing running, or xray running without its session.
    static var needsRestore: Bool {
        let xray = runningPID() != nil
        return (!xray && FileManager.default.fileExists(atPath: Store.dnsSavedFile.path))
            || (xray && pid(in: Store.sessionPidFile) == nil)
    }

    /// Stops a leftover xray and restores DNS (one administrator prompt).
    func restore() {
        do {
            try runPrivileged(["--restore"], detached: false)
            set(.disconnected)
        } catch is CancellationError {
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Disconnect, then connect with the new settings (a new administrator prompt).
    func reconnect(_ library: Library) {
        pendingConnect = library
        disconnect()
    }

    // MARK: Disconnect

    func disconnect() {
        guard Self.runningPID() != nil || state == .connecting else { return set(.disconnected) }
        FileManager.default.createFile(atPath: Store.stopFile.path, contents: nil)
        set(.disconnecting)
    }

    // MARK: Status

    /// The utun interface that currently carries internet traffic, if it is not ours. Two
    /// tunnels cannot both own the same routes ("failed to add system route … file exists").
    static func otherTunnel() -> String? {
        guard runningPID() == nil else { return nil }
        let route = Process()
        route.executableURL = URL(fileURLWithPath: "/sbin/route")
        route.arguments = ["-n", "get", "1.1.1.1"]
        let out = Pipe()
        route.standardOutput = out
        route.standardError = FileHandle.nullDevice
        guard (try? route.run()) != nil else { return nil }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        route.waitUntilExit()
        let interface = text.split(separator: "\n").first { $0.contains("interface:") }?
            .split(separator: " ").last.map(String.init)
        return interface?.hasPrefix("utun") == true ? interface : nil
    }

    /// PID written by the root session, if that process is alive. `kill(pid, 0)` on a root
    /// process from a user process fails with EPERM, which still means "exists".
    static func runningPID() -> pid_t? { pid(in: Store.pidFile) }

    private static func pid(in file: URL) -> pid_t? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0
        else { return nil }
        return kill(pid, 0) == 0 || errno == EPERM ? pid : nil
    }

    static func logTail(_ lines: Int = 5) -> String {
        let text = (try? String(contentsOf: Store.logFile, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }

    private func poll() {
        let running = Self.runningPID() != nil
        switch state {
        case .connecting where running:
            // The session works on its own root-owned copy by now; don't keep credentials around.
            try? FileManager.default.removeItem(at: Store.configFile)
            set(.connected)
        case .connecting where Date().timeIntervalSince(connectStarted) > 15:
            fail("Xray did not start.\n\n" + Self.logTail())
        case .connected where !running:
            fail("Xray stopped unexpectedly.\n\n" + Self.logTail())
        case .disconnecting where !running:
            try? FileManager.default.removeItem(at: Store.stopFile)
            set(.disconnected)
            if let library = pendingConnect { pendingConnect = nil; connect(library) }
        case .disconnecting where Self.needsRestore:
            fail("The session stopped responding. Use Restore Network Settings in the menu.")
        case .disconnected where running, .failed where running:
            set(.connected)   // e.g. connected before this app instance started
        default:
            break
        }
    }

    private func set(_ new: State) {
        guard new != state else { return }
        state = new
        onChange()
    }

    private func fail(_ message: String) { set(.failed(message)) }
}
