#!/bin/bash
# Builds build/XrayBar.app from source: release build, app bundle, ad-hoc signature.
# Command Line Tools only. Install by copying the app to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM (CLT, new build system) sometimes misses a source edited moments before a build;
# refreshing the timestamps makes the release build always compile what is on disk.
touch Sources/*/*.swift Sources/XrayBar/Resources/*
swift build -c release
bin=$(swift build -c release --show-bin-path)
app=build/XrayBar.app

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
# Build number (shown in About as "0.2.0 (57)"): the commit count, so every build is distinct.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$app/Contents/Info.plist"
cp "$bin/XrayBar" "$app/Contents/MacOS/XrayBar"
cp "$bin/XrayBarHelper" "$app/Contents/MacOS/XrayBarHelper"   # installed as root only on request (D28)
cp -R Support/*.lproj "$app/Contents/Resources/"   # UI translations (D47)
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
