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
        // One instance only: a second one would run its own sessions against the same files.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        // Run without a bundle (swift run), alerts would show a folder icon; the .app has AppIcon.icns.
        if !Bundle.main.bundlePath.hasSuffix(".app") {
            let symbol = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
                .applying(.init(hierarchicalColor: .controlAccentColor))
            NSApplication.shared.applicationIconImage = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "XrayBar")?
                .withSymbolConfiguration(symbol)
        }
        model = AppModel()
    }

    var body: some Scene {
        // A standard menu (8-Menu.swift), as the HIG asks for menu bar extras.
        MenuBarExtra {
            AppMenu(model: model)
        } label: {
            Image(systemName: model.iconName)
                .accessibilityLabel(model.statusText)   // VoiceOver: "Connected — …", not "shield"
        }
    }
}
