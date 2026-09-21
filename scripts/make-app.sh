#!/bin/bash
# Builds build/XrayBar.app from source: release build, app bundle, ad-hoc signature.
# Command Line Tools only. Install by copying the app to /Applications.
# UNIVERSAL=1 builds for Apple silicon and Intel in one binary; that needs Xcode (the release CI).
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM (CLT, new build system) sometimes misses a source edited moments before a build;
# refreshing the timestamps makes the release build always compile what is on disk.
touch Sources/*/*.swift Sources/XrayBar/Resources/*
arch=()
[[ -n ${UNIVERSAL:-} ]] && arch=(--arch arm64 --arch x86_64)
swift build -c release ${arch[@]+"${arch[@]}"}
bin=$(swift build -c release ${arch[@]+"${arch[@]}"} --show-bin-path)
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
# Inside out: the helper first (a universal binary is not signed by the linker), then the app.
codesign --force --sign - "$app/Contents/MacOS/XrayBarHelper"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
# Every architecture must run on the macOS that Info.plist promises (a toolchain may default higher).
min=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")
for b in "$app"/Contents/MacOS/*; do
    vtool -show-build "$b" | awk -v m="$min" '$1 == "minos" && $2 != m {bad=1} END {exit bad}' \
        || { echo "$b: minimum macOS is not $min"; exit 1; }
done
# The session script finds the event watcher at this path (D42); fail here, not at Connect.
res="$app/Contents/Resources/XrayBar_XrayBar.bundle/Contents/Resources"
[[ -f $res/xraybar-session.sh && -x $res/../../../../MacOS/XrayBarHelper ]] || { echo "unexpected bundle layout"; exit 1; }

echo "Built $app"
echo "Install: rm -rf /Applications/XrayBar.app && cp -R $app /Applications/"
