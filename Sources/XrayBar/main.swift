// XrayBar — a menu-bar control panel for Xray-core's native TUN on macOS.
// Start reading at 1-Model.swift. This file only starts the app.

import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
    let menuBar = MenuBar()
    withExtendedLifetime(menuBar) { app.run() }
}
