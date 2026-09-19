#!/bin/bash
# Builds build/XrayBar.app from source: release build, app bundle, ad-hoc signature.
# Command Line Tools only. Install by copying the app to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin=$(swift build -c release --show-bin-path)
app=build/XrayBar.app

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
cp "$bin/XrayBar" "$app/Contents/MacOS/XrayBar"
cp "$bin/XrayBarHelper" "$app/Contents/MacOS/XrayBarHelper"   # installed as root only on request (D28)
# SwiftPM looks for the resource bundle (the session script) in Contents/Resources.
cp -R "$bin/XrayBar_XrayBar.bundle" "$app/Contents/Resources/"
# The icon is drawn from source at build time (no binary images in the repository).
iconset=$(mktemp -d)/AppIcon.iconset
swift scripts/make-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$iconset")"

# Ad-hoc signature: seals the bundle so any later change to it (including the root script)
# is detectable with `codesign --verify`. Not a Developer ID; see docs/SECURITY.md.
codesign --force --sign - "$app"
codesign --verify --strict "$app"

echo "Built $app"
echo "Install: rm -rf /Applications/XrayBar.app && cp -R $app /Applications/"
