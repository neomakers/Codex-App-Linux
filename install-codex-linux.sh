#!/bin/bash
#
# Codex Linux Installer (Unofficial)
# Builds a Linux runnable Codex desktop app from the official macOS DMG.
#
# Usage:
#   chmod +x install-codex-linux.sh
#   ./install-codex-linux.sh
#   ./install-codex-linux.sh --dmg /path/to/Codex.dmg
#   ./install-codex-linux.sh --output /path/to/codex-linux
#

set -euo pipefail

if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

if [ -f "$SCRIPT_DIR/codex-linux.sh" ] && [ -d "$SCRIPT_DIR/webview" ]; then
  SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
fi

cd "$SCRIPT_DIR"

DEFAULT_DMG_URL="https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
DEFAULT_PATCH_ENGINE_URL="https://raw.githubusercontent.com/areu01or00/Codex-App-Linux/main/tools/patch-codex-linux.mjs"
DEFAULT_OUTPUT_DIR="$SCRIPT_DIR/codex-linux"
INSTALLER_VERSION="2026.05.25-chrome-host"
WORK_DIR="$(mktemp -d /tmp/codex-linux-install-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

DMG_PATH=""
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
SKIP_CLI_INSTALL="0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[*]${NC} $1" >&2; }
success() { echo -e "${GREEN}[✓]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $1" >&2; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

usage() {
  cat <<USAGE
Codex Linux Installer (Unofficial)

Options:
  --dmg <path>       Use an existing Codex DMG
  --output <path>    Install output directory (default: $DEFAULT_OUTPUT_DIR)
  --skip-cli-install Do not attempt global Codex CLI install/update
  -h, --help         Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dmg)
      DMG_PATH="${2:-}"
      [ -n "$DMG_PATH" ] || error "--dmg requires a path"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:-}"
      [ -n "$OUTPUT_DIR" ] || error "--output requires a path"
      shift 2
      ;;
    --skip-cli-install)
      SKIP_CLI_INSTALL="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      ;;
  esac
done

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Codex Linux Installer (Unofficial)          ║${NC}"
echo -e "${CYAN}║    Frictionless DMG -> Linux app conversion       ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Installer version: $INSTALLER_VERSION"
echo ""

# -----------------------------------------------------------------------------
# Prereqs
# -----------------------------------------------------------------------------
log "Checking prerequisites..."

command -v node >/dev/null 2>&1 || error "Node.js is required (v18+ recommended)."
command -v npm >/dev/null 2>&1 || error "npm is required."
command -v curl >/dev/null 2>&1 || error "curl is required."

success "Node.js: $(node --version)"
success "npm: $(npm --version)"

# -----------------------------------------------------------------------------
# Resolve DMG
# -----------------------------------------------------------------------------
resolve_dmg_path() {
  if [ -n "$DMG_PATH" ]; then
    [ -f "$DMG_PATH" ] || error "DMG not found: $DMG_PATH"
    echo "$DMG_PATH"
    return
  fi

  local candidates=(
    "$SCRIPT_DIR/Codex-latest.dmg"
    "$SCRIPT_DIR/Codex.dmg"
    "$SCRIPT_DIR"/*.dmg
  )

  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      echo "$c"
      return
    fi
  done

  local downloaded="$SCRIPT_DIR/Codex-latest.dmg"
  log "No local DMG found. Downloading latest Codex DMG..."
  curl -fL --retry 3 --connect-timeout 20 -o "$downloaded" "$DEFAULT_DMG_URL" || error "Failed to download DMG from $DEFAULT_DMG_URL"
  echo "$downloaded"
}

DMG_PATH="$(resolve_dmg_path)"
success "Using DMG: $DMG_PATH"
DMG_SHA256="unknown"
if command -v sha256sum >/dev/null 2>&1; then
  DMG_SHA256="$(sha256sum "$DMG_PATH" | awk '{print $1}')"
fi

# -----------------------------------------------------------------------------
# 7zip
# -----------------------------------------------------------------------------
find_7zip() {
  if command -v 7z >/dev/null 2>&1; then
    echo "7z"
    return
  fi
  if command -v 7zz >/dev/null 2>&1; then
    echo "7zz"
    return
  fi

  cat >&2 <<'EOF'

7zip is required to extract the Codex DMG.

Install it, then rerun the installer:

  Ubuntu/Debian: sudo apt install p7zip-full
  Fedora:        sudo dnf install p7zip p7zip-plugins
  Arch:          sudo pacman -S p7zip
  openSUSE:      sudo zypper install p7zip

EOF
  error "7zip not found"
}

SEVEN_ZIP="$(find_7zip)"
success "7zip ready: $SEVEN_ZIP"

# -----------------------------------------------------------------------------
# Extract DMG + ASAR
# -----------------------------------------------------------------------------
log "Extracting DMG..."
"$SEVEN_ZIP" x "$DMG_PATH" -o"$WORK_DIR/extracted" -y >"$WORK_DIR/7z.log" 2>&1 || true

ASAR_PATH="$(find "$WORK_DIR/extracted" -name app.asar -type f 2>/dev/null | head -1)"
APP_PLIST="$(find "$WORK_DIR/extracted" -path '*/Contents/Info.plist' -type f 2>/dev/null | grep -E '/[^/]+\.app/Contents/Info\.plist$' | head -1)"
APP_RESOURCES_DIR="$(dirname "$ASAR_PATH")"
CHROME_PLUGIN_SRC="$(find "$WORK_DIR/extracted" -path '*/Contents/Resources/plugins/openai-bundled/plugins/chrome/.codex-plugin/plugin.json' -type f 2>/dev/null | head -1)"
if [ -n "$CHROME_PLUGIN_SRC" ]; then
  CHROME_PLUGIN_SRC="$(dirname "$(dirname "$CHROME_PLUGIN_SRC")")"
fi

[ -n "$ASAR_PATH" ] || error "app.asar not found in DMG extraction"
[ -n "$APP_PLIST" ] || error "Codex app Info.plist not found in DMG extraction"

success "Found app payload"

run_asar_extract() {
  local src="$1"
  local dst="$2"

  if command -v asar >/dev/null 2>&1; then
    asar extract "$src" "$dst"
    return
  fi

  # No global asar: use npm exec to avoid permanent global state
  npm exec --yes @electron/asar -- extract "$src" "$dst"
}

log "Extracting app.asar..."
run_asar_extract "$ASAR_PATH" "$WORK_DIR/app_src" || error "Failed to extract app.asar"

[ -d "$WORK_DIR/app_src/.vite" ] || error "Extracted app is missing .vite"
[ -d "$WORK_DIR/app_src/webview" ] || error "Extracted app is missing webview"
[ -f "$WORK_DIR/app_src/package.json" ] || error "Extracted app is missing package.json"

# -----------------------------------------------------------------------------
# Build metadata + package.json synthesis
# -----------------------------------------------------------------------------
log "Synthesizing Linux package metadata..."

APP_VERSION="$(awk '/CFBundleShortVersionString/{getline; gsub(/.*<string>|<\/string>.*/,""); print; exit}' "$APP_PLIST")"
APP_BUILD="$(awk '/CFBundleVersion/{getline; gsub(/.*<string>|<\/string>.*/,""); print; exit}' "$APP_PLIST")"
[ -n "$APP_VERSION" ] || APP_VERSION="unknown"
[ -n "$APP_BUILD" ] || APP_BUILD="unknown"

node - "$WORK_DIR/app_src/package.json" "$WORK_DIR/package.generated.json" "$APP_VERSION" <<'NODE'
const fs = require("fs");
const srcPkg = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const outPath = process.argv[3];
const appVersion = process.argv[4];

const sourceDeps = srcPkg.dependencies || {};
const excludedWorkspaceDeps = new Set([
  "app-server-types",
  "browser-api",
  "browser-backend-common",
  "browser-common",
  "commands",
  "external-agent-migration",
  "protocol",
  "shared-node",
]);
const excludedPlatformDeps = new Set([
  "electron-liquid-glass",
  "objc-js",
]);
const excludedProtocols = [
  "link:",
  "workspace:",
  "file:",
];

const deps = {};
for (const [name, version] of Object.entries(sourceDeps)) {
  if (excludedWorkspaceDeps.has(name)) continue;
  if (excludedPlatformDeps.has(name)) continue;
  if (excludedProtocols.some((prefix) => String(version).startsWith(prefix))) continue;
  deps[name] = version;
}

let electronVersion =
  (srcPkg.devDependencies && srcPkg.devDependencies.electron) ||
  (srcPkg.dependencies && srcPkg.dependencies.electron) ||
  "40.0.0";

let electronMajor = Number.parseInt(String(electronVersion).match(/\d+/)?.[0] || "0", 10);
if (electronMajor >= 42 && deps["better-sqlite3"]) {
  // better-sqlite3 12.x does not yet build against Electron 42's V8
  // external pointer API. Use the newest Electron 41 runtime for Linux.
  electronVersion = "41.6.1";
  electronMajor = 41;
}

const output = {
  name: "codex-linux",
  productName: "Codex",
  version: `${appVersion}-linux`,
  description: "Codex for Linux (unofficial port)",
  main: srcPkg.main || ".vite/build/bootstrap.js",
  scripts: {
    start: "electron .",
    "start:debug": "electron . --enable-logging"
  },
  dependencies: deps,
  devDependencies: {
    electron: electronVersion,
    "@electron/rebuild": "^4.0.3"
  }
};

fs.writeFileSync(outPath, `${JSON.stringify(output, null, 2)}\n`);
NODE

# -----------------------------------------------------------------------------
# Install tree
# -----------------------------------------------------------------------------
log "Preparing output directory: $OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

cp -r "$WORK_DIR/app_src/.vite" "$OUTPUT_DIR/"
cp -r "$WORK_DIR/app_src/webview" "$OUTPUT_DIR/"
if [ -d "$WORK_DIR/app_src/native" ]; then
  cp -r "$WORK_DIR/app_src/native" "$OUTPUT_DIR/"
else
  mkdir -p "$OUTPUT_DIR/native"
fi
cp "$WORK_DIR/package.generated.json" "$OUTPUT_DIR/package.json"

if [ -f "$APP_RESOURCES_DIR/codexTemplate.png" ]; then
  cp "$APP_RESOURCES_DIR/codexTemplate.png" "$OUTPUT_DIR/icon.png"
elif [ -f "$APP_RESOURCES_DIR/icon-codex-dark-color.png" ]; then
  cp "$APP_RESOURCES_DIR/icon-codex-dark-color.png" "$OUTPUT_DIR/icon.png"
elif [ -f "$APP_RESOURCES_DIR/icon-codex-light.png" ]; then
  cp "$APP_RESOURCES_DIR/icon-codex-light.png" "$OUTPUT_DIR/icon.png"
elif [ -f "$APP_RESOURCES_DIR/chatgptTemplate.png" ]; then
  cp "$APP_RESOURCES_DIR/chatgptTemplate.png" "$OUTPUT_DIR/icon.png"
elif [ -f "$APP_RESOURCES_DIR/icon.png" ]; then
  cp "$APP_RESOURCES_DIR/icon.png" "$OUTPUT_DIR/icon.png"
fi

# Ensure main points to an existing file for newer hashed bundles.
node - "$OUTPUT_DIR/package.json" <<'NODE'
const fs = require("fs");
const path = require("path");
const pkgPath = process.argv[2];
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
const root = path.dirname(pkgPath);
const buildDir = path.join(root, ".vite", "build");

const candidates = [
  pkg.main,
  ".vite/build/bootstrap.js",
  ".vite/build/main.js",
];

let chosen = null;
for (const c of candidates) {
  if (!c) continue;
  if (fs.existsSync(path.join(root, c))) {
    chosen = c;
    break;
  }
}

if (!chosen && fs.existsSync(buildDir)) {
  const hashedMain = fs.readdirSync(buildDir).find((n) => /^main-.*\.js$/.test(n));
  if (hashedMain) chosen = `.vite/build/${hashedMain}`;
}

if (!chosen) chosen = ".vite/build/bootstrap.js";
pkg.main = chosen;
fs.writeFileSync(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`);
NODE

APP_MAIN_ENTRY="$(node -e "const p=require('$OUTPUT_DIR/package.json'); console.log(p.main||'unknown')")"
ELECTRON_RUNTIME_VERSION="$(node -e "const p=require('$OUTPUT_DIR/package.json'); console.log((p.devDependencies&&p.devDependencies.electron)||'unknown')")"

# -----------------------------------------------------------------------------
# Linux patch engine
# -----------------------------------------------------------------------------
resolve_patch_engine() {
  local local_engine="$SCRIPT_DIR/tools/patch-codex-linux.mjs"
  if [ -f "$local_engine" ]; then
    echo "$local_engine"
    return
  fi

  local downloaded="$WORK_DIR/patch-codex-linux.mjs"
  log "No local patch engine found. Downloading Linux patch engine..."
  curl -fsSL --retry 3 --connect-timeout 20 -o "$downloaded" "$DEFAULT_PATCH_ENGINE_URL" || \
    error "Failed to download patch engine from $DEFAULT_PATCH_ENGINE_URL"
  echo "$downloaded"
}

PATCH_ENGINE="$(resolve_patch_engine)"
log "Running Linux patch engine: $PATCH_ENGINE"
if [ -n "$CHROME_PLUGIN_SRC" ] && [ -d "$CHROME_PLUGIN_SRC" ]; then
  export CODEX_CHROME_PLUGIN_SOURCE="$CHROME_PLUGIN_SRC"
fi
node "$PATCH_ENGINE" "$OUTPUT_DIR"
success "Linux patch engine complete"

# -----------------------------------------------------------------------------
# npm install + rebuild
# -----------------------------------------------------------------------------
log "Installing npm dependencies (this can take a few minutes)..."
(
  cd "$OUTPUT_DIR"
  npm install
)
success "Dependencies installed"

log "Rebuilding native modules for Electron..."
(
  cd "$OUTPUT_DIR"
  npx @electron/rebuild
)
success "Native modules rebuilt"

# -----------------------------------------------------------------------------
# Linux stubs / launcher
# -----------------------------------------------------------------------------
log "Applying Linux compatibility patches..."

rm -f "$OUTPUT_DIR/native/sparkle.node" 2>/dev/null || true

mkdir -p "$OUTPUT_DIR/node_modules/electron-liquid-glass"
cat > "$OUTPUT_DIR/node_modules/electron-liquid-glass/index.js" <<'STUBJS'
const stub = {
  isGlassSupported: () => false,
  enable: () => {},
  disable: () => {},
  setOptions: () => {}
};
module.exports = stub;
module.exports.default = stub;
STUBJS

cat > "$OUTPUT_DIR/node_modules/electron-liquid-glass/package.json" <<'STUBPKG'
{"name":"electron-liquid-glass","version":"1.0.0","main":"index.js"}
STUBPKG

mkdir -p "$OUTPUT_DIR/bin"
cat > "$OUTPUT_DIR/bin/codex-fallback" <<'CLIWRAP'
#!/bin/bash
set -euo pipefail
exec npx --yes @openai/codex@latest "$@"
CLIWRAP
chmod +x "$OUTPUT_DIR/bin/codex-fallback"

cat > "$OUTPUT_DIR/codex-linux.sh" <<'LAUNCHER'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

if [ "${CODEX_LINUX_LAUNCHER_LOG:-1}" = "1" ]; then
  log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/codex-linux"
  mkdir -p "$log_dir"
  log_file="$log_dir/launcher.log"
  if [ -f "$log_file" ] && [ "$(wc -c <"$log_file" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv "$log_file" "$log_file.1" 2>/dev/null || true
  fi
  {
    echo ""
    echo "[$(date -Is)] launch cwd=$SCRIPT_DIR display=${DISPLAY:-} wayland=${WAYLAND_DISPLAY:-} codex_home=${CODEX_HOME:-<default>}"
  } >>"$log_file"
  exec >>"$log_file" 2>&1
fi

export ELECTRON_RENDERER_URL="file://${SCRIPT_DIR}/webview/index.html"
export CODEX_CHROME_PLUGIN_ROOT="${SCRIPT_DIR}/plugins/openai-bundled/plugins/chrome"

if [ -z "${CODEX_CLI_PATH:-}" ]; then
  if command -v codex >/dev/null 2>&1; then
    export CODEX_CLI_PATH="$(command -v codex)"
  else
    export CODEX_CLI_PATH="${SCRIPT_DIR}/bin/codex-fallback"
  fi
fi

if [ -z "${CODEX_BROWSER_USE_NODE_PATH:-}" ] && command -v node >/dev/null 2>&1; then
  export CODEX_BROWSER_USE_NODE_PATH="$(command -v node)"
fi

if [ -z "${NODE_REPL_NODE_PATH:-}" ] && [ -n "${CODEX_BROWSER_USE_NODE_PATH:-}" ]; then
  export NODE_REPL_NODE_PATH="$CODEX_BROWSER_USE_NODE_PATH"
fi

if [ -z "${CODEX_NODE_REPL_PATH:-}" ]; then
  export CODEX_NODE_REPL_PATH="${SCRIPT_DIR}/bin/node_repl-linux"
fi

enable_remote_control_config() {
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local config_file="$codex_home/config.toml"

  mkdir -p "$codex_home"

  node - "$config_file" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
let input = "";
try {
  input = fs.readFileSync(file, "utf8");
} catch {}

const lines = input.split(/\r?\n/);
const out = [];
let inFeatures = false;
let sawFeatures = false;
let wroteRemoteControl = false;

for (const line of lines) {
  if (/^\s*\[.*\]\s*$/.test(line)) {
    if (inFeatures && !wroteRemoteControl) {
      out.push("remote_control = true");
      wroteRemoteControl = true;
    }
    inFeatures = /^\s*\[features\]\s*$/.test(line);
    sawFeatures ||= inFeatures;
    out.push(line);
    continue;
  }

  if (inFeatures && /^\s*remote_control\s*=/.test(line)) {
    if (!wroteRemoteControl) {
      out.push("remote_control = true");
      wroteRemoteControl = true;
    }
    continue;
  }

  out.push(line);
}

if (inFeatures && !wroteRemoteControl) out.push("remote_control = true");
if (!sawFeatures) out.unshift("[features]", "remote_control = true", "");

fs.writeFileSync(file, out.join("\n").replace(/\n*$/, "\n"));
NODE
}

ensure_managed_codex_shim() {
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local managed_dir="$codex_home/packages/standalone/current"
  local managed_codex="$managed_dir/codex"

  mkdir -p "$managed_dir"

  if [ -x "$managed_codex" ] && ! grep -q "Codex Linux managed-path compatibility shim" "$managed_codex" 2>/dev/null; then
    return 0
  fi

  local tmp
  tmp="$(mktemp "${managed_codex}.tmp.XXXXXX")"
  {
    echo '#!/bin/bash'
    echo '# Codex Linux managed-path compatibility shim.'
    echo 'set -euo pipefail'
    printf 'exec %q "$@"\n' "$CODEX_CLI_PATH"
  } > "$tmp"
  chmod +x "$tmp"
  mv "$tmp" "$managed_codex"
}

start_remote_control_daemon() {
  [ "${CODEX_LINUX_REMOTE_CONTROL:-0}" = "1" ] || return 0
  [ -x "$CODEX_CLI_PATH" ] || return 0
  [ "${CODEX_LINUX_ALLOW_CODEX_HOME_WRITES:-0}" = "1" ] || {
    local log_dir="${XDG_CONFIG_HOME:-$HOME/.config}/codex-linux"
    mkdir -p "$log_dir"
    echo "[$(date -Is)] skipped remote-control startup because CODEX_LINUX_ALLOW_CODEX_HOME_WRITES is not 1" >>"$log_dir/remote-control-daemon.log"
    return 0
  }

  local log_dir="${XDG_CONFIG_HOME:-$HOME/.config}/codex-linux"
  local log_file="$log_dir/remote-control-daemon.log"
  local start_stdout="$log_dir/remote-control-start.stdout"
  local start_stderr="$log_dir/remote-control-start.stderr"
  mkdir -p "$log_dir"

  enable_remote_control_config >>"$log_file" 2>&1 || true
  ensure_managed_codex_shim >>"$log_file" 2>&1 || true

  {
    echo ""
    echo "[$(date -Is)] starting remote-control daemon via $CODEX_CLI_PATH"
  } >>"$log_file"

  "$CODEX_CLI_PATH" remote-control start --json --enable remote_control >"$start_stdout" 2>"$start_stderr" || true
  cat "$start_stdout" >>"$log_file" 2>/dev/null || true
  cat "$start_stderr" >>"$log_file" 2>/dev/null || true

  if grep -q '"status":"connecting"' "$start_stdout" 2>/dev/null && grep -q '"timedOut":true' "$start_stdout" 2>/dev/null; then
    echo "[$(date -Is)] remote-control daemon is stale/connecting; restarting once" >>"$log_file"
    "$CODEX_CLI_PATH" remote-control stop --json >>"$log_file" 2>&1 || true
    "$CODEX_CLI_PATH" remote-control start --json --enable remote_control >"$start_stdout" 2>"$start_stderr" || true
    cat "$start_stdout" >>"$log_file" 2>/dev/null || true
    cat "$start_stderr" >>"$log_file" 2>/dev/null || true
  fi
}

start_remote_control_daemon

linux_graphics_flags=()
if [ "${CODEX_LINUX_GRAPHICS_MODE:-stable}" != "native" ]; then
  linux_graphics_flags+=(
    --ozone-platform=x11
    --disable-features=VaapiVideoDecoder,VaapiVideoEncoder,Vulkan,UseSkiaRenderer
    --disable-smooth-scrolling
    --disable-backgrounding-occluded-windows
  )
fi

unset ELECTRON_RUN_AS_NODE
exec ./node_modules/.bin/electron . --no-sandbox "${linux_graphics_flags[@]}" "$@"
LAUNCHER
chmod +x "$OUTPUT_DIR/codex-linux.sh"

success "Launcher created"

# -----------------------------------------------------------------------------
# Optional CLI install/update
# -----------------------------------------------------------------------------
if [ "$SKIP_CLI_INSTALL" = "1" ]; then
  warn "Skipping Codex CLI install/update by request (--skip-cli-install)."
else
  log "Ensuring Codex CLI is available..."
  if command -v codex >/dev/null 2>&1; then
    success "Codex CLI found: $(command -v codex) ($(codex --version 2>/dev/null || echo unknown))"
  else
    warn "Codex CLI not found in PATH. Attempting global install..."
    if npm install -g @openai/codex@latest >/dev/null 2>&1; then
      success "Installed Codex CLI globally: $(command -v codex)"
    else
      warn "Global install failed (likely permissions). Launcher will use local npx fallback."
    fi
  fi
fi

CLI_PATH_USED="$OUTPUT_DIR/bin/codex-fallback"
CLI_VERSION_USED="npx @openai/codex@latest (fallback)"
if command -v codex >/dev/null 2>&1; then
  CLI_PATH_USED="$(command -v codex)"
  CLI_VERSION_USED="$(codex --version 2>/dev/null || echo unknown)"
fi

node - "$OUTPUT_DIR/build-info.json" \
  "$APP_VERSION" "$APP_BUILD" "$ELECTRON_RUNTIME_VERSION" "$APP_MAIN_ENTRY" \
  "$DMG_PATH" "$DMG_SHA256" "$CLI_PATH_USED" "$CLI_VERSION_USED" "$INSTALLER_VERSION" <<'NODE'
const fs = require("fs");
const outPath = process.argv[2];
const payload = {
  generatedAt: new Date().toISOString(),
  installerVersion: process.argv[11],
  codexAppVersion: process.argv[3],
  codexAppBuild: process.argv[4],
  electronRuntime: process.argv[5],
  mainEntry: process.argv[6],
  dmgPath: process.argv[7],
  dmgSha256: process.argv[8],
  cliPath: process.argv[9],
  cliVersion: process.argv[10],
};
fs.writeFileSync(outPath, JSON.stringify(payload, null, 2) + "\n");
NODE

# -----------------------------------------------------------------------------
# Desktop shortcut (best effort)
# -----------------------------------------------------------------------------
DESKTOP_FILE="$HOME/.local/share/applications/codex.desktop"
LEGACY_DESKTOP_FILE="$HOME/.local/share/applications/codex-linux.desktop"
ICON_THEME_DIR="$HOME/.local/share/icons/hicolor/1024x1024/apps"
ICON_THEME_512_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
PIXMAP_DIR="$HOME/.local/share/pixmaps"
mkdir -p "$(dirname "$DESKTOP_FILE")"
mkdir -p "$ICON_THEME_DIR"
mkdir -p "$ICON_THEME_512_DIR"
mkdir -p "$PIXMAP_DIR"
if [ ! -f "$HOME/.local/share/icons/hicolor/index.theme" ] && [ -f /usr/share/icons/hicolor/index.theme ]; then
  cp /usr/share/icons/hicolor/index.theme "$HOME/.local/share/icons/hicolor/index.theme"
fi
cp "$OUTPUT_DIR/icon.png" "$ICON_THEME_DIR/codex-linux.png"
cp "$OUTPUT_DIR/icon.png" "$ICON_THEME_512_DIR/codex-linux.png"
cp "$OUTPUT_DIR/icon.png" "$PIXMAP_DIR/codex-linux.png"
chmod 644 "$ICON_THEME_DIR/codex-linux.png" "$ICON_THEME_512_DIR/codex-linux.png" "$PIXMAP_DIR/codex-linux.png"
cat > "$DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Name=Codex
Comment=Run Codex desktop app on Linux
Exec=$OUTPUT_DIR/codex-linux.sh %u
Path=$OUTPUT_DIR
Icon=codex-linux
Terminal=false
Type=Application
StartupNotify=true
StartupWMClass=Codex (Dev)
Categories=Development;
Keywords=codex;chatgpt;openai;ai;
MimeType=x-scheme-handler/codex;
DESKTOP
chmod +x "$DESKTOP_FILE"
gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true

cat > "$LEGACY_DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Name=Codex (Linux Port)
Comment=Run Codex desktop app on Linux (unofficial)
NoDisplay=true
Exec=$OUTPUT_DIR/codex-linux.sh %u
Path=$OUTPUT_DIR
Icon=codex-linux
Terminal=false
Type=Application
StartupNotify=true
StartupWMClass=Codex (Dev)
Categories=Development;
MimeType=x-scheme-handler/codex;
DESKTOP
chmod +x "$LEGACY_DESKTOP_FILE"
gio set "$LEGACY_DESKTOP_FILE" metadata::trusted true 2>/dev/null || true

DESKTOP_SHORTCUT_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
if [ -d "$DESKTOP_SHORTCUT_DIR" ]; then
  cp "$DESKTOP_FILE" "$DESKTOP_SHORTCUT_DIR/Codex.desktop"
  chmod +x "$DESKTOP_SHORTCUT_DIR/Codex.desktop"
  gio set "$DESKTOP_SHORTCUT_DIR/Codex.desktop" metadata::trusted true 2>/dev/null || true
fi

if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default codex.desktop x-scheme-handler/codex 2>/dev/null || \
    warn "Could not register codex:// URL handler with xdg-mime. Auth callbacks may not return to the desktop app automatically."
else
  warn "xdg-mime not found. Register x-scheme-handler/codex manually if auth callbacks do not return to Codex."
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/codex" <<COMMAND
#!/bin/bash
set -euo pipefail

export CODEX_HOME="\${CODEX_HOME:-\$HOME/.codex}"

REAL_CODEX="$CLI_PATH_USED"

if [ ! -x "\$REAL_CODEX" ]; then
  if [ -x /snap/bin/codex ]; then
    REAL_CODEX="/snap/bin/codex"
  else
    echo "codex: real Codex CLI not found" >&2
    exit 127
  fi
fi

exec "\$REAL_CODEX" "\$@"
COMMAND
chmod +x "$BIN_DIR/codex"

cat > "$BIN_DIR/codex-app" <<COMMAND
#!/bin/bash
set -euo pipefail

APP="$OUTPUT_DIR/codex-linux.sh"
LOG_DIR="\${XDG_CACHE_HOME:-\$HOME/.cache}/codex-linux"
LOG_FILE="\$LOG_DIR/codex-app.log"

export CODEX_HOME="\${CODEX_HOME:-\$HOME/.codex}"

case "\${1:-}" in
  -h|--help)
    cat <<'HELP'
Usage:
  codex-app              Launch Codex App and detach from this terminal.
  codex-app --foreground Launch Codex App attached to this terminal.

Logs:
  ~/.cache/codex-linux/codex-app.log
  ~/.cache/codex-linux/launcher.log
HELP
    exit 0
    ;;
esac

if [ "\${1:-}" = "--foreground" ]; then
  shift
  exec "\$APP" "\$@"
fi

if [ ! -x "\$APP" ]; then
  echo "codex-app: launcher not found or not executable: \$APP" >&2
  exit 127
fi

mkdir -p "\$LOG_DIR"

if command -v setsid >/dev/null 2>&1; then
  setsid -f "\$APP" "\$@" </dev/null >>"\$LOG_FILE" 2>&1
else
  nohup "\$APP" "\$@" </dev/null >>"\$LOG_FILE" 2>&1 &
fi

echo "Codex started."
echo "Log: \$LOG_FILE"
COMMAND
chmod +x "$BIN_DIR/codex-app"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Installation Complete!                 ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Installed app: $OUTPUT_DIR"
echo "Installer:     $INSTALLER_VERSION"
echo "App version:   $APP_VERSION (build $APP_BUILD)"
echo "Electron:      $ELECTRON_RUNTIME_VERSION"
echo "Main entry:    $APP_MAIN_ENTRY"
echo "DMG source:    $DMG_PATH"
echo "DMG sha256:    $DMG_SHA256"
echo "Codex CLI:     $CLI_PATH_USED ($CLI_VERSION_USED)"
echo "Build info:    $OUTPUT_DIR/build-info.json"
echo "URL handler:   x-scheme-handler/codex -> $DESKTOP_FILE"
echo ""
echo "Launch:"
echo "  cd \"$OUTPUT_DIR\""
echo "  ./codex-linux.sh"
echo ""
echo "Desktop entry: $DESKTOP_FILE"
echo ""
