#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMPDIR="$(mktemp -d)"
TEST_FAILURES=0
ORIGINAL_PATH="$PATH"

cleanup() {
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

assert_fail() {
  if "$@"; then
    fail "expected failure: $*"
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

  if [[ "$expected" != "$actual" ]]; then
    fail "expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local expected="$1"
  local actual="$2"

  if [[ "$actual" != *"$expected"* ]]; then
    fail "expected '$actual' to contain '$expected'"
  fi
}

assert_file() {
  local file="$1"
  [[ -f "$file" ]] || fail "expected file: $file"
}

assert_executable() {
  local file="$1"
  [[ -x "$file" ]] || fail "expected executable: $file"
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" ||
    fail "expected $file to contain: $expected"
}

assert_file_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "$unexpected" "$file"; then
    fail "expected $file not to contain: $unexpected"
  fi
}

assert_file_not_exists() {
  local file="$1"
  [[ ! -e "$file" ]] || fail "expected file not to exist: $file"
}

assert_command_contains() {
  local expected="$1"
  shift
  local output

  if ! output=$("$@" 2>&1); then
    fail "expected command success: $*; output: $output"
    return
  fi
  if [[ "$output" != *"$expected"* ]]; then
    fail "expected command output to contain '$expected', got: $output"
  fi
}

assert_command_fails_with() {
  local expected="$1"
  shift
  local output

  if output=$("$@" 2>&1); then
    fail "expected command failure: $*"
  elif [[ "$output" != *"$expected"* ]]; then
    fail "expected command error containing '$expected', got: $output"
  fi
}

make_fake_node() {
  local node_path="$1"
  local version="$2"

  mkdir -p "$(dirname "$node_path")"
  cat >"$node_path" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
  printf '%s\\n' '$version'
fi
EOF
  chmod +x "$node_path"
}

make_fake_npm() {
  local npm_path="$1"

  mkdir -p "$(dirname "$npm_path")"
  cat >"$npm_path" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$npm_path"
}

make_fake_7z() {
  local seven_zip_path="$1"

  mkdir -p "$(dirname "$seven_zip_path")"
  cat >"$seven_zip_path" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "t" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "$seven_zip_path"
}

make_fake_http_tools() {
  local bin_dir="$1"
  local expected_bytes="$2"
  local wget_bytes="$3"

  mkdir -p "$bin_dir"
  cat >"$bin_dir/curl" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" -fsSIL "* ]]; then
  printf 'HTTP/2 302\r\ncontent-length: 7\r\nHTTP/2 200\r\nContent-Length: ${expected_bytes}\r\n\r\n'
  exit 0
fi
exit 1
EOF
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
/usr/bin/truncate -s ${wget_bytes} "\$destination"
EOF
  chmod +x "$bin_dir/curl" "$bin_dir/wget"
}

make_fake_curl_only_tools() {
  local bin_dir="$1"
  local expected_bytes="$2"
  local state_file="$3"

  mkdir -p "$bin_dir"
  for tool in awk bash dirname mkdir stat; do
    ln -s "/usr/bin/$tool" "$bin_dir/$tool"
  done
  cat >"$bin_dir/curl" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" -fsSIL "* ]]; then
  printf 'HTTP/2 200\r\nContent-Length: ${expected_bytes}\r\n\r\n'
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
if (( count == 1 )); then
  /usr/bin/truncate -s 4 "\$destination"
else
  /usr/bin/truncate -s ${expected_bytes} "\$destination"
fi
EOF
  chmod +x "$bin_dir/curl"
}

make_recording_7z() {
  local seven_zip_path="$1"
  local log_path="$2"

  mkdir -p "$(dirname "$seven_zip_path")"
  cat >"$seven_zip_path" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'${log_path}'
[[ "\$1" == "t" ]]
EOF
  chmod +x "$seven_zip_path"
}

make_fake_debian_7zip_tools() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"
  cat >"$bin_dir/apt-get" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "download" && "$2" == "7zip" ]] || exit 1
: >7zip-test.deb
EOF
  cat >"$bin_dir/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "-x" ]] || exit 1
root_dir="$3"
/usr/bin/mkdir -p "$root_dir/usr/lib/7zip"
cat >"$root_dir/usr/lib/7zip/7z" <<'SEVENZIP'
#!/usr/bin/env bash
exit 0
SEVENZIP
/usr/bin/chmod +x "$root_dir/usr/lib/7zip/7z"
EOF
  chmod +x "$bin_dir/apt-get" "$bin_dir/dpkg-deb"
}

make_fake_node_bootstrap() {
  local hook_path="$1"

  cat >"$hook_path" <<'EOF'
#!/usr/bin/env bash
runtime_dir="$1"
mkdir -p "$runtime_dir/bin"
cat >"$runtime_dir/bin/node" <<'NODE'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf '%s\n' v22.23.2
fi
NODE
cat >"$runtime_dir/bin/npm" <<'NPM'
#!/usr/bin/env bash
exit 0
NPM
chmod +x "$runtime_dir/bin/node" "$runtime_dir/bin/npm"
EOF
  chmod +x "$hook_path"
}

write_plist() {
  local plist="$1"
  local bundle_id="$2"

  mkdir -p "$(dirname "$plist")"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>${bundle_id}</string>
  <key>CFBundleShortVersionString</key>
  <string>26.727.40816</string>
  <key>CFBundleVersion</key>
  <string>6067</string>
</dict>
</plist>
EOF
}

make_chatgpt_fixture() {
  local fixture="$1"
  local app_root="$fixture/ChatGPT Installer/ChatGPT.app"

  write_plist "$app_root/Contents/Info.plist" "com.openai.codex"
  mkdir -p "$app_root/Contents/Resources/app.asar.unpacked"
  : >"$app_root/Contents/Resources/app.asar"
}

make_codex_fixture() {
  local fixture="$1"
  local app_root="$fixture/Codex Installer/Codex.app"

  write_plist "$app_root/Contents/Info.plist" "com.openai.codex"
  mkdir -p "$app_root/Contents/Resources/app.asar.unpacked"
  : >"$app_root/Contents/Resources/app.asar"
}

# shellcheck source=../lib/chatgpt-installer.sh
source "$ROOT_DIR/lib/chatgpt-installer.sh"

assert_ok version_at_least 22.23.2 22.12.0
assert_fail version_at_least 18.19.1 22.12.0
assert_eq x64 "$(normalize_linux_arch x86_64)"
assert_eq arm64 "$(normalize_linux_arch aarch64)"
assert_fail normalize_linux_arch riscv64

plist_fixture="$TEST_TMPDIR/indented.plist"
write_plist "$plist_fixture" "com.openai.codex"
assert_eq com.openai.codex "$(plist_value "$plist_fixture" CFBundleIdentifier)"

fixture="$TEST_TMPDIR/payload"
make_chatgpt_fixture "$fixture"
assert_ok discover_chatgpt_payload "$fixture"
assert_eq "$fixture/ChatGPT Installer/ChatGPT.app" "$CHATGPT_APP_ROOT"
assert_ok validate_chatgpt_payload

rm -rf "$fixture/ChatGPT Installer/ChatGPT.app/Contents/Resources/app.asar.unpacked"
assert_fail_with "missing app.asar.unpacked" validate_chatgpt_payload

fixture="$TEST_TMPDIR/codex-only"
make_codex_fixture "$fixture"
assert_fail_with "unsupported DMG layout: ChatGPT.app not found" \
  discover_chatgpt_payload "$fixture"

fixture="$TEST_TMPDIR/download-and-toolchain"
mkdir -p "$fixture/bin" "$fixture/old-bin" "$fixture/work"
truncate -s 100 "$fixture/ChatGPT-latest.dmg"
assert_ok file_size_matches "$fixture/ChatGPT-latest.dmg" 100
assert_fail_with "incomplete DMG: expected 101 bytes, found 100" \
  file_size_matches "$fixture/ChatGPT-latest.dmg" 101

make_fake_node "$fixture/bin/node" "v22.23.2"
make_fake_npm "$fixture/bin/npm"
PATH="$fixture/bin:/usr/bin:/bin"
assert_ok resolve_node "$fixture/work"
assert_eq "$fixture/bin/node" "$NODE_BIN"

make_fake_node "$fixture/old-bin/node" "v18.19.1"
make_fake_node_bootstrap "$fixture/fake-node-bootstrap"
PATH="$fixture/old-bin:/usr/bin:/bin"
CHATGPT_NODE_DOWNLOAD_HOOK="$fixture/fake-node-bootstrap"
assert_ok resolve_node "$fixture/work"
assert_contains "$fixture/work/node-v22.23.2-linux-" "$NODE_BIN"

make_fake_7z "$fixture/bin/7z"
PATH="$fixture/bin:/usr/bin:/bin"
assert_ok resolve_7zip "$fixture/work"
assert_eq "$fixture/bin/7z" "$SEVEN_ZIP"

fixture="$TEST_TMPDIR/download-integrity"
mkdir -p "$fixture"
make_fake_http_tools "$fixture/http-bin" 120 100
PATH="$fixture/http-bin:$ORIGINAL_PATH"
assert_eq 120 "$(remote_content_length https://example.invalid/ChatGPT.dmg)"
assert_fail_with "download remained incomplete after 3 attempts: expected 120 bytes, found 100" \
  download_resumable https://example.invalid/ChatGPT.dmg "$fixture/wget-partial.dmg"

make_fake_http_tools "$fixture/http-complete-bin" 120 120
PATH="$fixture/http-complete-bin:$ORIGINAL_PATH"
assert_ok download_resumable \
  https://example.invalid/ChatGPT.dmg "$fixture/wget-complete.dmg"
assert_ok file_size_matches "$fixture/wget-complete.dmg" 120

make_fake_curl_only_tools "$fixture/curl-bin" 10 "$fixture/curl-count"
PATH="$fixture/curl-bin"
assert_ok download_resumable \
  https://example.invalid/ChatGPT.dmg "$fixture/curl-resumed.dmg"
assert_eq 2 "$(< "$fixture/curl-count")"
assert_ok file_size_matches "$fixture/curl-resumed.dmg" 10

PATH="$ORIGINAL_PATH"
make_recording_7z "$fixture/recording-7z" "$fixture/7z.log"
SEVEN_ZIP="$fixture/recording-7z"
truncate -s 9 "$fixture/validated.dmg"
assert_fail_with "incomplete DMG: expected 10 bytes, found 9" \
  validate_dmg "$fixture/validated.dmg" 10
[[ ! -e "$fixture/7z.log" ]] || fail "7-Zip ran before size validation passed"
truncate -s 10 "$fixture/validated.dmg"
assert_ok validate_dmg "$fixture/validated.dmg" 10
assert_eq "t $fixture/validated.dmg" "$(< "$fixture/7z.log")"

truncate -s 9 "$fixture/cached-old-release.dmg"
SEVEN_ZIP="$fixture/recording-7z"
assert_ok cached_dmg_is_usable "$fixture/cached-old-release.dmg" 10
SEVEN_ZIP=/usr/bin/false
assert_fail cached_dmg_is_usable "$fixture/cached-old-release.dmg" 10
SEVEN_ZIP="$fixture/recording-7z"

ignored_links_log="$fixture/ignored-links.log"
cat >"$ignored_links_log" <<'EOF'
ERROR: Dangerous link path was ignored : ChatGPT Installer/Applications : /Applications
ERROR: Dangerous symbolic link path was ignored : pkg/node_modules/.bin/tool : ../../../tool
Sub items Errors: 2
EOF
assert_ok extraction_log_has_only_ignored_links "$ignored_links_log"

unexpected_extract_log="$fixture/unexpected-extract.log"
cat >"$unexpected_extract_log" <<'EOF'
ERROR: Data Error : ChatGPT Installer/ChatGPT.app/Contents/Resources/app.asar
EOF
assert_fail extraction_log_has_only_ignored_links "$unexpected_extract_log"

fixture="$TEST_TMPDIR/7zip-fallback"
mkdir -p "$fixture/work"
make_fake_debian_7zip_tools "$fixture/bin"
PATH="$fixture/bin:/usr/bin:/bin"
CHATGPT_DISTRO_ID=debian
assert_ok resolve_7zip "$fixture/work"
assert_eq "$fixture/work/7zip-root/usr/lib/7zip/7z" "$SEVEN_ZIP"

mkdir -p "$fixture/dnf-bin" "$fixture/pacman-bin" "$fixture/zypper-bin"
for pair in "dnf fedora" "pacman arch" "zypper opensuse"; do
  set -- $pair
  : >"$fixture/$1-bin/$1"
  cat >"$fixture/$1-bin/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$fixture/$1-bin/$1" "$fixture/$1-bin/apt-get"
  PATH="$fixture/$1-bin:/usr/bin:/bin"
  CHATGPT_DISTRO_ID="$2"
  assert_fail_with "$1" resolve_7zip "$fixture/$2-work"
done
unset CHATGPT_DISTRO_ID
PATH="$ORIGINAL_PATH"

fixture="$TEST_TMPDIR/launcher"
mkdir -p "$fixture/chatgpt-linux"
assert_ok write_chatgpt_launcher \
  "$fixture/chatgpt-linux" "$NODE_BIN" "$NPM_BIN"
assert_file "$fixture/chatgpt-linux/chatgpt-linux.sh"
assert_executable "$fixture/chatgpt-linux/chatgpt-linux.sh"
assert_file_contains "$fixture/chatgpt-linux/chatgpt-linux.sh" \
  'export CODEX_CLI_PATH='
assert_file_contains "$fixture/chatgpt-linux/chatgpt-linux.sh" \
  'exec ./node_modules/.bin/electron'
assert_file_contains "$fixture/chatgpt-linux/chatgpt-linux.sh" \
  '${XDG_CONFIG_HOME:-$HOME/.config}/chatgpt-linux'

assert_ok write_desktop_entry \
  "$fixture/chatgpt-linux" "$fixture/chatgpt-linux.desktop"
assert_file_contains "$fixture/chatgpt-linux.desktop" 'Name=ChatGPT Linux'
assert_file_contains "$fixture/chatgpt-linux.desktop" \
  "Exec=$fixture/chatgpt-linux/chatgpt-linux.sh %u"
assert_file_contains "$fixture/chatgpt-linux.desktop" \
  'MimeType=x-scheme-handler/codex;'
assert_file_not_contains "$fixture/chatgpt-linux.desktop" 'codex-linux'

assert_command_contains "ChatGPT Linux Installer" \
  "$ROOT_DIR/install-chatgpt-linux.sh" --help
assert_command_contains "--dmg <path>" \
  "$ROOT_DIR/install-chatgpt-linux.sh" --help
assert_command_contains "--audit-source-url <url>" \
  "$ROOT_DIR/install-chatgpt-linux.sh" --help
assert_command_fails_with "Unknown option: --unknown" \
  "$ROOT_DIR/install-chatgpt-linux.sh" --unknown
: >"$TEST_TMPDIR/not-url.dmg"
assert_command_fails_with "--audit-source-url must be an HTTP(S) URL" \
  "$ROOT_DIR/install-chatgpt-linux.sh" --audit-candidate \
  --dmg "$TEST_TMPDIR/not-url.dmg" --audit-source-url not-a-url
assert_file_not_exists "$ROOT_DIR/install-codex-linux.sh"

retry_attempts=0
retry_fail_twice() {
  retry_attempts=$((retry_attempts + 1))
  (( retry_attempts >= 3 ))
}
assert_ok retry_command 3 0 "transient test command" retry_fail_twice
assert_eq 3 "$retry_attempts"

retry_always_fails() {
  return 17
}
assert_fail retry_command 2 0 "permanent test command" retry_always_fails

assert_file_contains "$ROOT_DIR/install-chatgpt-linux.sh" \
  'install --no-audit --no-fund --ignore-scripts'
assert_file_contains "$ROOT_DIR/install-chatgpt-linux.sh" \
  '"$NODE_BIN" node_modules/electron/install.js'

if (( TEST_FAILURES > 0 )); then
  printf '%d test assertion(s) failed\n' "$TEST_FAILURES" >&2
  exit 1
fi

printf 'All installer function tests passed\n'
