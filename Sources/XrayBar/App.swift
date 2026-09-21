// XrayBar — a menu-bar control panel for Xray-core's native TUN on macOS.
// Start reading at 1-Model.swift. This file only starts the app.

import SwiftUI

@main
struct XrayBarApp: App {
    // A plain constant: SwiftUI creates the App once. (@State is a macro in the macOS 27 SDK
    // whose plugin the Command Line Tools do not ship.)
    private let model: AppModel

    init() {
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
        }
    }
}
