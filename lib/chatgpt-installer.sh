#!/usr/bin/env bash

CHATGPT_PRODUCT_NAME="ChatGPT Linux"
CHATGPT_OUTPUT_BASENAME="chatgpt-linux"
CHATGPT_LAUNCHER_NAME="chatgpt-linux.sh"
CHATGPT_DESKTOP_ID="chatgpt-linux.desktop"
CHATGPT_BUNDLE_ID="com.openai.codex"
MIN_NODE_VERSION="22.12.0"
PORTABLE_NODE_VERSION="22.23.2"

installer_error() {
  printf '[x] %s\n' "$*" >&2
  return 1
}
retry_command() {
  local attempts="$1"
  local delay_seconds="$2"
  local label="$3"
  shift 3
  local attempt=1
  local status=0

  if [[ ! "$attempts" =~ ^[1-9][0-9]*$ ]] || \
     [[ ! "$delay_seconds" =~ ^[0-9]+$ ]]; then
    installer_error "invalid retry policy for $label"
    return
  fi
  if (( $# == 0 )); then
    installer_error "missing command for retry policy: $label"
    return
  fi

  while (( attempt <= attempts )); do
    if "$@"; then
      return 0
    else
      status=$?
    fi
    if (( attempt == attempts )); then
      return "$status"
    fi
    printf '[!] %s failed (attempt %d/%d); retrying\n' \
      "$label" "$attempt" "$attempts" >&2
    (( delay_seconds == 0 )) || sleep "$delay_seconds"
    attempt=$((attempt + 1))
  done
}

version_at_least() {
  local actual="$1"
  local required="$2"
  local -a actual_parts required_parts
  local index actual_part required_part max_parts

  if [[ ! "$actual" =~ ^[0-9]+(\.[0-9]+)*$ ]] || \
     [[ ! "$required" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    installer_error "invalid version comparison: $actual >= $required"
    return
  fi

  IFS='.' read -r -a actual_parts <<<"$actual"
  IFS='.' read -r -a required_parts <<<"$required"
  max_parts=${#actual_parts[@]}
  if (( ${#required_parts[@]} > max_parts )); then
    max_parts=${#required_parts[@]}
  fi

  for ((index = 0; index < max_parts; index++)); do
    actual_part=${actual_parts[index]:-0}
    required_part=${required_parts[index]:-0}
    if (( 10#$actual_part > 10#$required_part )); then
      return 0
    fi
    if (( 10#$actual_part < 10#$required_part )); then
      return 1
    fi
  done
}

normalize_linux_arch() {
  local machine="${1:-$(uname -m)}"

  case "$machine" in
    x86_64|amd64) printf '%s\n' x64 ;;
    aarch64|arm64) printf '%s\n' arm64 ;;
    *) installer_error "unsupported Linux architecture: $machine" ;;
  esac
}

remote_content_length() {
  local url="$1"
  local headers

  headers=$(curl -fsSIL "$url") || return
  printf '%s\n' "$headers" | awk '
    {
      gsub(/\r/, "", $0)
      if (tolower($1) == "content-length:" && $2 ~ /^[0-9]+$/) {
        content_bytes = $2
      }
    }
    END { print content_bytes }
  '
}

file_size_matches() {
  local file="$1"
  local expected_bytes="$2"
  local actual_bytes

  [[ -f "$file" ]] || {
    installer_error "missing file: $file"
    return
  }

  actual_bytes=$(stat -c%s "$file") || return
  [[ "$actual_bytes" == "$expected_bytes" ]] || {
    installer_error "incomplete DMG: expected $expected_bytes bytes, found $actual_bytes"
    return
  }
}

download_resumable() {
  local url="$1"
  local destination="$2"
  local expected_bytes

  mkdir -p "$(dirname "$destination")"

  expected_bytes=""
  if command -v curl >/dev/null 2>&1; then
    expected_bytes=$(remote_content_length "$url") || return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget --continue --tries=0 --timeout=30 --waitretry=2 -O "$destination" "$url" || return
    if [[ -n "$expected_bytes" ]]; then
      file_size_matches "$destination" "$expected_bytes" || return
    fi
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    installer_error "neither wget nor curl is available for download"
    return
  fi

  if [[ -z "$expected_bytes" ]]; then
    curl -fL --retry 1 --connect-timeout 20 -C - -o "$destination" "$url"
    return
  fi

  while [[ ! -f "$destination" ]] || \
        ! file_size_matches "$destination" "$expected_bytes"; do
    curl -fL --retry 1 --connect-timeout 20 -C - -o "$destination" "$url" || return
  done
}

resolve_node() {
  local work_dir="$1"
  local node_candidate npm_candidate node_version arch runtime_dir archive url

  node_candidate=$(command -v node 2>/dev/null || true)
  npm_candidate=$(command -v npm 2>/dev/null || true)
  if [[ -n "$node_candidate" && -n "$npm_candidate" ]]; then
    node_version=$("$node_candidate" --version 2>/dev/null || true)
    node_version=${node_version#v}
    if version_at_least "$node_version" "$MIN_NODE_VERSION"; then
      NODE_BIN="$node_candidate"
      NPM_BIN="$npm_candidate"
      PATH="$(dirname "$NODE_BIN"):$PATH"
      return 0
    fi
  fi

  arch=$(normalize_linux_arch) || return
  runtime_dir="$work_dir/node-v${PORTABLE_NODE_VERSION}-linux-${arch}"
  NODE_BIN="$runtime_dir/bin/node"
  NPM_BIN="$runtime_dir/bin/npm"

  if [[ ! -x "$NODE_BIN" || ! -x "$NPM_BIN" ]]; then
    mkdir -p "$work_dir"
    if [[ -n "${CHATGPT_NODE_DOWNLOAD_HOOK:-}" ]]; then
      "$CHATGPT_NODE_DOWNLOAD_HOOK" "$runtime_dir" || return
    else
      archive="$work_dir/node-v${PORTABLE_NODE_VERSION}-linux-${arch}.tar.xz"
      url="https://nodejs.org/dist/v${PORTABLE_NODE_VERSION}/node-v${PORTABLE_NODE_VERSION}-linux-${arch}.tar.xz"
      download_resumable "$url" "$archive" || return
      tar -xJf "$archive" -C "$work_dir" || return
    fi
  fi

  [[ -x "$NODE_BIN" && -x "$NPM_BIN" ]] || {
    installer_error "portable Node runtime is incomplete: $runtime_dir"
    return
  }

  node_version=$("$NODE_BIN" --version 2>/dev/null || true)
  node_version=${node_version#v}
  version_at_least "$node_version" "$MIN_NODE_VERSION" || {
    installer_error "portable Node $node_version does not satisfy $MIN_NODE_VERSION"
    return
  }
  PATH="$runtime_dir/bin:$PATH"
}

resolve_7zip() {
  local work_dir="$1"
  local package_dir root_dir distro_id distro_like distro_tags
  local ID ID_LIKE

  distro_id="${CHATGPT_DISTRO_ID:-}"
  distro_like=""
  if [[ -z "$distro_id" && -r /etc/os-release ]]; then
    ID=""
    ID_LIKE=""
    # shellcheck disable=SC1091
    . /etc/os-release
    distro_id="${ID:-}"
    distro_like="${ID_LIKE:-}"
  elif [[ -z "$distro_id" && -f /etc/debian_version ]]; then
    distro_id="debian"
  fi
  distro_tags="$distro_id $distro_like"

  SEVEN_ZIP=$(command -v 7z 2>/dev/null || true)
  if [[ -z "$SEVEN_ZIP" ]]; then
    SEVEN_ZIP=$(command -v 7zz 2>/dev/null || true)
  fi
  [[ -n "$SEVEN_ZIP" ]] && return 0

  if [[ "$distro_tags" == *debian* || "$distro_tags" == *ubuntu* ]] && \
     command -v apt-get >/dev/null 2>&1 && \
     command -v dpkg-deb >/dev/null 2>&1; then
    package_dir="$work_dir/7zip-package"
    root_dir="$work_dir/7zip-root"
    mkdir -p "$package_dir" "$root_dir"
    (
      cd "$package_dir" || exit
      apt-get download 7zip
      dpkg-deb -x ./*.deb "$root_dir"
    ) || return
    SEVEN_ZIP="$root_dir/usr/lib/7zip/7z"
    [[ -x "$SEVEN_ZIP" ]] || {
      installer_error "7-Zip package did not provide $SEVEN_ZIP"
      return
    }
    return 0
  fi

  case "$distro_tags" in
    *fedora*|*rhel*|*centos*)
      installer_error "7-Zip not found; install it with: dnf install 7zip"
      ;;
    *arch*|*manjaro*)
      installer_error "7-Zip not found; install it with: pacman -S 7zip"
      ;;
    *opensuse*|*suse*)
      installer_error "7-Zip not found; install it with: zypper install 7zip"
      ;;
    *)
      if command -v dnf >/dev/null 2>&1; then
        installer_error "7-Zip not found; install it with: dnf install 7zip"
      elif command -v pacman >/dev/null 2>&1; then
        installer_error "7-Zip not found; install it with: pacman -S 7zip"
      elif command -v zypper >/dev/null 2>&1; then
        installer_error "7-Zip not found; install it with: zypper install 7zip"
      else
        installer_error \
          "7-Zip not found; install package '7zip' (7z or 7zz required)"
      fi
      ;;
  esac
}

validate_dmg() {
  local file="$1"
  local expected_bytes="${2:-}"

  if [[ -n "$expected_bytes" ]]; then
    file_size_matches "$file" "$expected_bytes" || return
  fi
  [[ -n "${SEVEN_ZIP:-}" ]] || {
    installer_error "7-Zip executable is not resolved"
    return
  }
  "$SEVEN_ZIP" t "$file"
}

cached_dmg_is_usable() {
  local file="$1"
  local expected_bytes="${2:-}"

  [[ -f "$file" ]] || return 1

  if [[ -n "$expected_bytes" ]] &&
     file_size_matches "$file" "$expected_bytes" >/dev/null 2>&1; then
    validate_dmg "$file" "$expected_bytes"
    return
  fi

  validate_dmg "$file"
}

extraction_log_has_only_ignored_links() {
  local log_file="$1"

  [[ -f "$log_file" ]] || return 1

  awk '
    /^ERROR:/ {
      saw_ignored = 1
      if ($0 !~ /^ERROR: Dangerous (symbolic )?link path was ignored : /) bad = 1
    }
    END { exit !(saw_ignored && !bad) }
  ' "$log_file"
}

write_chatgpt_launcher() {
  local output_dir="$1"
  local launcher="$output_dir/$CHATGPT_LAUNCHER_NAME"

  mkdir -p "$output_dir/bin"

  cat >"$output_dir/bin/codex-fallback" <<'CLIWRAP'
#!/usr/bin/env bash
set -euo pipefail
exec npx --yes @openai/codex@latest "$@"
CLIWRAP
  chmod +x "$output_dir/bin/codex-fallback" || return

  cat >"$launcher" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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
  if [ -x "$managed_codex" ] &&
     ! grep -q "ChatGPT Linux managed-path compatibility shim" "$managed_codex" 2>/dev/null; then
    return 0
  fi

  local tmp
  tmp="$(mktemp "${managed_codex}.tmp.XXXXXX")"
  {
    echo '#!/usr/bin/env bash'
    echo '# ChatGPT Linux managed-path compatibility shim.'
    echo 'set -euo pipefail'
    printf 'exec %q "$@"\n' "$CODEX_CLI_PATH"
  } >"$tmp"
  chmod +x "$tmp"
  mv "$tmp" "$managed_codex"
}

start_remote_control_daemon() {
  [ "${CODEX_LINUX_REMOTE_CONTROL:-1}" = "0" ] && return 0
  [ -x "$CODEX_CLI_PATH" ] || return 0

  local log_dir="${XDG_CONFIG_HOME:-$HOME/.config}/chatgpt-linux"
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

  "$CODEX_CLI_PATH" remote-control start --json --enable remote_control \
    >"$start_stdout" 2>"$start_stderr" || true
  cat "$start_stdout" >>"$log_file" 2>/dev/null || true
  cat "$start_stderr" >>"$log_file" 2>/dev/null || true

  if grep -q '"status":"connecting"' "$start_stdout" 2>/dev/null &&
     grep -q '"timedOut":true' "$start_stdout" 2>/dev/null; then
    echo "[$(date -Is)] remote-control daemon is stale/connecting; restarting once" >>"$log_file"
    "$CODEX_CLI_PATH" remote-control stop --json >>"$log_file" 2>&1 || true
    "$CODEX_CLI_PATH" remote-control start --json --enable remote_control \
      >"$start_stdout" 2>"$start_stderr" || true
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

exec ./node_modules/.bin/electron . --no-sandbox "${linux_graphics_flags[@]}" "$@"
LAUNCHER

  chmod +x "$launcher"
}

write_desktop_entry() {
  local output_dir="$1"
  local desktop_file="$2"
  local absolute_output

  absolute_output=$(cd "$output_dir" && pwd -P) || return
  mkdir -p "$(dirname "$desktop_file")"
  cat >"$desktop_file" <<DESKTOP
[Desktop Entry]
Name=ChatGPT Linux
Comment=Run ChatGPT desktop on Linux (unofficial)
Exec=$absolute_output/$CHATGPT_LAUNCHER_NAME %u
Terminal=false
Type=Application
Categories=Development;
MimeType=x-scheme-handler/codex;
DESKTOP
}

plist_value() {
  local plist="$1"
  local key="$2"

  [[ -f "$plist" ]] || return 1

  awk -v key="$key" '
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
    }
    line == "<key>" key "</key>" {
      while (getline > 0) {
        if ($0 ~ /^[[:space:]]*<string>[^<]*<\/string>[[:space:]]*$/) {
          sub(/^[[:space:]]*<string>/, "")
          sub(/<\/string>[[:space:]]*$/, "")
          print
          exit
        }
        if ($0 ~ /^[[:space:]]*<key>/) {
          exit
        }
      }
    }
  ' "$plist"
}

discover_chatgpt_payload() {
  local extracted_root="$1"
  local plist

  [[ -d "$extracted_root" ]] || {
    installer_error "extracted DMG root not found: $extracted_root"
    return
  }

  plist=$(find "$extracted_root" -type f \
    -path '*/ChatGPT.app/Contents/Info.plist' -print -quit)
  [[ -n "$plist" ]] || {
    installer_error "unsupported DMG layout: ChatGPT.app not found"
    return
  }

  CHATGPT_PLIST="$plist"
  CHATGPT_APP_ROOT="${plist%/Contents/Info.plist}"
  CHATGPT_RESOURCES="$CHATGPT_APP_ROOT/Contents/Resources"
  CHATGPT_ASAR="$CHATGPT_RESOURCES/app.asar"
  CHATGPT_ASAR_UNPACKED="$CHATGPT_RESOURCES/app.asar.unpacked"
}

validate_chatgpt_payload() {
  [[ -d "${CHATGPT_APP_ROOT:-}" ]] || {
    installer_error "missing ChatGPT.app root"
    return
  }
  [[ -f "${CHATGPT_PLIST:-}" ]] || {
    installer_error "missing Info.plist"
    return
  }
  [[ "$(plist_value "$CHATGPT_PLIST" CFBundleIdentifier)" == "$CHATGPT_BUNDLE_ID" ]] || {
    installer_error "unexpected bundle identifier in Info.plist"
    return
  }
  [[ -d "${CHATGPT_RESOURCES:-}" ]] || {
    installer_error "missing Resources directory"
    return
  }
  [[ -f "${CHATGPT_ASAR:-}" ]] || {
    installer_error "missing app.asar"
    return
  }
  [[ -d "${CHATGPT_ASAR_UNPACKED:-}" ]] || {
    installer_error "missing app.asar.unpacked"
    return
  }
}
