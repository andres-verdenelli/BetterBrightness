#!/bin/bash
set -euo pipefail
test_root="$(cd "$(dirname "$0")/.." && pwd)"
test_output="${TMPDIR:-/tmp}/BetterBrightnessTests"
test_sdk="${BETTERBRIGHTNESS_TEST_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
mkdir -p "$test_output/module-cache"
swiftc -sdk "$test_sdk" -parse-as-library \
  -module-cache-path "$test_output/module-cache" \
  "$test_root/BetterBrightness/BrightnessController.swift" \
  "$test_root/BetterBrightness/ConfigurationStore.swift" \
  "$test_root/BetterBrightness/DiscoveryController.swift" \
  "$test_root/BetterBrightness/WiZDiscoveryService.swift" \
  "$test_root/BetterBrightness/LightDraft.swift" \
  "$test_root/Tests/LightDraftTests.swift" \
  "$test_root/Tests/DiscoveryControllerTests.swift" \
  -o "$test_output/DiscoveryControllerTests"
"$test_output/DiscoveryControllerTests"
swiftc -sdk "$test_sdk" -parse-as-library \
  -module-cache-path "$test_output/module-cache" \
  "$test_root/BetterBrightness/BrightnessRangeControl.swift" \
  "$test_root/Tests/RangeControlTests.swift" \
  -o "$test_output/RangeControlTests"
"$test_output/RangeControlTests"
swiftc -sdk "$test_sdk" -parse-as-library \
  -module-cache-path "$test_output/module-cache" \
  "$test_root/BetterBrightness/LaunchAtLoginController.swift" \
  "$test_root/Tests/LaunchAtLoginTests.swift" \
  -o "$test_output/LaunchAtLoginTests"
"$test_output/LaunchAtLoginTests"
