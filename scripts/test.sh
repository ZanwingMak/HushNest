#!/bin/bash
set -euo pipefail

# 使用可用 iPhone 模拟器执行功能和交互测试，全程不输出测试音频。
run_tests() {
    cd "$(dirname "$0")/.."
    mkdir -p build
    xcodegen generate
    local test_device
    test_device="${SIMULATOR_ID:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; devices=json.load(sys.stdin)["devices"]; print(next(d["udid"] for runtime,items in devices.items() if "iOS" in runtime for d in items if "iPhone" in d["name"]))')}"
    xcrun simctl bootstatus "$test_device" -b
    xcodebuild test -project HushNest.xcodeproj -scheme HushNest \
        -destination "platform=iOS Simulator,id=$test_device" \
        -derivedDataPath build/DerivedData \
        -resultBundlePath "build/Tests-$(date +%Y%m%d-%H%M%S).xcresult" \
        -parallel-testing-enabled NO -test-timeouts-enabled YES \
        -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 180 -retry-tests-on-failure -test-iterations 2 CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO "$@"
}

run_tests "$@"
