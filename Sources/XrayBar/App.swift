// XrayBar — a menu-bar control panel for Xray-core's native TUN on macOS.
// Start reading at 1-Model.swift. This file only starts the app.

import OSLog
import SwiftUI

/// Unified logging (Console.app, or `log stream --predicate 'subsystem == "io.github.heaprip.xraybar"'`).
/// Dynamic text is private by default, so server names and addresses show as <private>.
let appLog = Logger(subsystem: "io.github.heaprip.xraybar", category: "app")

/// Text in the user's language: Support/<lang>.lproj/Localizable.strings, keyed by the English
/// text itself, so a missing translation shows English (D47). The menu's SwiftUI literals are
/// looked up the same way by SwiftUI; formats use %@ and %ld.
func L(_ english: String) -> String { Bundle.main.localizedString(forKey: english, value: nil, table: nil) }

@main
struct XrayBarApp: App {
    // A plain constant: SwiftUI creates the App once. (@State is a macro in the macOS 27 SDK
    // whose plugin the Command Line Tools do not ship.)
    private let model: AppModel

    init() {
        // Started by Session.runPrivileged to show the administrator prompt: no UI of its own.
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--admin" {
            exit(Session.adminChild(CommandLine.arguments[2]))
        }
        // One instance only: a second one would run its own sessions against the same files.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        // Run without a bundle (swift run), alerts would show a folder icon; the .app has AppIcon.icns.
        if !Bundle.main.bundlePath.hasSuffix(".app") {
            NSApplication.shared.applicationIconImage = Mark.image(filled: [0, 1, 2, 3])
        }
        model = AppModel()
    }

    var body: some Scene {
        // A standard menu (8-Menu.swift), as the HIG asks for menu bar extras.
        MenuBarExtra {
            AppMenu(model: model)
        } label: {
            Image(nsImage: Mark.image(filled: model.markPetals, badge: model.helperOutdated))   // badge: D43
                .accessibilityLabel(model.statusText)   // VoiceOver: "Connected — …"
        }
    }
}
