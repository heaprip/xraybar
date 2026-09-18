// XrayBar — a menu-bar control panel for Xray-core's native TUN on macOS.
// Start reading at 1-Model.swift. This file only starts the app.

import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
    // Run without a bundle (swift run), alerts would show a folder icon; the .app has AppIcon.icns.
    if !Bundle.main.bundlePath.hasSuffix(".app") {
        let symbol = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
            .applying(.init(hierarchicalColor: .controlAccentColor))
        app.applicationIconImage = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "XrayBar")?
            .withSymbolConfiguration(symbol)
    }
    let menuBar = MenuBar()
    withExtendedLifetime(menuBar) { app.run() }
}
