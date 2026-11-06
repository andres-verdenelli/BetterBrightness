#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_root="${TMPDIR:-/tmp}/BetterBrightness-sidebar-preview"
mkdir -p "$preview_root"
preview_root="$(cd "$preview_root" && pwd -P)"
preview_app="$preview_root/Build/Products/Debug/BetterBrightness.app"
preview_executable="$preview_app/Contents/MacOS/BetterBrightness"
preview_log="$preview_root/build.log"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
echo "Building isolated UI preview…"
if ! xcodebuild -project "$repo_root/BetterBrightness.xcodeproj" \
    -scheme BetterBrightness -configuration Debug -derivedDataPath "$preview_root" \
    PRODUCT_BUNDLE_IDENTIFIER=andydev.BetterBrightness.sidebarPreview \
    CODE_SIGN_IDENTITY=- build > "$preview_log" 2>&1; then
    tail -n 80 "$preview_log"
    exit 1
fi
codesign --verify --deep --strict "$preview_app"

# Restart only this preview executable, including launches with extra arguments.
while read -r process_id executable; do
    if [[ "$executable" == "$preview_executable" ]]; then
        kill "$process_id"
        for attempt in {1..30}; do
            if ! kill -0 "$process_id" 2>/dev/null; then break; fi
            sleep 0.1
        done
        if kill -0 "$process_id" 2>/dev/null; then
            echo "The previous preview did not exit; close it and rerun." >&2
            exit 1
        fi
    fi
done < <(ps -axo pid=,comm=)

open -n "$preview_app" --args --preview-settings
echo "Opened preview: $preview_app"
echo "Build log: $preview_log"
