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
SKIP_GUI_SMOKE=0
AUDIT_CANDIDATE=0
AUDIT_OUTPUT=""
AUDIT_SOURCE_URL=""
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
  --dmg <path>          Use an existing ChatGPT DMG
  --output <path>       Install output directory (default: $DEFAULT_OUTPUT_DIR)
  --skip-cli-install    Do not attempt Codex CLI discovery/update
  --skip-gui-smoke      Skip the pre-promotion GUI smoke (expert/headless use)
  --audit-candidate     Audit a future candidate without installing it
  --audit-output <path> Write candidate evidence here (default: temporary)
  --audit-source-url <url>
                         Record the source URL for a local audit DMG
  -h, --help            Show this help
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
    --skip-gui-smoke)
      SKIP_GUI_SMOKE=1
      shift
      ;;
    --audit-candidate)
      AUDIT_CANDIDATE=1
      shift
      ;;
    --audit-output)
      [[ $# -ge 2 && -n "$2" ]] || die "--audit-output requires a path"
      AUDIT_OUTPUT="$2"
      shift 2
      ;;
    --audit-source-url)
      [[ $# -ge 2 && -n "$2" ]] || die "--audit-source-url requires a URL"
      AUDIT_SOURCE_URL="$2"
      shift 2
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

if (( AUDIT_CANDIDATE )); then
  (( SKIP_GUI_SMOKE == 0 )) ||
    die "--skip-gui-smoke is not applicable to --audit-candidate"
  if [[ -n "$DMG_PATH" && -z "$AUDIT_SOURCE_URL" ]]; then
    die "--audit-source-url is required with --audit-candidate --dmg"
  fi
  if [[ -n "$AUDIT_SOURCE_URL" ]]; then
    case "$AUDIT_SOURCE_URL" in
      http://*|https://*) ;;
      *) die "--audit-source-url must be an HTTP(S) URL" ;;
    esac
  fi
  if [[ -z "$AUDIT_OUTPUT" ]]; then
    AUDIT_OUTPUT="$(mktemp -d /tmp/chatgpt-linux-audit-XXXXXX)"
  else
    case "$AUDIT_OUTPUT" in
      /*) ;;
      *) AUDIT_OUTPUT="$SCRIPT_DIR/$AUDIT_OUTPUT" ;;
    esac
    mkdir -p "$AUDIT_OUTPUT" || die "cannot create audit output: $AUDIT_OUTPUT"
    AUDIT_OUTPUT="$(cd "$AUDIT_OUTPUT" && pwd -P)"
  fi
else
  [[ -z "$AUDIT_OUTPUT" ]] ||
    die "--audit-output requires --audit-candidate"
  [[ -z "$AUDIT_SOURCE_URL" ]] ||
    die "--audit-source-url requires --audit-candidate"
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
fi

WORK_DIR="$(mktemp -d /tmp/chatgpt-linux-install-XXXXXX)"
if (( AUDIT_CANDIDATE == 0 )); then
  STAGING_DIR="${OUTPUT_DIR}.staging.$$"
fi
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
DMG_SOURCE_URL="$DEFAULT_DMG_URL"
if (( AUDIT_CANDIDATE )); then
  if [[ -n "$DMG_PATH" ]]; then
    [[ -f "$DMG_PATH" ]] || die "DMG not found: $DMG_PATH"
    DMG_SOURCE_URL="$AUDIT_SOURCE_URL"
  else
    audit_candidate_dir="$(mktemp -d "$AUDIT_OUTPUT/candidate-XXXXXXXX")" ||
      die "cannot create a unique audit candidate directory"
    DMG_PATH="$audit_candidate_dir/candidate.dmg"
    if command -v curl >/dev/null 2>&1; then
      EXPECTED_DMG_BYTES="$(remote_content_length "$DEFAULT_DMG_URL" 2>/dev/null || true)"
    fi
    log "Downloading the audit candidate with bounded retries"
    download_resumable \
      "$DEFAULT_DMG_URL" "$DMG_PATH" "$EXPECTED_DMG_BYTES" ||
      die "failed to download the audit candidate"
  fi
else
  log "Loading the repository's current release contract"
  load_current_release_contract "$SCRIPT_DIR/compatibility" "$NODE_BIN" ||
    die "unable to load the current release contract"
  success "Selected release contract: compatibility/${RELEASE_CONTRACT_PATH#"$SCRIPT_DIR/compatibility/"}"
  DEFAULT_DMG_URL="$RELEASE_DMG_URL"
  DMG_SOURCE_URL="$RELEASE_DMG_URL"
  EXPECTED_DMG_BYTES="$RELEASE_DMG_BYTES"

  if [[ -n "$DMG_PATH" ]]; then
    [[ -f "$DMG_PATH" ]] || die "DMG not found: $DMG_PATH"
  else
    DMG_PATH="$DEFAULT_DMG_PATH"
    if verify_file_identity \
      "$DMG_PATH" "$RELEASE_DMG_BYTES" "$RELEASE_DMG_SHA256" \
      >"$WORK_DIR/cached-dmg-identity.log" 2>&1; then
      success "Using the cached DMG verified for the selected release contract"
    else
      resume_compatible=0
      if command -v curl >/dev/null 2>&1; then
        remote_contract_bytes="$(require_remote_size_matches_contract \
          "$RELEASE_DMG_URL" "$RELEASE_DMG_BYTES")" ||
          die "the mutable remote endpoint no longer serves the selected release; supply its verified cached DMG with --dmg"
        [[ "$remote_contract_bytes" == "$RELEASE_DMG_BYTES" ]] &&
          resume_compatible=1
      fi
      if [[ -f "$DMG_PATH" ]]; then
        cached_bytes=$(stat -c%s "$DMG_PATH")
        if (( resume_compatible == 0 || cached_bytes >= RELEASE_DMG_BYTES )); then
          quarantine_path=$(quarantine_file "$DMG_PATH" identity-mismatch) ||
            die "failed to quarantine an identity-incompatible cache"
          warn "preserved an identity-incompatible cache at $quarantine_path"
        fi
      fi
      log "Downloading or resuming the selected release DMG with bounded retries"
      download_resumable \
        "$RELEASE_DMG_URL" "$DMG_PATH" "$RELEASE_DMG_BYTES" ||
        die "failed to download the selected release DMG"
    fi
  fi

  verify_file_identity \
    "$DMG_PATH" "$RELEASE_DMG_BYTES" "$RELEASE_DMG_SHA256" ||
    die "DMG does not match the current release contract"
fi

DMG_PATH="$(cd "$(dirname "$DMG_PATH")" && pwd -P)/$(basename "$DMG_PATH")"
success "Using DMG: $DMG_PATH"

log "Validating DMG archive integrity"
if ! validate_dmg "$DMG_PATH" "$EXPECTED_DMG_BYTES" \
  >"$WORK_DIR/7zip-test.log" 2>&1; then
  tail -n 40 "$WORK_DIR/7zip-test.log" >&2 || true
  die "incomplete or invalid DMG: $DMG_PATH"
fi
success "DMG integrity verified"

DMG_BYTES="$(stat -c%s "$DMG_PATH")"
DMG_SHA256="$(sha256sum "$DMG_PATH" | awk '{print $1}')"

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
if (( AUDIT_CANDIDATE )); then
  validate_chatgpt_payload ||
    die "ChatGPT.app payload validation failed"
else
  validate_chatgpt_payload "$CHATGPT_BUNDLE_ID" ||
    die "ChatGPT.app payload validation failed"
fi

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

[[ -f "$APP_SOURCE/package.json" ]] ||
  die "extracted app is missing package.json"

APP_BUNDLE_ID="$(plist_value "$CHATGPT_PLIST" CFBundleIdentifier)"
APP_ARCHITECTURE="$(detect_macos_app_architecture \
  "$CHATGPT_APP_ROOT" "$CHATGPT_PLIST")" ||
  die "unsupported candidate architecture"
TARGET_ARCHITECTURE="$(normalize_linux_arch)" ||
  die "unsupported target Linux architecture"
APP_MAIN_ENTRY="$("$NODE_BIN" -e \
  'const p=require(process.argv[1]); process.stdout.write(p.main || "")' \
  "$APP_SOURCE/package.json")"
ELECTRON_RUNTIME_VERSION="$("$NODE_BIN" -e \
  'const p=require(process.argv[1]); process.stdout.write(p.devDependencies?.electron || "")' \
  "$APP_SOURCE/package.json")"
[[ -n "$APP_MAIN_ENTRY" ]] || die "candidate package is missing its main entry"
[[ -n "$ELECTRON_RUNTIME_VERSION" ]] ||
  die "candidate package is missing its Electron version"

if (( AUDIT_CANDIDATE )); then
  write_candidate_audit_evidence \
    "$AUDIT_OUTPUT" "$APP_VERSION" "$APP_BUILD" "$APP_BUNDLE_ID" \
    "$APP_ARCHITECTURE" "$ELECTRON_RUNTIME_VERSION" "$APP_MAIN_ENTRY" \
    "$DMG_BYTES" "$DMG_SHA256" "$DMG_SOURCE_URL" ||
    die "failed to write candidate audit evidence"
  success "Candidate audit complete; no installation or output promotion occurred"
  printf '\nCandidate evidence: %s/candidate-evidence.json\n' "$AUDIT_OUTPUT"
  printf 'Candidate DMG:      %s\n\n' "$DMG_PATH"
  exit 0
fi

validate_contract_payload \
  "$APP_ARCHITECTURE" "$TARGET_ARCHITECTURE" \
  "$ELECTRON_RUNTIME_VERSION" "$APP_MAIN_ENTRY" ||
  die "ChatGPT.app does not match the current release contract"
success "Extracted application metadata and required paths match the release contract"

[[ -d "$APP_SOURCE/.vite" ]] || die "extracted app is missing .vite"
[[ -d "$APP_SOURCE/webview" ]] || die "extracted app is missing webview"

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

write_chatgpt_launcher "$STAGING_DIR" "$NODE_BIN" "$NPM_BIN" ||
  die "launcher generation failed"

if command -v codex >/dev/null 2>&1; then
  CLI_PATH_USED="$(command -v codex)"
  CLI_VERSION_USED="$(codex --version 2>/dev/null || printf unknown)"
  success "Codex CLI: $CLI_PATH_USED ($CLI_VERSION_USED)"
elif (( SKIP_CLI_INSTALL )); then
  CLI_PATH_USED="$STAGING_DIR/bin/codex-fallback"
  CLI_VERSION_USED="npm exec @openai/codex@latest (fallback)"
  warn "Codex CLI discovery skipped; launcher will use its recorded-runtime fallback"
else
  CLI_PATH_USED="$STAGING_DIR/bin/codex-fallback"
  CLI_VERSION_USED="npm exec @openai/codex@latest (fallback)"
  warn "Codex CLI not found; launcher will use its recorded-runtime fallback"
fi

"$NODE_BIN" - "$STAGING_DIR/build-info.json" \
  "$INSTALLER_VERSION" "$APP_VERSION" "$APP_BUILD" \
  "$ELECTRON_RUNTIME_VERSION" "$APP_MAIN_ENTRY" \
  "$DMG_PATH" "$DMG_SHA256" "$DMG_BYTES" \
  "$NODE_BIN" "$NPM_BIN" "$NODE_VERSION" \
  "$CLI_PATH_USED" "$CLI_VERSION_USED" \
  "compatibility/${RELEASE_CONTRACT_PATH#"$SCRIPT_DIR/compatibility/"}" <<'NODE'
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
  dmgBytes,
  nodePath,
  npmPath,
  nodeVersion,
  cliPath,
  cliVersion,
  releaseContract,
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
  dmgBytes: Number(dmgBytes),
  nodePath,
  npmPath,
  nodeVersion,
  cliPath,
  cliVersion,
  releaseContract,
};
fs.writeFileSync(outputPath, JSON.stringify(payload, null, 2) + "\n");
NODE

if [[ -e "$OUTPUT_DIR" ]]; then
  if [[ ! -d "$OUTPUT_DIR" ||
        ! -f "$OUTPUT_DIR/build-info.json" ||
        ! -f "$OUTPUT_DIR/$CHATGPT_LAUNCHER_NAME" ]]; then
    die "refusing to replace a directory not recognized as generated ChatGPT Linux output: $OUTPUT_DIR"
  fi
fi

log "Validating staging native modules with the Electron ABI"
if (( SKIP_GUI_SMOKE )); then
  warn "GUI smoke will be skipped by explicit expert request"
else
  log "Running bounded GUI smoke from staging with remote control disabled"
fi
validate_and_promote_staging \
  "$STAGING_DIR" "$OUTPUT_DIR" "$SKIP_GUI_SMOKE" "$WORK_DIR/gui-smoke.log" || {
  tail -n 80 "$WORK_DIR/gui-smoke.log" >&2 2>/dev/null || true
  die "staging validation or promotion failed; current output was not replaced"
}
STAGING_DIR=""
if (( SKIP_GUI_SMOKE )); then
  success "Staging native validation passed before promotion; GUI smoke was skipped"
else
  success "Staging native/GUI validation passed before promotion"
fi
if [[ -n "$PREVIOUS_DIR" && -e "$PREVIOUS_DIR" ]]; then
  success "Previous output preserved for rollback: $PREVIOUS_DIR"
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
