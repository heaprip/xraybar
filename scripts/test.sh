#!/bin/bash
# Runs the tests. Works around a Command Line Tools SwiftPM bug: the test target's separate
# emit-module job is built without the Swift Testing macro plugin ("plugin for module
# 'TestingMacros' not found"), so the plugin directory is passed explicitly.
#   scripts/test.sh                 unit tests
#   scripts/test.sh --integration   also run configs from your local v2rayN through xray (read-only)
set -eu
cd "$(dirname "$0")/.."
plugins="$(dirname "$(dirname "$(xcrun --find swift)")")/lib/swift/host/plugins/testing"
[[ ${1:-} == --integration ]] && export XRAYBAR_INTEGRATION=1
exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins"
