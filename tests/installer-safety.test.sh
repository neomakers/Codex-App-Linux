#!/usr/bin/env bash

set +u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMPDIR="$(mktemp -d)"
TEST_FAILURES=0
ORIGINAL_PATH="$PATH"
ORIGINAL_NODE_BIN="$(command -v node)"

cleanup() {
  local proc pid pgid caller_pgid command_line
  caller_pgid=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')
  for proc in /proc/[0-9]*; do
    [[ -r "$proc/cmdline" ]] || continue
    command_line=$(tr '\0' ' ' <"$proc/cmdline" 2>/dev/null || true)
    [[ "$command_line" == *"$TEST_TMPDIR"* ]] || continue
    pid=${proc#/proc/}
    [[ "$pid" != "$$" ]] || continue
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ "$pgid" =~ ^[1-9][0-9]*$ ]] || continue
    [[ "$pgid" != "$caller_pgid" ]] || continue
    kill -TERM -- "-$pgid" 2>/dev/null || true
    kill -KILL -- "-$pgid" 2>/dev/null || true
  done
  rm -rf "$TEST_TMPDIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  TEST_FAILURES=$((TEST_FAILURES + 1))
}

assert_ok() {
  if ! "$@"; then
    fail "expected success: $*"
  fi
}

assert_fail_with() {
  local expected="$1"
  shift
  local output

  if output=$("$@" 2>&1); then
    fail "expected failure: $*"
  elif [[ "$output" != *"$expected"* ]]; then
    fail "expected error containing '$expected', got: $output"
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"

  [[ "$expected" == "$actual" ]] ||
    fail "expected '$expected', got '$actual'"
}

assert_file_contains() {
  local file="$1"
  local expected="$2"

  grep -Fq -- "$expected" "$file" ||
    fail "expected $file to contain: $expected"
}

write_plist() {
  local plist="$1"
  local bundle_id="$2"
  local version="$3"
  local build="$4"

  mkdir -p "$(dirname "$plist")"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>${bundle_id}</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${build}</string>
  <key>CFBundleExecutable</key>
  <string>ChatGPT</string>
</dict>
</plist>
EOF
}

make_audit_cli_fakes() {
  local bin_dir="$1"
  local node_bin="${2:-$ORIGINAL_NODE_BIN}"

  mkdir -p "$bin_dir"
  cat >"$bin_dir/node" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
  printf 'v22.23.2\n'
  exit 0
fi
exec "$node_bin" "\$@"
EOF
  cat >"$bin_dir/npm" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf '10.9.2\n'
  exit 0
fi
destination="${@: -1}"
mkdir -p "$destination"
cp -a "$AUDIT_FIXTURE_APP_SOURCE/." "$destination/"
EOF
  cat >"$bin_dir/7z" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "t" ]]; then
  exit 0
fi
if [[ "${1:-}" == "x" ]]; then
  destination=''
  for argument in "$@"; do
    case "$argument" in
      -o*) destination="${argument#-o}" ;;
    esac
  done
  [[ -n "$destination" ]] || exit 71
  mkdir -p "$destination"
  cp -a "$AUDIT_FIXTURE_PAYLOAD/." "$destination/"
  exit 0
fi
exit 72
EOF
  cat >"$bin_dir/file" <<'EOF'
#!/usr/bin/env bash
printf 'Mach-O 64-bit executable arm64\n'
EOF
  chmod +x "$bin_dir/node" "$bin_dir/npm" "$bin_dir/7z" "$bin_dir/file"
}

make_complete_payload() {
  local fixture="$1"
  local app_root="$fixture/ChatGPT Installer/ChatGPT.app"

  write_plist "$app_root/Contents/Info.plist" \
    com.openai.codex 26.727.40816 6067
  mkdir -p \
    "$app_root/Contents/Resources/app.asar.unpacked" \
    "$app_root/Contents/Resources/plugins"
  : >"$app_root/Contents/Resources/app.asar"
}

make_always_short_curl() {
  local bin_dir="$1"
  local state_file="$2"

  mkdir -p "$bin_dir"
  cat >"$bin_dir/curl" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" -fsSIL "* ]]; then
  printf 'HTTP/2 200\r\nContent-Length: 10\r\n\r\n'
  exit 0
fi
destination=''
while (( \$# > 0 )); do
  if [[ "\$1" == "-o" ]]; then
    destination="\$2"
    shift 2
    continue
  fi
  shift
done
count=0
[[ -f '${state_file}' ]] && count=\$(< '${state_file}')
count=\$((count + 1))
printf '%s\n' "\$count" >'${state_file}'
/usr/bin/truncate -s 4 "\$destination"
EOF
  chmod +x "$bin_dir/curl"
  cat >"$bin_dir/wget" <<EOF
#!/usr/bin/env bash
destination=''
while (( \$# > 0 )); do
  if [[ "\$1" == "-O" ]]; then
    destination="\$2"
    shift 2
    continue
  fi
  shift
done
count=0
[[ -f '${state_file}' ]] && count=\$(< '${state_file}')
count=\$((count + 1))
printf '%s\n' "\$count" >'${state_file}'
/usr/bin/truncate -s 4 "\$destination"
EOF
  chmod +x "$bin_dir/wget"
}

# shellcheck source=../lib/chatgpt-installer.sh
source "$ROOT_DIR/lib/chatgpt-installer.sh"

# Break caught: a 20-second default rejects valid first launches whose isolated
# state initialization reaches the renderer just after the old deadline.
assert_eq 40 "$GUI_SMOKE_SECONDS_DEFAULT"
assert_eq 90 "$GUI_SMOKE_SECONDS_MAX"

# Break caught: normal installation stops loading compatibility/current.json.
assert_ok load_current_release_contract "$ROOT_DIR/compatibility" "$(command -v node)"
assert_eq chatgpt-app-only "$RELEASE_APPLICATION_PROFILE"
assert_eq com.openai.codex "$RELEASE_BUNDLE_ID"
assert_eq 26.727.40816 "$RELEASE_APP_VERSION"
assert_eq 6067 "$RELEASE_APP_BUILD"
assert_eq arm64 "$RELEASE_SOURCE_ARCHITECTURE"
assert_eq x64 "$RELEASE_TARGET_ARCHITECTURE"
assert_eq 42.3.0 "$RELEASE_ELECTRON_VERSION"
assert_eq .vite/build/early-bootstrap.js "$RELEASE_MAIN_ENTRY"
assert_eq 609303023 "$RELEASE_DMG_BYTES"
assert_eq fb93a239c811c7639cf45a90ff36c262fa0290640140cd12da3fdc60b62255ae \
  "$RELEASE_DMG_SHA256"
assert_eq 4 "${#RELEASE_REQUIRED_PATHS[@]}"

# Break caught: an incompatible cache is moved into cleanup-owned storage and
# deleted even though the installer reports it as preserved.
fixture="$TEST_TMPDIR/quarantine"
mkdir -p "$fixture"
printf incompatible >"$fixture/ChatGPT-latest.dmg"
quarantine_path=$(quarantine_file "$fixture/ChatGPT-latest.dmg" identity-mismatch)
[[ ! -e "$fixture/ChatGPT-latest.dmg" ]] ||
  fail "quarantined cache remained at the active cache path"
assert_eq incompatible "$(<"$quarantine_path")"
assert_eq "$fixture" "$(dirname "$quarantine_path")"

# Break caught: a same-size but wrong-hash DMG reaches extraction.
fixture="$TEST_TMPDIR/identity"
mkdir -p "$fixture"
printf contract >"$fixture/candidate.dmg"
candidate_sha=$(sha256sum "$fixture/candidate.dmg" | awk '{print $1}')
assert_ok verify_file_identity "$fixture/candidate.dmg" 8 "$candidate_sha"
assert_fail_with "DMG size mismatch: expected 9 bytes, found 8" \
  verify_file_identity "$fixture/candidate.dmg" 9 "$candidate_sha"
assert_fail_with "DMG SHA-256 mismatch" \
  verify_file_identity "$fixture/candidate.dmg" 8 \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# Break caught: mutable remote size changes and downloading begins anyway.
fixture="$TEST_TMPDIR/remote-size"
mkdir -p "$fixture/bin"
cat >"$fixture/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'HTTP/2 200\r\nContent-Length: 11\r\n\r\n'
EOF
chmod +x "$fixture/bin/curl"
PATH="$fixture/bin:$ORIGINAL_PATH"
assert_fail_with "remote candidate size 11 does not match current release contract 10" \
  require_remote_size_matches_contract https://example.invalid/ChatGPT.dmg 10
PATH="$ORIGINAL_PATH"

# Break caught: version/build/main/Electron/architecture or required paths drift.
fixture="$TEST_TMPDIR/payload"
make_complete_payload "$fixture"
assert_ok discover_chatgpt_payload "$fixture"
assert_ok validate_contract_payload \
  arm64 x64 42.3.0 .vite/build/early-bootstrap.js
assert_fail_with "main entry mismatch" \
  validate_contract_payload arm64 x64 42.3.0 wrong-main.js
rm -rf "$fixture/ChatGPT Installer/ChatGPT.app/Contents/Resources/plugins"
assert_fail_with "required release path is missing" \
  validate_contract_payload arm64 x64 42.3.0 .vite/build/early-bootstrap.js

# Break caught: candidate audit overwrites/promotes the current installation.
fixture="$TEST_TMPDIR/audit"
mkdir -p "$fixture/audit" "$fixture/current-output"
printf old >"$fixture/current-output/sentinel"
assert_ok write_candidate_audit_evidence \
  "$fixture/audit" 27.1.2 7000 com.openai.codex x64 43.0.0 main.js \
  1234 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  https://example.invalid/Codex.dmg
assert_eq old "$(<"$fixture/current-output/sentinel")"
assert_file_contains "$fixture/audit/candidate-evidence.json" '"version": "27.1.2"'
assert_file_contains "$fixture/audit/candidate-evidence.json" '"sourceUrl": "https://example.invalid/Codex.dmg"'
if grep -Fq "$ROOT_DIR" "$fixture/audit/candidate-evidence.json"; then
  fail "candidate evidence contains a machine-local repository path"
fi

# Break caught: audit orchestration rejects a future bundle, records host rather
# than candidate architecture, or mutates an existing installation.
fixture="$TEST_TMPDIR/audit-cli"
payload_root="$fixture/payload/ChatGPT Installer/ChatGPT.app"
app_source="$fixture/app-source"
mkdir -p \
  "$payload_root/Contents/MacOS" \
  "$payload_root/Contents/Resources/app.asar.unpacked" \
  "$app_source" "$fixture/audit" "$fixture/current-output" "$fixture/home"
write_plist "$payload_root/Contents/Info.plist" \
  com.example.future-chatgpt 27.1.2 7000
: >"$payload_root/Contents/MacOS/ChatGPT"
: >"$payload_root/Contents/Resources/app.asar"
printf '{"main":"future-main.js","devDependencies":{"electron":"43.0.0"}}\n' \
  >"$app_source/package.json"
printf old >"$fixture/current-output/sentinel"
printf audit-dmg >"$fixture/future.dmg"
make_audit_cli_fakes "$fixture/bin"
assert_ok env \
  PATH="$fixture/bin:/usr/bin:/bin" \
  HOME="$fixture/home" XDG_CACHE_HOME="$fixture/cache" \
  AUDIT_FIXTURE_PAYLOAD="$fixture/payload" \
  AUDIT_FIXTURE_APP_SOURCE="$app_source" \
  "$ROOT_DIR/install-chatgpt-linux.sh" \
    --audit-candidate \
    --dmg "$fixture/future.dmg" \
    --audit-source-url https://example.invalid/future.dmg \
    --audit-output "$fixture/audit" \
    --output "$fixture/current-output"
assert_eq old "$(<"$fixture/current-output/sentinel")"
assert_file_contains "$fixture/audit/candidate-evidence.json" \
  '"bundleId": "com.example.future-chatgpt"'
assert_file_contains "$fixture/audit/candidate-evidence.json" \
  '"sourceArchitecture": "arm64"'

# Break caught: a remote audit says an existing candidate was preserved but
# moves it into cleanup-owned storage and deletes it on failure.
fixture="$TEST_TMPDIR/audit-existing-candidate"
mkdir -p "$fixture/audit" "$fixture/home"
printf keep-this-candidate >"$fixture/audit/candidate.dmg"
make_audit_cli_fakes "$fixture/bin"
cat >"$fixture/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'HTTP/2 200\r\nContent-Length: 10\r\n\r\n'
EOF
cat >"$fixture/bin/wget" <<'EOF'
#!/usr/bin/env bash
destination=''
while (( $# > 0 )); do
  if [[ "$1" == "-O" ]]; then
    destination="$2"
    shift 2
    continue
  fi
  shift
done
/usr/bin/truncate -s 4 "$destination"
exit 1
EOF
chmod +x "$fixture/bin/curl" "$fixture/bin/wget"
if env \
  PATH="$fixture/bin:/usr/bin:/bin" \
  HOME="$fixture/home" XDG_CACHE_HOME="$fixture/cache" \
  CHATGPT_DOWNLOAD_ATTEMPTS=1 \
  "$ROOT_DIR/install-chatgpt-linux.sh" \
    --audit-candidate --audit-output "$fixture/audit" \
    >"$fixture/install.log" 2>&1; then
  fail "expected the deliberately short audit download to fail"
fi
assert_eq keep-this-candidate "$(<"$fixture/audit/candidate.dmg")"

# Break caught: validation is skipped or promotion runs before native/GUI checks.
fixture="$TEST_TMPDIR/order"
mkdir -p "$fixture/staging"
(
  validation_log="$fixture/order.log"
  validate_staging_native_modules() { printf 'native\n' >>"$validation_log"; }
  run_staging_gui_smoke() { printf 'gui\n' >>"$validation_log"; }
  promote_staged_output() { printf 'promote\n' >>"$validation_log"; }
  assert_ok validate_and_promote_staging \
    "$fixture/staging" "$fixture/output" 0 "$fixture/gui.log"
  assert_eq $'native\ngui\npromote' "$(<"$validation_log")"
)

# Break caught: successful promotion accumulates multiple generated rollbacks.
fixture="$TEST_TMPDIR/single-rollback"
mkdir -p \
  "$fixture/staging" \
  "$fixture/output" \
  "$fixture/output.previous.older"
printf new >"$fixture/staging/sentinel"
printf old >"$fixture/output/sentinel"
printf '{}\n' >"$fixture/output.previous.older/build-info.json"
: >"$fixture/output.previous.older/chatgpt-linux.sh"
assert_ok promote_staged_output "$fixture/staging" "$fixture/output"
previous_count=$(find "$fixture" -maxdepth 1 -type d \
  -name 'output.previous.*' | wc -l)
assert_eq 1 "$previous_count"
assert_eq old "$(<"$PREVIOUS_DIR/sentinel")"

# Break caught: a failed promotion leaves the old output moved aside.
fixture="$TEST_TMPDIR/rollback"
mkdir -p "$fixture/staging" "$fixture/output"
printf new >"$fixture/staging/sentinel"
printf old >"$fixture/output/sentinel"
(
  move_count=0
  mv() {
    move_count=$((move_count + 1))
    if (( move_count == 2 )); then
      return 73
    fi
    command mv "$@"
  }
  assert_fail_with "failed to promote validated staging output" \
    promote_staged_output "$fixture/staging" "$fixture/output"
)
assert_eq old "$(<"$fixture/output/sentinel")"

# Break caught: the native gate does not load every required module through Electron.
fixture="$TEST_TMPDIR/native"
mkdir -p "$fixture/node_modules/.bin"
for module in @parcel/watcher bufferutil utf-8-validate node-pty better-sqlite3; do
  mkdir -p "$fixture/node_modules/$module"
  printf 'module.exports = true;\n' >"$fixture/node_modules/$module/index.js"
done
cat >"$fixture/node_modules/.bin/electron" <<EOF
#!/usr/bin/env bash
[[ "\${ELECTRON_RUN_AS_NODE:-}" == "1" ]] || exit 71
exec "$ORIGINAL_NODE_BIN" "\$@"
EOF
chmod +x "$fixture/node_modules/.bin/electron"
assert_ok validate_staging_native_modules "$fixture"

# Break caught: GUI smoke accepts an early exit or never observes an application route.
fixture="$TEST_TMPDIR/gui"
mkdir -p "$fixture"
cat >"$fixture/chatgpt-linux.sh" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${SMOKE_ENV_CAPTURE:-}" ]]; then
  printf 'HOME=%s\nCODEX_HOME=%s\nXDG_CONFIG_HOME=%s\n' \
    "$HOME" "$CODEX_HOME" "$XDG_CONFIG_HOME" >"$SMOKE_ENV_CAPTURE"
fi
printf 'mounted application route /\n'
sleep 2
EOF
chmod +x "$fixture/chatgpt-linux.sh"
SMOKE_ENV_CAPTURE="$fixture/gui-env.log" \
  CHATGPT_GUI_SMOKE_SECONDS=1 assert_ok \
  run_staging_gui_smoke "$fixture" "$fixture/gui.log"
assert_file_contains "$fixture/gui-env.log" \
  "HOME=$fixture/gui-smoke-state/home"
assert_file_contains "$fixture/gui-env.log" \
  "CODEX_HOME=$fixture/gui-smoke-state/codex"
cat >"$fixture/chatgpt-linux.sh" <<'EOF'
#!/usr/bin/env bash
printf 'mounted application route /\n'
exit 9
EOF
chmod +x "$fixture/chatgpt-linux.sh"
CHATGPT_GUI_SMOKE_SECONDS=1 assert_fail_with "GUI smoke exited before its timeout" \
  run_staging_gui_smoke "$fixture" "$fixture/gui-crash.log"
cat >"$fixture/chatgpt-linux.sh" <<'EOF'
#!/usr/bin/env bash
printf 'main app.whenReady resolved\n'
sleep 2
EOF
chmod +x "$fixture/chatgpt-linux.sh"
CHATGPT_GUI_SMOKE_SECONDS=1 assert_fail_with \
  "did not log renderer route/root evidence" \
  run_staging_gui_smoke "$fixture" "$fixture/gui-no-route.log"
cat >"$fixture/chatgpt-linux.sh" <<'EOF'
#!/usr/bin/env bash
trap '' TERM
printf 'mounted application route /\n'
while :; do sleep 1; done
EOF
chmod +x "$fixture/chatgpt-linux.sh"
smoke_started=$(date +%s)
CHATGPT_GUI_SMOKE_SECONDS=1 assert_ok \
  run_staging_gui_smoke "$fixture" "$fixture/gui-term-resistant.log"
smoke_elapsed=$(($(date +%s) - smoke_started))
(( smoke_elapsed <= 4 )) ||
  fail "GUI smoke did not force-clean a TERM-resistant Electron process"

# Break caught: pathname-based cleanup kills the caller's own process group.
# The whole RED scenario runs in an isolated session so the test runner survives
# the broken implementation and can report the failure.
fixture="$TEST_TMPDIR/gui-process-isolation"
mkdir -p "$fixture"
cat >"$fixture/chatgpt-linux.sh" <<'EOF'
#!/usr/bin/env bash
trap '' TERM
printf 'mounted application route /\n'
while :; do sleep 1; done
EOF
chmod +x "$fixture/chatgpt-linux.sh"
if ! timeout --kill-after=1s 8s setsid bash -c '
  set -Eeuo pipefail
  source "$1"
  marker="$2"
  log_file="$3"
  bash -c "exec -a $marker/unrelated-sentinel sleep 30" &
  sentinel=$!
  trap "kill $sentinel 2>/dev/null || true; wait $sentinel 2>/dev/null || true" EXIT
  CHATGPT_GUI_SMOKE_SECONDS=1 run_staging_gui_smoke "$marker" "$log_file"
  kill -0 "$sentinel"
  printf "parent-and-unrelated-sentinel-survived\n"
' bash "$ROOT_DIR/lib/chatgpt-installer.sh" "$fixture" "$fixture/gui.log" \
  >"$fixture/isolation.log" 2>&1; then
  fail "GUI smoke killed its caller group or leaked its owned process group"
fi
assert_file_contains "$fixture/isolation.log" \
  'parent-and-unrelated-sentinel-survived'

# Break caught: launcher uses PATH Node, starts remote control by default, or lies about key protection.
fixture="$TEST_TMPDIR/launcher"
runtime_dir="$fixture/recorded-runtime"
output_dir="$fixture/chatgpt-linux"
mkdir -p "$runtime_dir/bin" "$output_dir/node_modules/.bin" "$fixture/home"
cat >"$runtime_dir/bin/node" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$fixture/runtime-node.log'
exit 0
EOF
cat >"$runtime_dir/bin/npm" <<'EOF'
// npm CLI fixture
EOF
cat >"$output_dir/node_modules/.bin/electron" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${CODEX_BROWSER_USE_NODE_PATH:-}" >'$fixture/browser-node.log'
printf '%s\n' "\${NODE_REPL_NODE_PATH:-}" >'$fixture/repl-node.log'
exit 0
EOF
cat >"$fixture/fake-codex" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$fixture/codex-cli.log'
exit 0
EOF
chmod +x \
  "$runtime_dir/bin/node" "$runtime_dir/bin/npm" \
  "$output_dir/node_modules/.bin/electron" "$fixture/fake-codex"
assert_ok write_chatgpt_launcher \
  "$output_dir" "$runtime_dir/bin/node" "$runtime_dir/bin/npm"
HOME="$fixture/home" PATH=/usr/bin:/bin CODEX_CLI_PATH="$fixture/fake-codex" \
  assert_ok "$output_dir/chatgpt-linux.sh"
assert_eq "$runtime_dir/bin/node" "$(<"$fixture/browser-node.log")"
assert_eq "$runtime_dir/bin/node" "$(<"$fixture/repl-node.log")"
[[ ! -e "$fixture/home/.codex/config.toml" ]] ||
  fail "launcher mutated Codex config without explicit opt-in"
[[ ! -e "$fixture/codex-cli.log" ]] ||
  fail "launcher started remote control without explicit opt-in"
assert_ok timeout 2s env PATH=/usr/bin:/bin \
  "$output_dir/bin/codex-fallback" --version
assert_file_contains "$fixture/runtime-node.log" \
  "$runtime_dir/bin/npm exec --yes @openai/codex@latest -- --version"
if grep -R -Fq os_protected_nonextractable "$output_dir"; then
  fail "generated product falsely claims nonextractable software-key protection"
fi
mv "$runtime_dir/bin/node" "$runtime_dir/bin/node.missing"
assert_fail_with "recorded Node runtime is unavailable" \
  env HOME="$fixture/home" PATH=/usr/bin:/bin "$output_dir/chatgpt-linux.sh"

# Break caught: successful but permanently short transfers retry forever.
fixture="$TEST_TMPDIR/retries"
make_always_short_curl "$fixture/bin" "$fixture/count"
PATH="$fixture/bin:/usr/bin:/bin"
assert_fail_with "download remained incomplete after 3 attempts" \
  timeout 2s bash -c \
  'source "$1"; PATH="$2"; download_resumable "$3" "$4" 10' \
  bash "$ROOT_DIR/lib/chatgpt-installer.sh" "$fixture/bin:/usr/bin:/bin" \
  https://example.invalid/ChatGPT.dmg "$fixture/candidate.dmg"
assert_eq 3 "$(<"$fixture/count")"
PATH="$ORIGINAL_PATH"

# Break caught: unknown-length downloads accept a pre-created empty file as a
# successful candidate even when every transfer fails.
fixture="$TEST_TMPDIR/unknown-length"
mkdir -p "$fixture/bin"
cat >"$fixture/bin/wget" <<'EOF'
#!/usr/bin/env bash
destination=''
while (( $# > 0 )); do
  if [[ "$1" == "-O" ]]; then
    destination="$2"
    shift 2
    continue
  fi
  shift
done
: >"$destination"
exit 1
EOF
cat >"$fixture/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture/bin/wget" "$fixture/bin/curl"
: >"$fixture/candidate.dmg"
PATH="$fixture/bin:/usr/bin:/bin"
assert_fail_with "download remained incomplete after 1 attempts" \
  env CHATGPT_DOWNLOAD_ATTEMPTS=1 bash -c \
    'source "$1"; PATH="$2"; download_resumable "$3" "$4"' \
    bash "$ROOT_DIR/lib/chatgpt-installer.sh" \
    "$fixture/bin:/usr/bin:/bin" https://example.invalid/unknown.dmg \
    "$fixture/candidate.dmg"
PATH="$ORIGINAL_PATH"

if (( TEST_FAILURES > 0 )); then
  printf '%d test assertion(s) failed\n' "$TEST_FAILURES" >&2
  exit 1
fi

printf 'All installer safety tests passed\n'
