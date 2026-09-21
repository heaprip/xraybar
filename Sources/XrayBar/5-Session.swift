// 5. Session — connect and disconnect.
//
// Connect: write config -> validate it with xray -> run xraybar-session.sh as root through
// the standard administrator prompt. From then on the root script owns xray, routes and DNS.
// Validation and the wait for Touch ID run off the main thread, so the menu stays responsive.
// Disconnect: create the stop file; the script stops xray and restores DNS by itself.
// The app never signals a process it did not start and never looks processes up by name (D5).

import AppKit
import CryptoKit
import Security

@MainActor
final class Session {
    enum State: Equatable {
        case disconnected, connecting, connected, disconnecting
        case failed(String)
    }

    private(set) var state: State = .disconnected
    var onChange: () -> Void = {}
    /// Checks the short transitions (connecting, disconnecting) twice a second.
    private var timer: Timer?
    /// Otherwise kqueue reports when xray or its session ends; nothing runs meanwhile (D42).
    private var exits: [DispatchSourceProcess] = []
    private var connectStarted = Date.distantPast
    /// Set by `reconnect`: connect again with this library once the old session is gone.
    private var pendingConnect: Library?

    init() {
        if Self.runningPID() != nil { state = .connected }
        track()
    }

    /// Watching a process needs no rights over it (root's xray included) and sends it nothing.
    /// Events that happen during sleep are delivered on wake.
    private func track() {
        timer?.invalidate()
        exits.forEach { $0.cancel() }
        exits = []
        switch state {
        case .connecting, .disconnecting:
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                MainActor.assumeIsolated { self.poll() }
            }
            timer?.tolerance = 0.2
        case .connected, .disconnected, .failed:
            for pid in [Self.runningPID(), Self.pid(in: Store.sessionPidFile)].compactMap({ $0 }) {
                let exit = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
                exit.setEventHandler { MainActor.assumeIsolated { self.poll() } }
                exit.resume()
                exits.append(exit)
            }
            DispatchQueue.main.async { self.poll() }   // one may have ended before it was watched
        }
    }

    // MARK: Connect

    /// `library.settings.xrayBinary` is the resolved xray from the root-owned store (AppModel).
    func connect(_ library: Library) {
        guard let profile = library.profile else { return fail("Add a profile first.") }
        guard !profile.uuid.isEmpty else {
            return fail("The server's credentials are in your keychain, which XrayBar could not read. "
                        + "Quit and reopen XrayBar, then allow access when macOS asks.")
        }
        guard let xray = library.settings.xrayBinary else {
            return fail("No Xray installed yet. Choose Xray › Download \(Assets.testedXray), or Copy Xray from v2rayN.")
        }
        if let other = Self.otherTunnel() {
            return fail("Another VPN or TUN (\(other)) already routes all traffic, for example v2rayN in TUN mode. "
                        + "Turn it off, then connect again.")
        }
        let s = library.settings
        let config = XrayConfig.make(profile: profile, routing: library.routing, settings: s, ipv6: Self.hasGlobalIPv6())
        connectStarted = .distantFuture   // no start timeout while validating or waiting for Touch ID
        set(.connecting)
        Task {
            do {
                try Store.write(XrayConfig.data(config), to: Store.configFile)
                let test = try XrayConfig.data(XrayConfig.validationCopy(config))
                try await Task.detached { try Self.validate(test, xray: xray, assets: s.assetsDir) }.value
                guard state == .connecting else { return }   // Disconnect chosen meanwhile
                try? FileManager.default.removeItem(at: Store.stopFile)
                let args = [xray, s.assetsDir, Store.configFile.path, Store.stopFile.path,
                            String(ProcessInfo.processInfo.processIdentifier)] + s.systemDNS
                if Helper.installed { try await Task.detached { try Helper.connect(args) }.value }
                else { try runPrivileged(args) }
                connectStarted = Date()
            } catch is CancellationError {
                set(.disconnected)
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    /// Xray new enough for native TUN routing, and `xray run -test` on the config (with TUN
    /// swapped out: creating a utun needs root). Blocks; runs off the main thread.
    nonisolated private static func validate(_ config: Data, xray path: String, assets: String) throws {
        let line = try Assets.versionLine(ofXray: path)
        guard Assets.version(line).lexicographicallyPrecedes(Assets.minimumXray) == false else {
            throw NSError(domain: "XrayBar", code: 4, userInfo: [NSLocalizedDescriptionKey:
                "\(line.split(separator: " ").prefix(2).joined(separator: " ")) is too old for native TUN on macOS "
                + "(needs \(Assets.minimumXray.map(String.init).joined(separator: ".")) or newer). "
                + "Choose one in Xray Version."])
        }

        let file = Store.dir.appendingPathComponent("config.test.json")
        try Store.write(config, to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let xray = Process()
        xray.executableURL = URL(fileURLWithPath: path)
        xray.arguments = ["run", "-test", "-c", file.path]
        xray.environment = ["XRAY_LOCATION_ASSET": assets]
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
    func runPrivileged(_ arguments: [String], detached: Bool = true, script name: String = "xraybar-session",
                       prompt: String? = nil) throws {
        guard let script = Bundle.module.url(forResource: name, withExtension: "sh") else {
            throw NSError(domain: "XrayBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "Session script missing"])
        }
        let command = "/bin/bash " + ([script.path] + arguments).map(Self.shellQuoted).joined(separator: " ")
            + (detached ? " >/dev/null 2>&1 &" : "")
        let source = "do shell script \"\(Self.appleScriptEscaped(command))\" with administrator privileges"
            + (prompt.map { " with prompt \"\(Self.appleScriptEscaped($0))\"" } ?? "")

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
            if Helper.installed { try Helper.request(["action": "restore"], authorize: false) }
            else { try runPrivileged(["--restore"], detached: false) }
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

    /// A globally routable IPv6 address (2000::/3) on an interface that is up, not a tunnel.
    /// Without one nothing can leak over IPv6, and IPv6 sent into the tunnel could not get out
    /// (v2rayN decides the same way). If the interfaces cannot be read: assume one.
    nonisolated static func hasGlobalIPv6() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return true }
        defer { freeifaddrs(list) }
        return sequence(first: first, next: { $0.pointee.ifa_next }).contains {
            let i = $0.pointee
            guard let address = i.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET6),
                  i.ifa_flags & UInt32(IFF_UP) != 0, i.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  !String(cString: i.ifa_name).hasPrefix("utun") else { return false }
            let byte = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr.__u6_addr.__u6_addr8.0 }
            return byte & 0xE0 == 0x20
        }
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
        case .connected where Self.needsRestore, .disconnecting where Self.needsRestore:
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
        if case .failed(let message) = new { appLog.error("Failed: \(message)") }
        else { appLog.info("State: \(String(describing: new), privacy: .public)") }
        track()
        onChange()
    }

    private func fail(_ message: String) { set(.failed(message)) }
}

/// Talks to the installed LaunchDaemon helper (D28) over its socket. Only used when installed.
enum Helper {
    static let plist = "/Library/LaunchDaemons/io.github.heaprip.xraybar.helper.plist"
    static let installedDir = "/Library/Application Support/XrayBar"
    static let socket = "/var/run/xraybar-helper.sock"
    static var installed: Bool { FileManager.default.fileExists(atPath: plist) }

    /// Bundled helper and session script, to install or to compare with the installed copies.
    static var bundledHelper: URL { Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("XrayBarHelper") }
    static var bundledScript: URL? { Bundle.module.url(forResource: "xraybar-session", withExtension: "sh") }

    /// The installed copies differ from this app's (the app was updated), or the authorization
    /// right predates D44 (timeout 0; without the key macOS reports its default, INT32_MAX).
    static var outdated: Bool {
        guard installed, let script = bundledScript else { return false }
        var rule: CFDictionary?
        let right = AuthorizationRightGet("io.github.heaprip.xraybar.connect", &rule) == errAuthorizationSuccess
        return hash(bundledHelper.path) != hash(installedDir + "/XrayBarHelper")
            || hash(script.path) != hash(installedDir + "/xraybar-session.sh")
            || !right || (rule as? [String: Any])?["timeout"] as? Int == 0
    }

    /// One authorization for the app's lifetime: the helper's check stores the credential in it
    /// (the right is not shared), so Touch ID is asked at the first Connect of each run (D44).
    nonisolated(unsafe) private static let authorization: AuthorizationRef? = {
        var auth: AuthorizationRef?
        return AuthorizationCreate(nil, nil, [], &auth) == errAuthorizationSuccess ? auth : nil
    }()

    private static func hash(_ path: String) -> String? {
        (try? Data(contentsOf: URL(fileURLWithPath: path))).map { SHA256.hash(data: $0).description }
    }

    /// Starts a session; the helper asks for Touch ID or the password first. Blocks until then.
    static func connect(_ args: [String]) throws { try request(["action": "connect", "args": args], authorize: true) }

    /// Sends one request; with `authorize`, includes an (empty) authorization for the helper to
    /// check with the system dialog. Blocks until the helper answers.
    static func request(_ body: [String: Any], authorize: Bool) throws {
        var body = body
        if authorize {
            guard let auth = authorization else { throw failure("Authorization failed") }
            var external = AuthorizationExternalForm()
            AuthorizationMakeExternalForm(auth, &external)
            body["auth"] = withUnsafeBytes(of: &external) { Data($0) }.base64EncodedString()
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure("socket failed") }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { socket.utf8CString.withUnsafeBytes($0.copyMemory) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw failure("The helper is not responding. Reinstall it: Diagnostics › Uninstall Helper, then Use Touch ID to Connect.") }
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        shutdown(fd, SHUT_WR)

        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while case let n = read(fd, &buffer, buffer.count), n > 0 { reply.append(buffer, count: n) }
        let answer = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] ?? [:]
        if answer["ok"] as? Bool == true { return }
        if answer["cancelled"] as? Bool == true { throw CancellationError() }
        throw failure(answer["error"] as? String ?? "The helper did not answer")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "XrayBar", code: 20, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
