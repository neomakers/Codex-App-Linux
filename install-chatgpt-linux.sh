#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# shellcheck source=lib/chatgpt-installer.sh
source "$SCRIPT_DIR/lib/chatgpt-installer.sh"

DEFAULT_DMG_URL="https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
DEFAULT_DMG_PATH="$SCRIPT_DIR/ChatGPT-latest.dmg"
DEFAULT_OUTPUT_DIR="$SCRIPT_DIR/$CHATGPT_OUTPUT_BASENAME"
INSTALLER_VERSION="2026.08.01-chatgpt-app"

DMG_PATH=""
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
SKIP_CLI_INSTALL=0
WORK_DIR=""
STAGING_DIR=""
PREVIOUS_DIR=""

log() {
  printf '[*] %s\n' "$*" >&2
}

success() {
  printf '[✓] %s\n' "$*" >&2
}

warn() {
  printf '[!] %s\n' "$*" >&2
}

die() {
  installer_error "$*" || true
  exit 1
}

usage() {
  cat <<USAGE
ChatGPT Linux Installer (Unofficial)

Builds ChatGPT Linux from the current official ChatGPT.app DMG payload.

Usage:
  ./install-chatgpt-linux.sh [options]

Options:
  --dmg <path>       Use an existing ChatGPT DMG
  --output <path>    Install output directory (default: $DEFAULT_OUTPUT_DIR)
  --skip-cli-install Do not attempt Codex CLI discovery/update
  -h, --help         Show this help
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --dmg)
      [[ $# -ge 2 && -n "$2" ]] || die "--dmg requires a path"
      DMG_PATH="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 && -n "$2" ]] || die "--output requires a path"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-cli-install)
      SKIP_CLI_INSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$SCRIPT_DIR/$OUTPUT_DIR" ;;
esac
output_name="$(basename -- "$OUTPUT_DIR")"
[[ "$output_name" != "." && "$output_name" != ".." ]] ||
  die "unsafe output path: $OUTPUT_DIR"
output_parent="$(dirname -- "$OUTPUT_DIR")"
mkdir -p "$output_parent" || die "cannot create output parent: $output_parent"
OUTPUT_DIR="$(cd "$output_parent" && pwd -P)/$output_name"
[[ "$OUTPUT_DIR" != "/" && "$OUTPUT_DIR" != "$SCRIPT_DIR" ]] ||
  die "refusing unsafe output directory: $OUTPUT_DIR"

WORK_DIR="$(mktemp -d /tmp/chatgpt-linux-install-XXXXXX)"
STAGING_DIR="${OUTPUT_DIR}.staging.$$"
TOOLCHAIN_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/chatgpt-linux/toolchain"
mkdir -p "$TOOLCHAIN_DIR" ||
  die "cannot create non-root toolchain cache: $TOOLCHAIN_DIR"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e

  if [[ -n "$STAGING_DIR" &&
        "$STAGING_DIR" == "$OUTPUT_DIR.staging."* &&
        -e "$STAGING_DIR" ]]; then
    rm -rf -- "$STAGING_DIR"
  fi

  if [[ -n "$PREVIOUS_DIR" &&
        "$PREVIOUS_DIR" == "$OUTPUT_DIR.previous."* &&
        -e "$PREVIOUS_DIR" &&
        ! -e "$OUTPUT_DIR" ]]; then
    mv -- "$PREVIOUS_DIR" "$OUTPUT_DIR"
  fi

  if [[ -n "$WORK_DIR" &&
        "$WORK_DIR" == /tmp/chatgpt-linux-install-* &&
        -d "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
  fi

  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '\nChatGPT Linux Installer (Unofficial)\n'
printf 'Installer version: %s\n\n' "$INSTALLER_VERSION"

log "Resolving Node.js $MIN_NODE_VERSION or newer"
resolve_node "$TOOLCHAIN_DIR" ||
  die "unable to resolve a supported Node.js runtime"
NODE_VERSION="$("$NODE_BIN" --version)"
NPM_VERSION="$("$NPM_BIN" --version)"
success "Node.js $NODE_VERSION; npm $NPM_VERSION"

log "Resolving 7-Zip without sudo"
resolve_7zip "$TOOLCHAIN_DIR" || die "unable to resolve 7-Zip"
success "7-Zip: $SEVEN_ZIP"

EXPECTED_DMG_BYTES=""
using_default_dmg=0
if [[ -n "$DMG_PATH" ]]; then
  [[ -f "$DMG_PATH" ]] || die "DMG not found: $DMG_PATH"
else
  DMG_PATH="$DEFAULT_DMG_PATH"
  using_default_dmg=1

  if command -v curl >/dev/null 2>&1; then
    EXPECTED_DMG_BYTES="$(remote_content_length "$DEFAULT_DMG_URL" 2>/dev/null || true)"
  fi

  needs_download=0
  if [[ ! -f "$DMG_PATH" ]]; then
    needs_download=1
  elif cached_dmg_is_usable "$DMG_PATH" "$EXPECTED_DMG_BYTES" \
       >"$WORK_DIR/cached-dmg-test.log" 2>&1; then
    cached_bytes=$(stat -c%s "$DMG_PATH")
    if [[ -n "$EXPECTED_DMG_BYTES" &&
          "$cached_bytes" != "$EXPECTED_DMG_BYTES" ]]; then
      warn "server DMG changed size; using the existing complete cached release"
      EXPECTED_DMG_BYTES=""
    fi
  else
    needs_download=1
  fi

  if (( needs_download )); then
    if [[ -f "$DMG_PATH" && -n "$EXPECTED_DMG_BYTES" ]] &&
       (( $(stat -c%s "$DMG_PATH") >= EXPECTED_DMG_BYTES )); then
      mv -- "$DMG_PATH" "$WORK_DIR/invalid-cached.dmg"
      warn "discarding an invalid full-size DMG cache before a fresh download"
    fi
    log "Downloading or resuming the current ChatGPT DMG"
    download_resumable "$DEFAULT_DMG_URL" "$DMG_PATH" ||
      die "failed to download a complete ChatGPT DMG"
  fi
fi

DMG_PATH="$(cd "$(dirname "$DMG_PATH")" && pwd -P)/$(basename "$DMG_PATH")"
success "Using DMG: $DMG_PATH"

log "Validating DMG integrity"
if ! validate_dmg "$DMG_PATH" "$EXPECTED_DMG_BYTES" \
  >"$WORK_DIR/7zip-test.log" 2>&1; then
  tail -n 40 "$WORK_DIR/7zip-test.log" >&2 || true
  die "incomplete or invalid DMG: $DMG_PATH"
fi
success "DMG integrity verified"

DMG_SHA256="unknown"
if command -v sha256sum >/dev/null 2>&1; then
  DMG_SHA256="$(sha256sum "$DMG_PATH" | awk '{print $1}')"
fi

EXTRACTED_DIR="$WORK_DIR/extracted"
mkdir -p "$EXTRACTED_DIR"
log "Extracting the complete ChatGPT.app payload"
extract_status=0
"$SEVEN_ZIP" x "$DMG_PATH" "-o$EXTRACTED_DIR" -y \
  >"$WORK_DIR/7zip-extract.log" 2>&1 || extract_status=$?
if (( extract_status != 0 )); then
  if extraction_log_has_only_ignored_links "$WORK_DIR/7zip-extract.log"; then
    warn "7-Zip safely ignored out-of-tree symbolic links from the macOS image"
  else
    tail -n 60 "$WORK_DIR/7zip-extract.log" >&2 || true
    die "failed to extract DMG"
  fi
fi

discover_chatgpt_payload "$EXTRACTED_DIR" ||
  die "unsupported DMG layout"
validate_chatgpt_payload ||
  die "ChatGPT.app payload validation failed"

APP_VERSION="$(plist_value "$CHATGPT_PLIST" CFBundleShortVersionString)"
APP_BUILD="$(plist_value "$CHATGPT_PLIST" CFBundleVersion)"
[[ -n "$APP_VERSION" ]] || die "missing ChatGPT app version in Info.plist"
[[ -n "$APP_BUILD" ]] || die "missing ChatGPT app build in Info.plist"
success "Found ChatGPT.app $APP_VERSION (build $APP_BUILD)"

APP_SOURCE="$WORK_DIR/app-source"
log "Extracting app.asar with @electron/asar 4.2.1"
"$NPM_BIN" exec --yes @electron/asar@4.2.1 -- \
  extract "$CHATGPT_ASAR" "$APP_SOURCE" ||
  die "ASAR extraction failed"

cp -a "$CHATGPT_ASAR_UNPACKED/." "$APP_SOURCE/" ||
  die "failed to merge app.asar.unpacked"

[[ -d "$APP_SOURCE/.vite" ]] || die "extracted app is missing .vite"
[[ -d "$APP_SOURCE/webview" ]] || die "extracted app is missing webview"
[[ -f "$APP_SOURCE/package.json" ]] ||
  die "extracted app is missing package.json"

GENERATED_PACKAGE="$WORK_DIR/package.generated.json"
"$NODE_BIN" "$SCRIPT_DIR/tools/generate-chatgpt-package.mjs" \
  "$APP_SOURCE/package.json" "$GENERATED_PACKAGE" "$APP_VERSION" ||
  die "Linux package metadata generation failed"

APP_MAIN_ENTRY="$("$NODE_BIN" -e \
  'const p=require(process.argv[1]); process.stdout.write(p.main)' \
  "$GENERATED_PACKAGE")"
ELECTRON_RUNTIME_VERSION="$("$NODE_BIN" -e \
  'const p=require(process.argv[1]); process.stdout.write(p.devDependencies.electron)' \
  "$GENERATED_PACKAGE")"
[[ -f "$APP_SOURCE/$APP_MAIN_ENTRY" ]] ||
  die "declared main entry is missing: $APP_MAIN_ENTRY"

[[ ! -e "$STAGING_DIR" ]] ||
  die "staging path already exists: $STAGING_DIR"
mkdir -p "$STAGING_DIR"

log "Preparing staged ChatGPT Linux application"
cp -a "$APP_SOURCE/." "$STAGING_DIR/" ||
  die "failed to copy extracted application"
rm -rf -- "$STAGING_DIR/node_modules"
rm -f -- "$STAGING_DIR/package-lock.json" "$STAGING_DIR/npm-shrinkwrap.json"
cp "$GENERATED_PACKAGE" "$STAGING_DIR/package.json"

if [[ -d "$CHATGPT_RESOURCES/plugins" ]]; then
  rm -rf -- "$STAGING_DIR/plugins"
  cp -a "$CHATGPT_RESOURCES/plugins" "$STAGING_DIR/plugins" ||
    die "failed to copy bundled plugins"
fi

if [[ -f "$CHATGPT_RESOURCES/codexTemplate.png" ]]; then
  cp "$CHATGPT_RESOURCES/codexTemplate.png" "$STAGING_DIR/icon.png"
elif [[ -f "$CHATGPT_RESOURCES/icon.png" ]]; then
  cp "$CHATGPT_RESOURCES/icon.png" "$STAGING_DIR/icon.png"
fi

PATCH_ENGINE="$SCRIPT_DIR/tools/patch-chatgpt-linux.mjs"
[[ -f "$PATCH_ENGINE" ]] || die "patch engine not found: $PATCH_ENGINE"
chrome_plugin_source="$CHATGPT_RESOURCES/plugins/openai-bundled/plugins/chrome"
if [[ -d "$chrome_plugin_source" ]]; then
  export CODEX_CHROME_PLUGIN_SOURCE="$chrome_plugin_source"
fi

log "Applying current Linux feature patches"
"$NODE_BIN" "$PATCH_ENGINE" "$STAGING_DIR" ||
  die "required Linux patch failed"

install_dependencies_once() (
  cd "$STAGING_DIR"
  "$NPM_BIN" install --no-audit --no-fund --ignore-scripts
)

install_electron_runtime_once() (
  cd "$STAGING_DIR"
  "$NODE_BIN" node_modules/electron/install.js
)

rebuild_native_modules_once() (
  cd "$STAGING_DIR"
  "$NPM_BIN" exec --yes @electron/rebuild@4.0.3 -- --force
)

log "Installing Electron $ELECTRON_RUNTIME_VERSION dependencies without native install scripts"
retry_command 3 3 "dependency installation" install_dependencies_once ||
  die "dependency installation failed"

log "Ensuring the Electron $ELECTRON_RUNTIME_VERSION runtime is downloaded"
retry_command 3 3 "Electron runtime download" install_electron_runtime_once ||
  die "Electron runtime installation failed"

log "Rebuilding native modules once for Electron $ELECTRON_RUNTIME_VERSION"
retry_command 3 3 "Electron native module rebuild" rebuild_native_modules_once ||
  die "native module rebuild failed"

rm -f -- "$STAGING_DIR/native/sparkle.node"
mkdir -p "$STAGING_DIR/node_modules/electron-liquid-glass"
cat >"$STAGING_DIR/node_modules/electron-liquid-glass/index.js" <<'STUBJS'
const stub = {
  isGlassSupported: () => false,
  enable: () => {},
  disable: () => {},
  setOptions: () => {},
};
module.exports = stub;
module.exports.default = stub;
STUBJS
cat >"$STAGING_DIR/node_modules/electron-liquid-glass/package.json" <<'STUBPKG'
{"name":"electron-liquid-glass","version":"1.0.0","main":"index.js"}
STUBPKG

write_chatgpt_launcher "$STAGING_DIR" ||
  die "launcher generation failed"

if command -v codex >/dev/null 2>&1; then
  CLI_PATH_USED="$(command -v codex)"
  CLI_VERSION_USED="$(codex --version 2>/dev/null || printf unknown)"
  success "Codex CLI: $CLI_PATH_USED ($CLI_VERSION_USED)"
elif (( SKIP_CLI_INSTALL )); then
  CLI_PATH_USED="$STAGING_DIR/bin/codex-fallback"
  CLI_VERSION_USED="npx @openai/codex@latest (fallback)"
  warn "Codex CLI discovery skipped; launcher will use its npx fallback"
else
  CLI_PATH_USED="$STAGING_DIR/bin/codex-fallback"
  CLI_VERSION_USED="npx @openai/codex@latest (fallback)"
  warn "Codex CLI not found; launcher will use its non-root npx fallback"
fi

"$NODE_BIN" - "$STAGING_DIR/build-info.json" \
  "$INSTALLER_VERSION" "$APP_VERSION" "$APP_BUILD" \
  "$ELECTRON_RUNTIME_VERSION" "$APP_MAIN_ENTRY" \
  "$DMG_PATH" "$DMG_SHA256" "$NODE_BIN" "$NODE_VERSION" \
  "$CLI_PATH_USED" "$CLI_VERSION_USED" <<'NODE'
const fs = require("fs");
const [
  outputPath,
  installerVersion,
  chatgptAppVersion,
  chatgptAppBuild,
  electronRuntime,
  mainEntry,
  dmgPath,
  dmgSha256,
  nodePath,
  nodeVersion,
  cliPath,
  cliVersion,
] = process.argv.slice(2);

const payload = {
  generatedAt: new Date().toISOString(),
  installerVersion,
  chatgptAppVersion,
  chatgptAppBuild,
  electronRuntime,
  mainEntry,
  dmgPath,
  dmgSha256,
  nodePath,
  nodeVersion,
  cliPath,
  cliVersion,
};
fs.writeFileSync(outputPath, JSON.stringify(payload, null, 2) + "\n");
NODE

if [[ -e "$OUTPUT_DIR" ]]; then
  if [[ ! -d "$OUTPUT_DIR" ||
        ! -f "$OUTPUT_DIR/build-info.json" ||
        ! -f "$OUTPUT_DIR/$CHATGPT_LAUNCHER_NAME" ]]; then
    die "refusing to replace a directory not recognized as generated ChatGPT Linux output: $OUTPUT_DIR"
  fi
  PREVIOUS_DIR="${OUTPUT_DIR}.previous.$$"
  [[ ! -e "$PREVIOUS_DIR" ]] ||
    die "backup path already exists: $PREVIOUS_DIR"
  mv -- "$OUTPUT_DIR" "$PREVIOUS_DIR" ||
    die "failed to preserve the existing generated output"
fi

if ! mv -- "$STAGING_DIR" "$OUTPUT_DIR"; then
  if [[ -n "$PREVIOUS_DIR" && -e "$PREVIOUS_DIR" ]]; then
    mv -- "$PREVIOUS_DIR" "$OUTPUT_DIR" || true
    PREVIOUS_DIR=""
  fi
  die "failed to finalize staged output"
fi
STAGING_DIR=""

if [[ -n "$PREVIOUS_DIR" && -e "$PREVIOUS_DIR" ]]; then
  rm -rf -- "$PREVIOUS_DIR"
  PREVIOUS_DIR=""
fi

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPLICATIONS_DIR="$DATA_HOME/applications"
DESKTOP_FILE="$APPLICATIONS_DIR/$CHATGPT_DESKTOP_ID"
write_desktop_entry "$OUTPUT_DIR" "$DESKTOP_FILE" ||
  die "desktop entry generation failed"

if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default "$CHATGPT_DESKTOP_ID" x-scheme-handler/codex ||
    warn "could not register the codex:// URL handler"
else
  warn "xdg-mime is unavailable; register x-scheme-handler/codex manually"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi

success "ChatGPT Linux installation complete"
printf '\nInstalled app:  %s\n' "$OUTPUT_DIR"
printf 'App version:    %s (build %s)\n' "$APP_VERSION" "$APP_BUILD"
printf 'Electron:       %s\n' "$ELECTRON_RUNTIME_VERSION"
printf 'Main entry:     %s\n' "$APP_MAIN_ENTRY"
printf 'DMG SHA-256:    %s\n' "$DMG_SHA256"
printf 'Build info:     %s/build-info.json\n' "$OUTPUT_DIR"
printf 'Desktop entry:  %s\n' "$DESKTOP_FILE"
printf 'Launch:         %s/%s\n\n' "$OUTPUT_DIR" "$CHATGPT_LAUNCHER_NAME"
