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

BUNDLED_CODEX="${SCRIPT_DIR}/runtime/codex-cli/codex"
BUNDLED_NODE="${SCRIPT_DIR}/runtime/node/bin/node"

if [ -z "${CODEX_CLI_PATH:-}" ]; then
  if [ -x "$BUNDLED_CODEX" ]; then
    export CODEX_CLI_PATH="$BUNDLED_CODEX"
  elif command -v codex >/dev/null 2>&1; then
    export CODEX_CLI_PATH="$(command -v codex)"
  else
    export CODEX_CLI_PATH="${SCRIPT_DIR}/bin/codex-fallback"
  fi
fi

if [ -z "${CODEX_BROWSER_USE_NODE_PATH:-}" ]; then
  if [ -x "$BUNDLED_NODE" ]; then
    export CODEX_BROWSER_USE_NODE_PATH="$BUNDLED_NODE"
  elif command -v node >/dev/null 2>&1; then
    export CODEX_BROWSER_USE_NODE_PATH="$(command -v node)"
  fi
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

  "$BUNDLED_NODE" - "$config_file" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
let input = "";
try { input = fs.readFileSync(file, "utf8"); } catch {}
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
  } >"$tmp"
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
  "$CODEX_CLI_PATH" remote-control start --json --enable remote_control >"$start_stdout" 2>"$start_stderr" || true
  cat "$start_stdout" >>"$log_file" 2>/dev/null || true
  cat "$start_stderr" >>"$log_file" 2>/dev/null || true
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
exec "$SCRIPT_DIR/node_modules/.bin/electron" . --no-sandbox "${linux_graphics_flags[@]}" "$@"
