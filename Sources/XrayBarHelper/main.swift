// XrayBarHelper — XrayBar's root side, installed once as a LaunchDaemon (docs/DECISIONS.md D28).
//
// launchd starts it when XrayBar connects to /var/run/xraybar-helper.sock; it exits when idle.
// One JSON request per connection, one JSON reply:
//   {"action": "connect", "auth": <AuthorizationExternalForm, base64>, "args": [session args]}
//       macOS authorizes the connecting user for io.github.heaprip.xraybar.connect with its own dialog
//       (Touch ID or password). Then the root-owned session script starts with those arguments,
//       except the app PID, which is taken from the socket peer, not from the request.
//   {"action": "restore"}
//       Runs the session script's clean-up after a session that died. No authorization needed.
// Everything it runs as root lives in /Library/Application Support/XrayBar, owned by root.

import Darwin
import Foundation
import Security

let script = "/Library/Application Support/XrayBar/xraybar-session.sh"
let right = "io.github.heaprip.xraybar.connect"

// MARK: Socket from launchd; serve until 20 s without requests.

let sockets = UnsafeMutablePointer<UnsafeMutablePointer<Int32>>.allocate(capacity: 1)
var socketCount = 0
guard launch_activate_socket("Listener", sockets, &socketCount) == 0, socketCount > 0 else {
    FileHandle.standardError.write(Data("XrayBarHelper must be started by launchd\n".utf8))
    exit(1)
}
let listener = sockets.pointee[0]

while true {
    var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
    guard poll(&ready, 1, 20_000) > 0 else { exit(0) }
    let client = accept(listener, nil, nil)
    guard client >= 0 else { continue }
    var timeout = timeval(tv_sec: 5, tv_usec: 0)   // a client that stops sending cannot hold us
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    reply(client, handle(client))
    close(client)
}

// MARK: Requests

func handle(_ client: Int32) -> [String: Any] {
    guard let request = try? JSONSerialization.jsonObject(with: readAll(client)) as? [String: Any] else {
        return ["ok": false, "error": "bad request"]
    }
    switch request["action"] as? String {
    case "connect":
        let status = authorize(request["auth"] as? String ?? "")
        guard status == errAuthorizationSuccess else {
            return ["ok": false, "cancelled": status == errAuthorizationCanceled,
                    "error": "not authorized (\(status))"]
        }
        guard var args = request["args"] as? [String], args.count >= 6 else { return ["ok": false, "error": "bad arguments"] }
        args[4] = String(peerPID(client))   // the session ends when this process exits
        return run(args, wait: false)
    case "restore":
        return run(["--restore"], wait: true)
    default:
        return ["ok": false, "error": "unknown action"]
    }
}

/// Asks macOS whether the client's user may connect. With interaction allowed, the system
/// shows its authentication dialog in the user's session; the answer comes to this process.
func authorize(_ base64: String) -> OSStatus {
    guard let data = Data(base64Encoded: base64), data.count == MemoryLayout<AuthorizationExternalForm>.size else {
        return errAuthorizationInvalidRef
    }
    var external = AuthorizationExternalForm()
    withUnsafeMutableBytes(of: &external) { _ = data.copyBytes(to: $0) }
    var auth: AuthorizationRef?
    let created = AuthorizationCreateFromExternalForm(&external, &auth)
    guard created == errAuthorizationSuccess, let auth else { return created }
    defer { AuthorizationFree(auth, []) }
    return right.withCString { name in
        var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
        return withUnsafeMutablePointer(to: &item) { items in
            var rights = AuthorizationRights(count: 1, items: items)
            return AuthorizationCopyRights(auth, &rights, nil, [.interactionAllowed, .extendRights], nil)
        }
    }
}

/// The session script under /bin/bash. A session runs detached (launchd's AbandonProcessGroup
/// keeps it alive after the helper exits); a restore is waited for.
func run(_ args: [String], wait: Bool) -> [String: Any] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [script] + args
    p.standardOutput = FileHandle.nullDevice
    let errors = Pipe()
    p.standardError = wait ? errors : FileHandle.nullDevice
    do { try p.run() } catch { return ["ok": false, "error": "\(error)"] }
    guard wait else { return ["ok": true] }
    let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    return p.terminationStatus == 0 ? ["ok": true] : ["ok": false, "error": text]
}

// MARK: Socket helpers

func peerPID(_ socket: Int32) -> pid_t {
    var pid: pid_t = 0
    var length = socklen_t(MemoryLayout<pid_t>.size)
    getsockopt(socket, SOL_LOCAL, LOCAL_PEERPID, &pid, &length)
    return pid
}

/// Reads until the client closes its side, at most 64 KB.
func readAll(_ socket: Int32) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count < 65_536 {
        let n = read(socket, &buffer, buffer.count)
        guard n > 0 else { break }
        data.append(buffer, count: n)
    }
    return data
}

func reply(_ socket: Int32, _ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    data.withUnsafeBytes { _ = write(socket, $0.baseAddress, $0.count) }
}
