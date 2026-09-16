#!/bin/bash
# Deterministic inventory of everything security-relevant in XrayBar. No network, no AI.
# Compare its output with the table in docs/SECURITY.md. Exit code 1 if the size budget fails.
set -u
cd "$(dirname "$0")/.."

SWIFT_BUDGET=1200   # lines in Sources/, excluding blank lines
SHELL_BUDGET=150    # lines in the privileged script, excluding blank lines

section() { printf '\n== %s\n' "$1"; }
find_code() { grep -rnE "$1" Sources --include='*.swift' --include='*.sh' || echo "  (none)"; }

section "Size budget"
swift_lines=$(cat Sources/XrayBar/*.swift | grep -cv '^[[:space:]]*$')
shell_lines=$(grep -cv '^[[:space:]]*$' Sources/XrayBar/Resources/xraybar-session.sh)
echo "Swift: $swift_lines / $SWIFT_BUDGET    privileged script: $shell_lines / $SHELL_BUDGET"
fail=0
(( swift_lines <= SWIFT_BUDGET )) || { echo "FAIL: Swift budget exceeded"; fail=1; }
(( shell_lines <= SHELL_BUDGET )) || { echo "FAIL: script budget exceeded"; fail=1; }

section "Files in the repository that are not source, docs or config"
git ls-files | grep -vE '\.(swift|md|sh|json|plist)$|^\.gitignore$|^LICENSE$' || echo "  (none)"

section "Declared package dependencies"
grep -n 'dependencies' Package.swift

section "Privilege: administrator prompt / sudo / root-only tools"
find_code 'administrator privileges|sudo|AuthorizationExecute|SMJobBless|SMAppService'

section "Process execution"
find_code 'Process\(\)|posix_spawn|NSTask|system\(|popen|executableURL'

section "Networking (expected: only 7-Assets.swift, run when the user asks)"
find_code 'URLSession|NSURLConnection|import Network|CFSocket|socket\(|/dev/tcp|curl |wget '

section "Hard-coded URLs and hosts"
find_code 'https?://'

section "Dynamic code and obfuscation-like constructs"
find_code 'dlopen|dlsym|NSClassFromString|perform\(|JavaScriptCore|eval |base64|Data\(base64'

section "File writes outside the app's own directory"
find_code 'write\(to:|createFile|moveItem|removeItem|install |> ?"|>>'

section "Commands run as root (every command in the privileged script)"
grep -nE '^\s*[a-z_]+=?|networksetup|route |kill |install |rm ' Sources/XrayBar/Resources/xraybar-session.sh \
    | grep -vE '^\s*[0-9]+:\s*#' | grep -E 'networksetup|route |kill |install |rm |XRAY' || true

exit $fail
