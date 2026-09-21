#!/bin/bash
# Deterministic inventory of everything security-relevant in XrayBar. No network, no AI.
# Compare its output with the table in docs/SECURITY.md. Exit code 1 if the size budget fails.
set -u
cd "$(dirname "$0")/.."

SWIFT_BUDGET=1700   # lines in Sources/XrayBar, excluding blank lines (1200 → 1400 D23 → 1500 D29 → 1600 D31 → 1700 D45)
HELPER_BUDGET=180   # lines in the root helper (Sources/XrayBarHelper), excluding blank lines (150 → 180 D42)
SHELL_BUDGET=270    # lines in the root scripts (session + install), excluding blank lines (220 → 250 D38 → 270 D42)

section() { printf '\n== %s\n' "$1"; }
find_code() { grep -rnE "$1" Sources --include='*.swift' --include='*.sh' || echo "  (none)"; }

section "Size budget"
swift_lines=$(cat Sources/XrayBar/*.swift | grep -cv '^[[:space:]]*$')
helper_lines=$(cat Sources/XrayBarHelper/*.swift | grep -cv '^[[:space:]]*$')
shell_lines=$(cat Sources/XrayBar/Resources/*.sh | grep -cv '^[[:space:]]*$')
echo "App Swift: $swift_lines / $SWIFT_BUDGET    root helper: $helper_lines / $HELPER_BUDGET    root scripts: $shell_lines / $SHELL_BUDGET"
fail=0
(( swift_lines <= SWIFT_BUDGET )) || { echo "FAIL: Swift budget exceeded"; fail=1; }
(( helper_lines <= HELPER_BUDGET )) || { echo "FAIL: helper budget exceeded"; fail=1; }
(( shell_lines <= SHELL_BUDGET )) || { echo "FAIL: script budget exceeded"; fail=1; }

section "Files in the repository that are not source, docs or config"
git ls-files | grep -vE '\.(swift|md|sh|json|plist)$|^\.gitignore$|^LICENSE$|^docs/images/.*\.png$' || echo "  (none)"

section "Declared package dependencies"
grep -n 'dependencies' Package.swift

section "Privilege: administrator prompt / sudo / root-only tools"
find_code 'administrator privileges|sudo|AuthorizationExecute|SMJobBless|SMAppService'

section "Process execution"
find_code 'Process\(\)|posix_spawn|NSTask|system\(|popen|executableURL'

section "Networking (expected: only 7-Assets.swift, run when the user asks)"
find_code 'URLSession|NSURLConnection|import Network|CFSocket|socket\(|/dev/tcp|curl |wget '

section "Screen capture (expected: none)"
find_code 'ScreenCaptureKit|SCScreenshotManager|SCStream\(|screencapture|CGWindowListCreateImage|CGDisplayCreateImage'

section "Hard-coded URLs and hosts"
find_code 'https?://'

section "Dynamic code and obfuscation-like constructs"
find_code 'dlopen|dlsym|NSClassFromString|perform\(|JavaScriptCore|eval |base64|Data\(base64'

section "File writes outside the app's own directory"
find_code 'write\(to:|createFile|moveItem|removeItem|install |> ?"|>>'

section "Commands run as root (every command in the root scripts)"
grep -nE '^\s*[a-z_]+=?|networksetup|route |kill |install |rm |launchctl|authorizationdb' Sources/XrayBar/Resources/*.sh \
    | grep -vE '^\s*[0-9]+:\s*#' | grep -E 'networksetup|route |kill |install |rm |launchctl|authorizationdb|XRAY' || true

exit $fail
