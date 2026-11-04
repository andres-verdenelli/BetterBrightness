#!/bin/bash
# Personal updates from GitHub; compatible with the Bash shipped by macOS.
set -euo pipefail

usage() {
    cat <<'EOF'
Uso: bash scripts/update-local.sh [--build-only]

Actualiza /Applications/BetterBrightness.app desde origin/main.
Descarga el código, ejecuta sus pruebas, compila y verifica una firma local.
Conserva la app anterior en ~/Library/Application Support/BetterBrightness/Backups.
No modifica tu rama, archivos de trabajo, preferencias ni opciones de inicio.

  --build-only  Verifica y compila sin cerrar ni reemplazar la app instalada.
  --help        Muestra esta ayuda.
EOF
}

fail() { echo "Error: $*" >&2; exit 1; }

sandbox_mode() {
    local entitlements sandbox_value
    entitlements="$(codesign -d --entitlements - --xml "$1" 2>/dev/null)" \
        || fail "No pude leer los permisos de $1."
    if [[ -z "$entitlements" ]]; then
        echo NO
        return
    fi
    printf '%s' "$entitlements" | plutil -lint - >/dev/null \
        || fail "No pude interpretar los permisos de $1."
    sandbox_value="$(printf '%s' "$entitlements" | /usr/libexec/PlistBuddy -c Print:com.apple.security.app-sandbox /dev/stdin 2>/dev/null || true)"
    if [[ "$sandbox_value" == true ]]; then echo YES; else echo NO; fi
}

build_only=false
case "${1:-}" in
    "") ;;
    --build-only) build_only=true ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || fail "Usá una sola opción."

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
installed_app="/Applications/BetterBrightness.app"
bundle_id="andydev.BetterBrightness"
process_pattern='^/Applications/BetterBrightness[.]app/Contents/MacOS/BetterBrightness($| )'

[[ "$(uname -s)" == Darwin ]] || fail "Este script requiere macOS."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun --find xcodebuild >/dev/null || fail "Instalá Xcode o indicá DEVELOPER_DIR."
[[ "$(git -C "$repo_root" remote get-url origin)" =~ ^(https://github.com/andres-verdenelli/BetterBrightness(\.git)?|git@github.com:andres-verdenelli/BetterBrightness(\.git)?)$ ]] \
    || fail "origin debe apuntar al repositorio andres-verdenelli/BetterBrightness."

# A change in sandbox mode changes where UserDefaults reads the user's settings.
# Preserve the installed mode; new installations use the project's sandbox.
sandbox=YES
if [[ -e "$installed_app" ]]; then
    [[ -d "$installed_app" && ! -L "$installed_app" ]] || fail "La app instalada no es un bundle normal."
    [[ "$(/usr/libexec/PlistBuddy -c Print:CFBundleIdentifier "$installed_app/Contents/Info.plist")" == "$bundle_id" ]] \
        || fail "La app instalada tiene otro identificador."
    signature="$(codesign -dv "$installed_app" 2>&1)" || fail "No pude leer la firma instalada."
    [[ "$signature" == *"Signature=adhoc"* ]] \
        || fail "La app instalada usa otra firma. Este script solo reemplaza builds locales con firma ad hoc."
    sandbox="$(sandbox_mode "$installed_app")"
fi

lock_dir="${TMPDIR:-/tmp}/BetterBrightnessUpdate-${UID}.lock"
mkdir "$lock_dir" 2>/dev/null || fail "Ya hay una actualización en curso (lock: $lock_dir)."
work_dir=""
stage_dir=""
keep_build=false
was_running=false
cleanup() {
    result=$?
    trap - EXIT
    if [[ -n "$stage_dir" && -d "$stage_dir/Previous.app" ]]; then
        if [[ ! -e "$installed_app" ]] && mv "$stage_dir/Previous.app" "$installed_app"; then
            echo "Se restauró la app anterior." >&2
            if $was_running; then open "$installed_app" || true; fi
        else
            echo "La app anterior sigue disponible en $stage_dir/Previous.app" >&2
        fi
    fi
    if [[ -n "$stage_dir" && ! -e "$stage_dir/Previous.app" ]]; then rm -rf "$stage_dir"; fi
    if [[ -n "$work_dir" ]] && ! $keep_build; then rm -rf "$work_dir"; fi
    rmdir "$lock_dir" || true
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/BetterBrightnessUpdate.XXXXXX")"
echo "Descargando main de GitHub…"
git -C "$repo_root" fetch --no-tags origin refs/heads/main
commit="$(git -C "$repo_root" rev-parse --verify 'FETCH_HEAD^{commit}')"
short_commit="${commit:0:12}"
if ! $build_only && [[ -d "$installed_app" ]]; then
    installed_commit="$(/usr/libexec/PlistBuddy -c Print:BetterBrightnessGitCommit "$installed_app/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$installed_commit" == "$commit" ]]; then
        echo "BetterBrightness ya está actualizada a main ($short_commit)."
        exit 0
    fi
fi
build_number="$(git -C "$repo_root" rev-list --count "$commit")"
mkdir "$work_dir/source"
git -C "$repo_root" archive "$commit" | tar -x -C "$work_dir/source"
cat >"$work_dir/BuildMetadata.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>BetterBrightnessGitCommit</key><string>$commit</string>
</dict></plist>
EOF

echo "Ejecutando pruebas de ${short_commit}…"
TMPDIR="$work_dir/" bash "$work_dir/source/Tests/run.sh"
echo "Compilando Release (sandbox: $sandbox)…"
if ! xcodebuild \
    -project "$work_dir/source/BetterBrightness.xcodeproj" \
    -scheme BetterBrightness \
    -configuration Release \
    -derivedDataPath "$work_dir/build" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_APP_SANDBOX="$sandbox" \
    CURRENT_PROJECT_VERSION="$build_number" \
    "INFOPLIST_FILE=$work_dir/BuildMetadata.plist" \
    build >"$work_dir/build.log" 2>&1; then
    cat "$work_dir/build.log" >&2
    fail "La compilación falló. La app instalada sigue intacta."
fi
built_app="$work_dir/build/Build/Products/Release/BetterBrightness.app"
codesign --verify --deep --strict "$built_app"
[[ "$(sandbox_mode "$built_app")" == "$sandbox" ]] || fail "La compilación cambió el modo de sandbox."
[[ "$(/usr/libexec/PlistBuddy -c Print:CFBundleIdentifier "$built_app/Contents/Info.plist")" == "$bundle_id" ]] \
    || fail "La compilación tiene otro identificador."
[[ "$(/usr/libexec/PlistBuddy -c Print:BetterBrightnessGitCommit "$built_app/Contents/Info.plist")" == "$commit" ]] \
    || fail "No se pudo registrar el commit compilado."

if $build_only; then
    keep_build=true
    echo "Build verificado de $short_commit: $built_app"
    echo "La app instalada sigue intacta. Los archivos temporales quedan en $work_dir"
    exit 0
fi

# Copy and verify before stopping the app. Staging beside it permits renames
# on the same filesystem, and leaves the old bundle recoverable on failure.
stage_dir="$(mktemp -d /Applications/.BetterBrightness-update.XXXXXX)"
ditto "$built_app" "$stage_dir/BetterBrightness.app"
codesign --verify --deep --strict "$stage_dir/BetterBrightness.app"
if [[ -d "$installed_app" ]]; then
    backup_dir="$HOME/Library/Application Support/BetterBrightness/Backups/$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$backup_dir"
    ditto "$installed_app" "$backup_dir/BetterBrightness.app"
    echo "Copia anterior: $backup_dir/BetterBrightness.app"
fi

running_pid="$(pgrep -f "$process_pattern")" || {
    result=$?
    [[ $result -eq 1 ]] || fail "No pude comprobar si la app está ejecutándose."
}
if [[ -n "$running_pid" ]]; then
    was_running=true
    osascript -e 'tell application "/Applications/BetterBrightness.app" to quit'
    for ((attempt=0; attempt<20; attempt++)); do
        if pgrep -f "$process_pattern" >/dev/null; then
            sleep 0.5
        else
            result=$?
            [[ $result -eq 1 ]] || fail "No pude comprobar el cierre de la app."
            break
        fi
    done
    if pgrep -f "$process_pattern" >/dev/null; then
        fail "La app no se cerró. Cerrala y volvé a ejecutar el script."
    else
        result=$?
        [[ $result -eq 1 ]] || fail "No pude comprobar el cierre de la app."
    fi
fi

if [[ -d "$installed_app" ]]; then mv "$installed_app" "$stage_dir/Previous.app"; fi
mv "$stage_dir/BetterBrightness.app" "$installed_app"
# The durable backup is now the recovery copy; the staging copy is redundant.
rm -rf "$stage_dir/Previous.app"
open "$installed_app"
echo "BetterBrightness actualizada a main ($short_commit)."
