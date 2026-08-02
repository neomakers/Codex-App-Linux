#!/usr/bin/env bash

CHATGPT_PRODUCT_NAME="ChatGPT Linux"
CHATGPT_OUTPUT_BASENAME="chatgpt-linux"
CHATGPT_LAUNCHER_NAME="chatgpt-linux.sh"
CHATGPT_DESKTOP_ID="chatgpt-linux.desktop"
CHATGPT_BUNDLE_ID="com.openai.codex"
MIN_NODE_VERSION="22.12.0"
PORTABLE_NODE_VERSION="22.23.2"
DOWNLOAD_ATTEMPTS=3

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

detect_macos_app_architecture() {
  local app_root="$1"
  local plist="$2"
  local executable_name executable_path file_output
  local saw_x64=0
  local saw_arm64=0

  command -v file >/dev/null 2>&1 || {
    installer_error "the file utility is required to inspect candidate architecture"
    return
  }
  executable_name=$(plist_value "$plist" CFBundleExecutable)
  [[ -n "$executable_name" ]] || {
    installer_error "candidate Info.plist is missing CFBundleExecutable"
    return
  }
  executable_path="$app_root/Contents/MacOS/$executable_name"
  [[ -f "$executable_path" ]] || {
    installer_error "candidate executable is missing: Contents/MacOS/$executable_name"
    return
  }
  file_output=$(file -b "$executable_path") || return
  [[ "$file_output" == *x86_64* ]] && saw_x64=1
  [[ "$file_output" == *arm64* || "$file_output" == *aarch64* ]] && saw_arm64=1
  if (( saw_x64 && saw_arm64 )); then
    printf '%s\n' universal
  elif (( saw_x64 )); then
    printf '%s\n' x64
  elif (( saw_arm64 )); then
    printf '%s\n' arm64
  else
    installer_error "unsupported candidate executable architecture: $file_output"
  fi
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

load_current_release_contract() {
  local compatibility_root="$1"
  local node_bin="$2"
  local contract_output
  local -a contract_lines

  [[ -d "$compatibility_root" ]] || {
    installer_error "compatibility directory not found: $compatibility_root"
    return
  }
  [[ -x "$node_bin" ]] || {
    installer_error "Node runtime cannot load the release contract: $node_bin"
    return
  }

  contract_output=$("$node_bin" - "$compatibility_root" <<'NODE'
const fs = require("fs");
const path = require("path");

const root = path.resolve(process.argv[2]);
const currentPath = path.join(root, "current.json");
const current = JSON.parse(fs.readFileSync(currentPath, "utf8"));
if (typeof current.release !== "string" || current.release.length === 0) {
  throw new Error("compatibility/current.json must select a release");
}
if (path.isAbsolute(current.release) || /^(?:[\\/]|[A-Za-z]:[\\/])/.test(current.release)) {
  throw new Error("current release pointer must be repository-relative");
}
const releasePath = path.resolve(root, current.release);
if (!releasePath.startsWith(`${root}${path.sep}`)) {
  throw new Error("current release pointer escapes compatibility/");
}
const release = JSON.parse(fs.readFileSync(releasePath, "utf8"));
if (release.schemaVersion !== 2) throw new Error("unsupported release contract schema");

const values = [
  releasePath,
  release.application?.profile,
  release.application?.bundleId,
  release.application?.version,
  release.application?.build,
  release.application?.sourceArchitecture,
  release.application?.targetArchitecture,
  release.application?.electronVersion,
  release.application?.mainEntry,
  release.dmg?.sourceUrl,
  release.dmg?.observedBytes,
  release.dmg?.sha256,
];
if (values.some((value) => value === undefined || value === null || String(value).includes("\n"))) {
  throw new Error("release contract is missing a required scalar field");
}
if (!Number.isSafeInteger(release.dmg.observedBytes) || release.dmg.observedBytes <= 0) {
  throw new Error("release contract DMG size must be a positive integer");
}
if (!/^[0-9a-f]{64}$/.test(release.dmg.sha256)) {
  throw new Error("release contract DMG SHA-256 is invalid");
}
if (!Array.isArray(release.requiredPaths) || release.requiredPaths.length === 0) {
  throw new Error("release contract requiredPaths must be non-empty");
}
for (const requiredPath of release.requiredPaths) {
  if (
    typeof requiredPath !== "string" ||
    requiredPath.length === 0 ||
    requiredPath.includes("\n") ||
    path.isAbsolute(requiredPath) ||
    requiredPath.split(/[\\/]/).includes("..")
  ) {
    throw new Error(`invalid required release path: ${requiredPath}`);
  }
}
process.stdout.write([...values, ...release.requiredPaths].join("\n"));
NODE
  ) || {
    installer_error "failed to load current release contract"
    return
  }
  mapfile -t contract_lines <<<"$contract_output"
  (( ${#contract_lines[@]} >= 13 )) || {
    installer_error "current release contract is incomplete"
    return
  }

  RELEASE_CONTRACT_PATH="${contract_lines[0]}"
  RELEASE_APPLICATION_PROFILE="${contract_lines[1]}"
  RELEASE_BUNDLE_ID="${contract_lines[2]}"
  RELEASE_APP_VERSION="${contract_lines[3]}"
  RELEASE_APP_BUILD="${contract_lines[4]}"
  RELEASE_SOURCE_ARCHITECTURE="${contract_lines[5]}"
  RELEASE_TARGET_ARCHITECTURE="${contract_lines[6]}"
  RELEASE_ELECTRON_VERSION="${contract_lines[7]}"
  RELEASE_MAIN_ENTRY="${contract_lines[8]}"
  RELEASE_DMG_URL="${contract_lines[9]}"
  RELEASE_DMG_BYTES="${contract_lines[10]}"
  RELEASE_DMG_SHA256="${contract_lines[11]}"
  RELEASE_REQUIRED_PATHS=("${contract_lines[@]:12}")
}

verify_file_identity() {
  local file="$1"
  local expected_bytes="$2"
  local expected_sha256="$3"
  local actual_bytes actual_sha256

  [[ -f "$file" ]] || {
    installer_error "DMG not found: $file"
    return
  }
  actual_bytes=$(stat -c%s "$file") || return
  [[ "$actual_bytes" == "$expected_bytes" ]] || {
    installer_error \
      "DMG size mismatch: expected $expected_bytes bytes, found $actual_bytes"
    return
  }
  command -v sha256sum >/dev/null 2>&1 || {
    installer_error "sha256sum is required to verify the release DMG"
    return
  }
  actual_sha256=$(sha256sum "$file" | awk '{print $1}') || return
  [[ "$actual_sha256" == "$expected_sha256" ]] || {
    installer_error \
      "DMG SHA-256 mismatch: expected $expected_sha256, found $actual_sha256"
    return
  }
}

quarantine_file() {
  local source_file="$1"
  local reason="$2"
  local timestamp quarantine_path

  [[ -f "$source_file" ]] || {
    installer_error "cannot quarantine missing file: $source_file"
    return
  }
  [[ "$reason" =~ ^[A-Za-z0-9._-]+$ ]] || {
    installer_error "invalid quarantine reason: $reason"
    return
  }
  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  quarantine_path="${source_file}.quarantine.${reason}.${timestamp}.$$"
  [[ ! -e "$quarantine_path" ]] || {
    installer_error "quarantine path already exists: $quarantine_path"
    return
  }
  mv -- "$source_file" "$quarantine_path" || return
  printf '%s\n' "$quarantine_path"
}

require_remote_size_matches_contract() {
  local url="$1"
  local expected_bytes="$2"
  local remote_bytes

  remote_bytes=$(remote_content_length "$url") || return
  if [[ -n "$remote_bytes" && "$remote_bytes" != "$expected_bytes" ]]; then
    installer_error \
      "remote candidate size $remote_bytes does not match current release contract $expected_bytes"
    return
  fi
  printf '%s\n' "$remote_bytes"
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
  local expected_bytes="${3:-}"
  local attempts="${CHATGPT_DOWNLOAD_ATTEMPTS:-$DOWNLOAD_ATTEMPTS}"
  local attempt actual_bytes

  mkdir -p "$(dirname "$destination")"

  if [[ -z "$expected_bytes" ]] && command -v curl >/dev/null 2>&1; then
    expected_bytes=$(remote_content_length "$url") || return
  fi

  if command -v wget >/dev/null 2>&1; then
    for ((attempt = 1; attempt <= attempts; attempt++)); do
      wget --continue --tries=1 --timeout=30 --waitretry=2 \
        -O "$destination" "$url" || true
      if [[ -z "$expected_bytes" ]]; then
        [[ -s "$destination" ]] && return 0
      elif file_size_matches "$destination" "$expected_bytes" >/dev/null 2>&1; then
        return 0
      fi
    done
    actual_bytes=$(stat -c%s "$destination" 2>/dev/null || printf 0)
    installer_error \
      "download remained incomplete after $attempts attempts: expected ${expected_bytes:-unknown} bytes, found $actual_bytes"
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    installer_error "neither wget nor curl is available for download"
    return
  fi

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    curl -fL --retry 0 --connect-timeout 20 -C - \
      -o "$destination" "$url" || true
    if [[ -z "$expected_bytes" ]]; then
      [[ -s "$destination" ]] && return 0
    elif file_size_matches "$destination" "$expected_bytes" >/dev/null 2>&1; then
      return 0
    fi
  done
  actual_bytes=$(stat -c%s "$destination" 2>/dev/null || printf 0)
  installer_error \
    "download remained incomplete after $attempts attempts: expected ${expected_bytes:-unknown} bytes, found $actual_bytes"
  return
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

validate_contract_payload() {
  local observed_source_architecture="$1"
  local observed_target_architecture="$2"
  local observed_electron="$3"
  local observed_main="$4"
  local required_path payload_path

  [[ "${RELEASE_APPLICATION_PROFILE:-}" == "chatgpt-app-only" ]] || {
    installer_error \
      "unsupported application profile: ${RELEASE_APPLICATION_PROFILE:-missing}"
    return
  }
  [[ "$(plist_value "$CHATGPT_PLIST" CFBundleIdentifier)" == "$RELEASE_BUNDLE_ID" ]] || {
    installer_error "bundle identifier mismatch with current release contract"
    return
  }
  [[ "$(plist_value "$CHATGPT_PLIST" CFBundleShortVersionString)" == "$RELEASE_APP_VERSION" ]] || {
    installer_error "application version mismatch with current release contract"
    return
  }
  [[ "$(plist_value "$CHATGPT_PLIST" CFBundleVersion)" == "$RELEASE_APP_BUILD" ]] || {
    installer_error "application build mismatch with current release contract"
    return
  }
  [[ "$observed_source_architecture" == "$RELEASE_SOURCE_ARCHITECTURE" ]] || {
    installer_error \
      "source application architecture mismatch: expected $RELEASE_SOURCE_ARCHITECTURE, found $observed_source_architecture"
    return
  }
  [[ "$observed_target_architecture" == "$RELEASE_TARGET_ARCHITECTURE" ]] || {
    installer_error \
      "target Linux architecture mismatch: expected $RELEASE_TARGET_ARCHITECTURE, found $observed_target_architecture"
    return
  }
  [[ "$observed_electron" == "$RELEASE_ELECTRON_VERSION" ]] || {
    installer_error \
      "Electron version mismatch: expected $RELEASE_ELECTRON_VERSION, found $observed_electron"
    return
  }
  [[ "$observed_main" == "$RELEASE_MAIN_ENTRY" ]] || {
    installer_error \
      "main entry mismatch: expected $RELEASE_MAIN_ENTRY, found $observed_main"
    return
  }

  for required_path in "${RELEASE_REQUIRED_PATHS[@]}"; do
    case "$required_path" in
      ChatGPT.app/*)
        payload_path="$CHATGPT_APP_ROOT/${required_path#ChatGPT.app/}"
        ;;
      *)
        installer_error \
          "required release path is outside ChatGPT.app: $required_path"
        return
        ;;
    esac
    [[ -e "$payload_path" ]] || {
      installer_error "required release path is missing: $required_path"
      return
    }
  done
}

write_candidate_audit_evidence() {
  local audit_dir="$1"
  local version="$2"
  local build="$3"
  local bundle_id="$4"
  local source_architecture="$5"
  local electron_version="$6"
  local main_entry="$7"
  local dmg_bytes="$8"
  local dmg_sha256="$9"
  local source_url="${10}"
  local node_bin="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"

  [[ -n "$node_bin" && -x "$node_bin" ]] || {
    installer_error "Node runtime is unavailable for candidate evidence"
    return
  }
  mkdir -p "$audit_dir" || return
  "$node_bin" - "$audit_dir/candidate-evidence.json" \
    "$version" "$build" "$bundle_id" "$source_architecture" \
    "$electron_version" "$main_entry" "$dmg_bytes" "$dmg_sha256" \
    "$source_url" <<'NODE'
const fs = require("fs");
const [
  outputPath,
  version,
  build,
  bundleId,
  sourceArchitecture,
  electronVersion,
  mainEntry,
  dmgBytes,
  dmgSha256,
  sourceUrl,
] = process.argv.slice(2);
const evidence = {
  schemaVersion: 1,
  mode: "audit-candidate",
  application: { version, build, bundleId, sourceArchitecture, electronVersion, mainEntry },
  dmg: { bytes: Number(dmgBytes), sha256: dmgSha256, sourceUrl },
};
fs.writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`);
NODE
}

validate_staging_native_modules() {
  local staging_dir="$1"
  local electron="$staging_dir/node_modules/.bin/electron"

  [[ -x "$electron" ]] || {
    installer_error "staging Electron runtime is unavailable: $electron"
    return
  }
  ELECTRON_RUN_AS_NODE=1 "$electron" -e '
    const path = require("path");
    const { createRequire } = require("module");
    const root = process.argv[1];
    const requireFromStaging = createRequire(path.join(root, "package.json"));
    for (const name of [
      "@parcel/watcher",
      "bufferutil",
      "utf-8-validate",
      "node-pty",
      "better-sqlite3",
    ]) {
      requireFromStaging(name);
      process.stdout.write(`loaded ${name}\n`);
    }
  ' "$staging_dir" || {
    installer_error "staging native-module Electron ABI validation failed"
    return
  }
}

terminate_owned_process_group() {
  local owned_pgid="$1"
  local caller_pgid

  [[ "$owned_pgid" =~ ^[1-9][0-9]*$ ]] || {
    installer_error "invalid owned GUI process group: $owned_pgid"
    return
  }
  caller_pgid=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')
  [[ -n "$caller_pgid" && "$owned_pgid" != "$caller_pgid" ]] || {
    installer_error "refusing to signal the installer process group"
    return
  }
  kill -TERM -- "-$owned_pgid" 2>/dev/null || true
  kill -KILL -- "-$owned_pgid" 2>/dev/null || true
}

run_staging_gui_smoke() {
  local staging_dir="$1"
  local log_file="$2"
  local smoke_seconds="${CHATGPT_GUI_SMOKE_SECONDS:-20}"
  local status=0
  local started_at elapsed smoke_pid smoke_state_dir

  [[ "$smoke_seconds" =~ ^[1-9][0-9]*$ ]] && (( smoke_seconds <= 60 )) || {
    installer_error "GUI smoke timeout must be between 1 and 60 seconds"
    return
  }
  [[ -x "$staging_dir/$CHATGPT_LAUNCHER_NAME" ]] || {
    installer_error "staging launcher is unavailable"
    return
  }
  command -v setsid >/dev/null 2>&1 || {
    installer_error "setsid is required for isolated GUI smoke cleanup"
    return
  }
  mkdir -p "$(dirname "$log_file")" || return
  smoke_state_dir="$(dirname "$log_file")/gui-smoke-state"
  mkdir -p \
    "$smoke_state_dir/home" \
    "$smoke_state_dir/config" \
    "$smoke_state_dir/cache" \
    "$smoke_state_dir/data" \
    "$smoke_state_dir/codex" || return
  started_at=$SECONDS
  HOME="$smoke_state_dir/home" \
    XDG_CONFIG_HOME="$smoke_state_dir/config" \
    XDG_CACHE_HOME="$smoke_state_dir/cache" \
    XDG_DATA_HOME="$smoke_state_dir/data" \
    CODEX_HOME="$smoke_state_dir/codex" \
    CODEX_LINUX_REMOTE_CONTROL=0 \
    setsid timeout --foreground --signal=TERM --kill-after=2s "${smoke_seconds}s" \
    "$staging_dir/$CHATGPT_LAUNCHER_NAME" \
    --enable-logging --disable-crash-reporter \
    >"$log_file" 2>&1 &
  smoke_pid=$!
  if wait "$smoke_pid"; then
    status=0
  else
    status=$?
  fi
  elapsed=$((SECONDS - started_at))
  terminate_owned_process_group "$smoke_pid" || return

  if (( (status != 124 && status != 137) || elapsed < smoke_seconds )); then
    installer_error \
      "GUI smoke exited before its timeout with status $status; see $log_file"
    return
  fi
  if ! grep -Eiq \
    'mounted (the )?application route|application route .*mounted|React root render requested' \
    "$log_file"; then
    installer_error \
      "GUI smoke stayed alive but did not log renderer route/root evidence; see $log_file"
    return
  fi
}

record_staging_validation() {
  local staging_dir="$1"
  local gui_status="$2"
  local node_bin="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"
  local build_info="$staging_dir/build-info.json"

  [[ -f "$build_info" && -n "$node_bin" && -x "$node_bin" ]] || return 0
  "$node_bin" - "$build_info" "$gui_status" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const guiSmoke = process.argv[3];
const value = JSON.parse(fs.readFileSync(file, "utf8"));
value.stagingValidation = {
  nativeModules: "passed",
  guiSmoke,
};
fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
NODE
}

prune_old_previous_outputs() {
  local output_dir="$1"
  local keep_dir="$2"
  local output_parent output_name candidate

  output_parent=$(dirname "$output_dir") || return
  output_name=$(basename "$output_dir") || return
  while IFS= read -r -d '' candidate; do
    [[ "$candidate" != "$keep_dir" ]] || continue
    if [[ -f "$candidate/build-info.json" &&
          -f "$candidate/$CHATGPT_LAUNCHER_NAME" ]]; then
      rm -rf -- "$candidate" || return
    else
      printf '[!] preserving unrecognized previous-output path: %s\n' \
        "$candidate" >&2
    fi
  done < <(
    find "$output_parent" -maxdepth 1 -type d \
      -name "$output_name.previous.*" -print0
  )
}

promote_staged_output() {
  local staging_dir="$1"
  local output_dir="$2"
  local timestamp

  [[ -d "$staging_dir" ]] || {
    installer_error "validated staging output is missing: $staging_dir"
    return
  }
  PREVIOUS_DIR=""
  if [[ -e "$output_dir" ]]; then
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    PREVIOUS_DIR="${output_dir}.previous.${timestamp}.$$"
    [[ ! -e "$PREVIOUS_DIR" ]] || {
      installer_error "backup path already exists: $PREVIOUS_DIR"
      return
    }
    mv -- "$output_dir" "$PREVIOUS_DIR" || {
      installer_error "failed to preserve the existing generated output"
      return
    }
  fi

  if ! mv -- "$staging_dir" "$output_dir"; then
    if [[ -n "$PREVIOUS_DIR" && -e "$PREVIOUS_DIR" ]]; then
      mv -- "$PREVIOUS_DIR" "$output_dir" || {
        installer_error \
          "promotion and rollback both failed; preserved output remains at $PREVIOUS_DIR"
        return
      }
      PREVIOUS_DIR=""
    fi
    installer_error "failed to promote validated staging output"
    return
  fi
  prune_old_previous_outputs "$output_dir" "$PREVIOUS_DIR" ||
    printf '[!] validated output was promoted, but an older rollback could not be pruned\n' >&2
}

validate_and_promote_staging() {
  local staging_dir="$1"
  local output_dir="$2"
  local skip_gui_smoke="$3"
  local gui_log="$4"

  validate_staging_native_modules "$staging_dir" || return
  if (( skip_gui_smoke )); then
    printf '[!] GUI smoke validation SKIPPED by --skip-gui-smoke\n' >&2
    record_staging_validation "$staging_dir" skipped || return
  else
    run_staging_gui_smoke "$staging_dir" "$gui_log" || return
    record_staging_validation "$staging_dir" passed || return
  fi
  promote_staged_output "$staging_dir" "$output_dir"
}

write_chatgpt_launcher() {
  local output_dir="$1"
  local runtime_node_bin="$2"
  local runtime_npm_bin="$3"
  local launcher="$output_dir/$CHATGPT_LAUNCHER_NAME"

  [[ -x "$runtime_node_bin" ]] || {
    installer_error "selected runtime Node is not executable: $runtime_node_bin"
    return
  }
  [[ -f "$runtime_npm_bin" ]] || {
    installer_error "selected runtime npm is unavailable: $runtime_npm_bin"
    return
  }
  mkdir -p "$output_dir/bin"

  {
    cat <<'CLIWRAP_HEAD'
#!/usr/bin/env bash
set -euo pipefail
CLIWRAP_HEAD
    printf 'RUNTIME_NODE_BIN=%q\n' "$runtime_node_bin"
    printf 'RUNTIME_NPM_BIN=%q\n' "$runtime_npm_bin"
    cat <<'CLIWRAP_BODY'
if [ ! -x "$RUNTIME_NODE_BIN" ]; then
  printf 'recorded Node runtime is unavailable: %s\n' "$RUNTIME_NODE_BIN" >&2
  exit 1
fi
if [ ! -f "$RUNTIME_NPM_BIN" ]; then
  printf 'recorded npm runtime is unavailable: %s\n' "$RUNTIME_NPM_BIN" >&2
  exit 1
fi
exec "$RUNTIME_NODE_BIN" "$RUNTIME_NPM_BIN" \
  exec --yes @openai/codex@latest -- "$@"
CLIWRAP_BODY
  } >"$output_dir/bin/codex-fallback"
  chmod +x "$output_dir/bin/codex-fallback" || return

  {
    cat <<'LAUNCHER_HEAD'
#!/usr/bin/env bash
set -euo pipefail
LAUNCHER_HEAD
    printf 'RUNTIME_NODE_BIN=%q\n' "$runtime_node_bin"
    printf 'RUNTIME_NPM_BIN=%q\n' "$runtime_npm_bin"
    cat <<'LAUNCHER_BODY'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -x "$RUNTIME_NODE_BIN" ]; then
  printf 'recorded Node runtime is unavailable: %s\n' "$RUNTIME_NODE_BIN" >&2
  exit 1
fi
if [ ! -f "$RUNTIME_NPM_BIN" ]; then
  printf 'recorded npm runtime is unavailable: %s\n' "$RUNTIME_NPM_BIN" >&2
  exit 1
fi

export PATH="$(dirname "$RUNTIME_NODE_BIN"):$PATH"
export ELECTRON_RENDERER_URL="file://${SCRIPT_DIR}/webview/index.html"
export CODEX_CHROME_PLUGIN_ROOT="${SCRIPT_DIR}/plugins/openai-bundled/plugins/chrome"
export CODEX_BROWSER_USE_NODE_PATH="$RUNTIME_NODE_BIN"
export NODE_REPL_NODE_PATH="$RUNTIME_NODE_BIN"

if [ -z "${CODEX_CLI_PATH:-}" ]; then
  if command -v codex >/dev/null 2>&1; then
    export CODEX_CLI_PATH="$(command -v codex)"
  else
    export CODEX_CLI_PATH="${SCRIPT_DIR}/bin/codex-fallback"
  fi
fi

if [ -z "${CODEX_NODE_REPL_PATH:-}" ]; then
  export CODEX_NODE_REPL_PATH="${SCRIPT_DIR}/bin/node_repl-linux"
fi

enable_remote_control_config() {
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local config_file="$codex_home/config.toml"

  mkdir -p "$codex_home"

  "$RUNTIME_NODE_BIN" - "$config_file" <<'NODE'
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
  [ "${CODEX_LINUX_REMOTE_CONTROL:-0}" = "1" ] || return 0
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
LAUNCHER_BODY
  } >"$launcher"

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
  local expected_bundle_id="${1:-}"
  local observed_bundle_id

  [[ -d "${CHATGPT_APP_ROOT:-}" ]] || {
    installer_error "missing ChatGPT.app root"
    return
  }
  [[ -f "${CHATGPT_PLIST:-}" ]] || {
    installer_error "missing Info.plist"
    return
  }
  observed_bundle_id=$(plist_value "$CHATGPT_PLIST" CFBundleIdentifier)
  [[ -n "$observed_bundle_id" ]] || {
    installer_error "missing bundle identifier in Info.plist"
    return
  }
  if [[ -n "$expected_bundle_id" && "$observed_bundle_id" != "$expected_bundle_id" ]]; then
    installer_error "unexpected bundle identifier in Info.plist"
    return
  fi
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
