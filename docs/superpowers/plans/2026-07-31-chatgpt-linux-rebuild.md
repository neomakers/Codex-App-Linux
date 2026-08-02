# ChatGPT Linux Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Codex-branded legacy installer with a reliable ChatGPT Linux installer that accepts only the current `ChatGPT.app` DMG layout and completes without `sudo` on this Ubuntu workstation.

**Architecture:** A small executable Bash entry point delegates testable environment, download, payload-discovery, launcher, and desktop-entry functions to `lib/chatgpt-installer.sh`. Package synthesis is isolated in an importable Node module. The existing patch engine is retained for internal Codex feature surfaces but renamed and made ChatGPT-output-aware.

**Tech Stack:** Bash 5, Node.js 22.23.2 LTS portable fallback, Node built-in `node:test`, `@electron/asar` 4.2.1, Electron 42.3.0, `@electron/rebuild` 4.0.3, 7-Zip 23.01, npm.

## Global Constraints

- Only `ChatGPT.app` is supported; a `Codex.app`-only DMG must be rejected.
- Generated names are `chatgpt-linux/`, `chatgpt-linux.sh`, `chatgpt-linux.desktop`, and `ChatGPT Linux`.
- Internal `codex`, `CODEX_*`, `com.openai.codex`, and `codex://` interfaces remain unchanged.
- Node.js must be at least 22.12.0; portable fallback is pinned to 22.23.2.
- The current app-declared Electron runtime, 42.3.0, is preserved.
- Installation must not invoke `sudo`.
- `app.asar` and adjacent `app.asar.unpacked` are treated as one payload.
- Existing installed output is not replaced until staging passes Electron-native-module and bounded GUI validation.
- This workspace has no `.git` metadata, so commit steps are recorded as unavailable rather than simulated.

## File Structure

- Create `install-chatgpt-linux.sh`: thin CLI entry point and installation orchestration.
- Create `lib/chatgpt-installer.sh`: sourceable pure and side-effecting installer functions.
- Create `tools/generate-chatgpt-package.mjs`: importable package metadata generator and CLI.
- Move `tools/patch-codex-linux.mjs` to `tools/patch-chatgpt-linux.mjs`: current feature patch engine with renamed output metadata.
- Create `tests/installer-functions.test.sh`: dependency-free Bash regression suite.
- Create `tests/generate-chatgpt-package.test.mjs`: Node metadata regression suite.
- Create `tests/run-all.sh`: syntax and unit-test entry point.
- Remove `install-codex-linux.sh`: obsolete Codex-layout installer.
- Modify `.gitignore`: ignore ChatGPT DMG/output names.
- Modify `README.md`: document only the ChatGPT Linux flow.

---

### Task 1: Testable ChatGPT Payload and Version Functions

**Files:**
- Create: `lib/chatgpt-installer.sh`
- Create: `tests/installer-functions.test.sh`

**Interfaces:**
- Produces: `version_at_least ACTUAL REQUIRED`
- Produces: `normalize_linux_arch [UNAME_MACHINE]`
- Produces: `plist_value PLIST KEY`
- Produces: `discover_chatgpt_payload EXTRACTED_ROOT`, setting `CHATGPT_APP_ROOT`, `CHATGPT_PLIST`, `CHATGPT_RESOURCES`, `CHATGPT_ASAR`, and `CHATGPT_ASAR_UNPACKED`
- Produces: `validate_chatgpt_payload`, returning nonzero with an actionable message

- [ ] **Step 1: Write failing fixture tests**

Create a dependency-free harness that builds temporary `ChatGPT.app` and `Codex.app` layouts. The core assertions are:

```bash
assert_ok version_at_least 22.23.2 22.12.0
assert_fail version_at_least 18.19.1 22.12.0
assert_eq x64 "$(normalize_linux_arch x86_64)"
assert_eq arm64 "$(normalize_linux_arch aarch64)"
assert_fail normalize_linux_arch riscv64

make_chatgpt_fixture "$fixture"
assert_ok discover_chatgpt_payload "$fixture"
assert_eq "$fixture/ChatGPT Installer/ChatGPT.app" "$CHATGPT_APP_ROOT"
assert_ok validate_chatgpt_payload

rm -rf "$fixture/ChatGPT Installer/ChatGPT.app/Contents/Resources/app.asar.unpacked"
assert_fail_with "missing app.asar.unpacked" validate_chatgpt_payload

make_codex_fixture "$fixture"
assert_fail_with "unsupported DMG layout: ChatGPT.app not found" \
  discover_chatgpt_payload "$fixture"
```

The ChatGPT fixture's plist must contain:

```xml
<key>CFBundleIdentifier</key>
<string>com.openai.codex</string>
<key>CFBundleShortVersionString</key>
<string>26.727.40816</string>
<key>CFBundleVersion</key>
<string>6067</string>
```

- [ ] **Step 2: Verify RED**

Run:

```bash
bash tests/installer-functions.test.sh
```

Expected: failure because `lib/chatgpt-installer.sh` and its functions do not exist.

- [ ] **Step 3: Implement minimal functions**

Start the library with constants and error capture that remain safe when sourced:

```bash
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
```

Implement version comparison with numeric dot components, architecture mapping for `x86_64|amd64` and `aarch64|arm64`, plist value extraction, and strict discovery using `find ... -print -quit` rather than `find | head` under `pipefail`.

`discover_chatgpt_payload` must search only:

```bash
-path '*/ChatGPT.app/Contents/Info.plist'
```

It derives the resources directory from that plist and never searches for a generic first `app.asar`.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
bash tests/installer-functions.test.sh
bash -n lib/chatgpt-installer.sh tests/installer-functions.test.sh
```

Expected: all payload, bundle-ID, version, and architecture cases pass with no syntax errors.

- [ ] **Step 5: Record checkpoint**

Run `git rev-parse --is-inside-work-tree`. Expected: failure because this downloaded workspace has no Git metadata; no commit is created.

---

### Task 2: Resumable Download and Local Toolchain Resolution

**Files:**
- Modify: `lib/chatgpt-installer.sh`
- Modify: `tests/installer-functions.test.sh`

**Interfaces:**
- Consumes: `version_at_least`, `normalize_linux_arch`
- Produces: `remote_content_length URL`
- Produces: `file_size_matches FILE EXPECTED_BYTES`
- Produces: `download_resumable URL DESTINATION`
- Produces: `resolve_node WORK_DIR`, setting `NODE_BIN`, `NPM_BIN`, and prepending the selected runtime to `PATH`
- Produces: `resolve_7zip WORK_DIR`, setting `SEVEN_ZIP`
- Produces: `validate_dmg FILE EXPECTED_BYTES`

- [ ] **Step 1: Add failing tests for cached-file and tool selection**

Add assertions using fake executables placed first on `PATH`:

```bash
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
PATH="$fixture/old-bin:/usr/bin:/bin"
CHATGPT_NODE_DOWNLOAD_HOOK="$fixture/fake-node-bootstrap"
assert_ok resolve_node "$fixture/work"
assert_contains "$fixture/work/node-v22.23.2-linux-" "$NODE_BIN"

make_fake_7z "$fixture/bin/7z"
PATH="$fixture/bin:/usr/bin:/bin"
assert_ok resolve_7zip "$fixture/work"
assert_eq "$fixture/bin/7z" "$SEVEN_ZIP"
```

The fake download hook creates `bin/node` and `bin/npm` beneath the requested portable runtime path. The fake 7-Zip returns success for `t`.

- [ ] **Step 2: Verify RED**

Run:

```bash
bash tests/installer-functions.test.sh
```

Expected: failure at the first missing download/toolchain function.

- [ ] **Step 3: Implement resumable download**

`download_resumable` must:

1. use `wget --continue --tries=0 --timeout=30 --waitretry=2 -O "$destination" "$url"` when `wget` exists;
2. otherwise loop `curl -fL --retry 1 --connect-timeout 20 -C - -o "$destination" "$url"` until `file_size_matches` succeeds; and
3. fail if neither downloader exists.

`remote_content_length` parses the final numeric `Content-Length` from `curl -fsSIL` and returns an empty string when the server omits it. `validate_dmg` checks the expected size when supplied, then runs:

```bash
"$SEVEN_ZIP" t "$file"
```

- [ ] **Step 4: Implement portable Node 22.23.2**

Map `x64` and `arm64` to:

```text
https://nodejs.org/dist/v22.23.2/node-v22.23.2-linux-<arch>.tar.xz
```

Download into the work directory, extract with `tar -xJf`, set `NODE_BIN` and `NPM_BIN`, prepend the portable `bin` directory to `PATH`, and verify `node --version` satisfies 22.12.0.

- [ ] **Step 5: Implement non-root 7-Zip fallback**

First accept an existing `7z` or `7zz`. On Debian/Ubuntu with `apt-get` and `dpkg-deb`, execute inside `$WORK_DIR/7zip-package`:

```bash
apt-get download 7zip
dpkg-deb -x ./*.deb "$WORK_DIR/7zip-root"
```

Use `$WORK_DIR/7zip-root/usr/lib/7zip/7z` directly so its adjacent `7z.so` plugin resolves correctly. Other distributions fail with a package-manager-specific prerequisite message and never call `sudo`.

- [ ] **Step 6: Verify GREEN**

Run:

```bash
bash tests/installer-functions.test.sh
bash -n lib/chatgpt-installer.sh tests/installer-functions.test.sh
```

Expected: all tests pass, including Node 18 fallback and local 7-Zip resolution.

- [ ] **Step 7: Record checkpoint**

No commit is possible because `.git` is absent. Preserve the passing test output in the session handoff.

---

### Task 3: Current ChatGPT Package Metadata Generator

**Files:**
- Create: `tools/generate-chatgpt-package.mjs`
- Create: `tests/generate-chatgpt-package.test.mjs`

**Interfaces:**
- Produces: `buildLinuxPackage(sourcePackage, appVersion) -> object`
- CLI: `node tools/generate-chatgpt-package.mjs SOURCE_PACKAGE OUTPUT_PACKAGE APP_VERSION`

- [ ] **Step 1: Write the failing Node tests**

Use `node:test` with a representative current source package:

```js
import test from "node:test";
import assert from "node:assert/strict";
import { buildLinuxPackage } from "../tools/generate-chatgpt-package.mjs";

test("generates ChatGPT Linux metadata for Electron 42", () => {
  const result = buildLinuxPackage({
    main: ".vite/build/early-bootstrap.js",
    dependencies: {
      "better-sqlite3": "^12.9.0",
      "objc-js": "1.5.0",
      "app-server-types": "workspace:*",
      "browser-api": "file:../../../lib/browser-api",
      "browser-common": "link:../../../lib/browser-common",
      "ws": "^8.21.1"
    },
    devDependencies: { electron: "42.3.0" }
  }, "26.727.40816");

  assert.equal(result.name, "chatgpt-linux");
  assert.equal(result.productName, "ChatGPT Linux");
  assert.equal(result.version, "26.727.40816-linux");
  assert.equal(result.main, ".vite/build/early-bootstrap.js");
  assert.equal(result.devDependencies.electron, "42.3.0");
  assert.equal(result.devDependencies["@electron/rebuild"], "4.0.3");
  assert.deepEqual(result.dependencies, {
    "better-sqlite3": "^12.9.0",
    "ws": "^8.21.1"
  });
});
```

Add a CLI test that writes temporary input JSON, invokes the module, and parses the generated output.

- [ ] **Step 2: Verify RED**

Run:

```bash
node --test tests/generate-chatgpt-package.test.mjs
```

Expected: module-not-found failure for `tools/generate-chatgpt-package.mjs`.

- [ ] **Step 3: Implement metadata synthesis**

Export `buildLinuxPackage`. Filter:

- dependency names `app-server-types`, `browser-api`, `browser-backend-common`, `browser-common`, `commands`, `external-agent-migration`, `protocol`, `shared-node`, `electron-liquid-glass`, and `objc-js`;
- every dependency value starting with `file:`, `link:`, or `workspace:`.

Return:

```js
{
  name: "chatgpt-linux",
  productName: "ChatGPT Linux",
  version: `${appVersion}-linux`,
  description: "ChatGPT for Linux (unofficial port)",
  main: sourcePackage.main,
  scripts: {
    start: "electron .",
    "start:debug": "electron . --enable-logging"
  },
  dependencies,
  devDependencies: {
    electron: sourcePackage.devDependencies.electron,
    "@electron/rebuild": "4.0.3"
  }
}
```

Reject a missing main entry or missing exact Electron version rather than silently choosing an older runtime.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
node --test tests/generate-chatgpt-package.test.mjs
```

Expected: all metadata API and CLI tests pass.

- [ ] **Step 5: Record checkpoint**

No commit is possible because `.git` is absent.

---

### Task 4: ChatGPT Launcher and Desktop Entry Generation

**Files:**
- Modify: `lib/chatgpt-installer.sh`
- Modify: `tests/installer-functions.test.sh`

**Interfaces:**
- Produces: `write_chatgpt_launcher OUTPUT_DIR`
- Produces: `write_desktop_entry OUTPUT_DIR DESKTOP_FILE`
- Launcher consumes: `CODEX_CLI_PATH`, `CODEX_BROWSER_USE_NODE_PATH`, `CODEX_NODE_REPL_PATH`, `CODEX_LINUX_GRAPHICS_MODE`, `CODEX_LINUX_REMOTE_CONTROL`

- [ ] **Step 1: Add failing naming and protocol tests**

Generate into a fixture and assert:

```bash
assert_ok write_chatgpt_launcher "$fixture/chatgpt-linux"
assert_file "$fixture/chatgpt-linux/chatgpt-linux.sh"
assert_executable "$fixture/chatgpt-linux/chatgpt-linux.sh"
assert_file_contains "$fixture/chatgpt-linux/chatgpt-linux.sh" \
  'export CODEX_CLI_PATH='
assert_file_contains "$fixture/chatgpt-linux/chatgpt-linux.sh" \
  'exec ./node_modules/.bin/electron'

assert_ok write_desktop_entry \
  "$fixture/chatgpt-linux" "$fixture/chatgpt-linux.desktop"
assert_file_contains "$fixture/chatgpt-linux.desktop" 'Name=ChatGPT Linux'
assert_file_contains "$fixture/chatgpt-linux.desktop" \
  'Exec='"$fixture"'/chatgpt-linux/chatgpt-linux.sh %u'
assert_file_contains "$fixture/chatgpt-linux.desktop" \
  'MimeType=x-scheme-handler/codex;'
assert_file_not_contains "$fixture/chatgpt-linux.desktop" 'codex-linux'
```

- [ ] **Step 2: Verify RED**

Run `bash tests/installer-functions.test.sh`.

Expected: failure because the generator functions are absent.

- [ ] **Step 3: Implement launcher**

Port the current graphics, CLI fallback, Browser Use, and remote-control behavior to `chatgpt-linux.sh`. User-visible config/log storage becomes `${XDG_CONFIG_HOME:-$HOME/.config}/chatgpt-linux`. Required internal environment names and the managed Codex CLI shim remain unchanged.

The final process is:

```bash
exec ./node_modules/.bin/electron . --no-sandbox "${linux_graphics_flags[@]}" "$@"
```

- [ ] **Step 4: Implement desktop entry**

Generate:

```desktop
[Desktop Entry]
Name=ChatGPT Linux
Comment=Run ChatGPT desktop on Linux (unofficial)
Exec=/absolute/output/chatgpt-linux.sh %u
Terminal=false
Type=Application
Categories=Development;
MimeType=x-scheme-handler/codex;
```

Do not call `xdg-mime` from the pure generator; registration belongs to the main installer.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
bash tests/installer-functions.test.sh
bash -n lib/chatgpt-installer.sh
```

Expected: generated launcher and desktop naming tests pass while internal Codex identifiers remain present.

- [ ] **Step 6: Record checkpoint**

No commit is possible because `.git` is absent.

---

### Task 5: Rename and Validate the Feature Patch Engine

**Files:**
- Move: `tools/patch-codex-linux.mjs` to `tools/patch-chatgpt-linux.mjs`
- Create: `tests/patch-engine-metadata.test.mjs`

**Interfaces:**
- CLI: `node tools/patch-chatgpt-linux.mjs CHATGPT_LINUX_OUTPUT_DIR`
- Produces: `chatgpt-linux-feature-manifest.json`

- [ ] **Step 1: Write failing source/manifest tests**

The test reads the patch engine source and asserts:

```js
assert.match(source, /Usage: patch-chatgpt-linux\.mjs <chatgpt-linux-output-dir>/);
assert.match(source, /patchEngine: "tools\/patch-chatgpt-linux\.mjs"/);
assert.match(source, /chatgpt-linux-feature-manifest\.json/);
assert.doesNotMatch(source, /codex-linux-feature-manifest\.json/);
```

Also execute the CLI without arguments and assert it fails with the new usage line.

- [ ] **Step 2: Verify RED**

Run:

```bash
node --test tests/patch-engine-metadata.test.mjs
```

Expected: failure because the renamed engine does not exist.

- [ ] **Step 3: Move and minimally rebrand the patch engine**

Rename the file, its usage string, its manifest `patchEngine`, its manifest filename, and user-visible `.config/codex-linux` storage to `.config/chatgpt-linux`. Preserve internal feature names, Codex Mobile strings, `CODEX_*` variables, browser socket names, and Chrome native-host contract identifiers.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
node --test tests/patch-engine-metadata.test.mjs
node --check tools/patch-chatgpt-linux.mjs
```

Expected: all metadata tests and syntax checks pass.

- [ ] **Step 5: Record checkpoint**

No commit is possible because `.git` is absent.

---

### Task 6: Assemble the ChatGPT-Only Installer

**Files:**
- Create: `install-chatgpt-linux.sh`
- Remove: `install-codex-linux.sh`
- Create: `tests/run-all.sh`
- Modify: `tests/installer-functions.test.sh`

**Interfaces:**
- CLI: `./install-chatgpt-linux.sh [--dmg PATH] [--output PATH] [--skip-cli-install]`
- Consumes all library functions and both Node tools.
- Produces the staged and then finalized `chatgpt-linux/` application.

- [ ] **Step 1: Add failing CLI tests**

Test:

```bash
assert_command_contains "./install-chatgpt-linux.sh --help" \
  "ChatGPT Linux Installer"
assert_command_contains "./install-chatgpt-linux.sh --help" \
  "--dmg <path>"
assert_command_fails_with "./install-chatgpt-linux.sh --unknown" \
  "Unknown option: --unknown"
assert_file_not_exists "install-codex-linux.sh"
```

Add `tests/run-all.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail
bash -n install-chatgpt-linux.sh lib/chatgpt-installer.sh tests/*.sh
bash tests/installer-functions.test.sh
node --test tests/*.test.mjs
```

- [ ] **Step 2: Verify RED**

Run `bash tests/run-all.sh`.

Expected: failure because `install-chatgpt-linux.sh` does not exist and the obsolete file remains.

- [ ] **Step 3: Implement argument and prerequisite flow**

The main sequence is:

```text
parse arguments
create work directory and cleanup trap
resolve Node 22
resolve 7-Zip
resolve or download ChatGPT-latest.dmg
validate exact size when available
test DMG
extract complete DMG
discover and validate ChatGPT.app
extract app.asar with adjacent app.asar.unpacked
validate .vite, webview, and package.json
generate Linux package metadata
prepare staging output
run patch engine
install dependencies
rebuild native modules
write launcher and build-info
load every required native module through Electron-as-Node from staging
run bounded GUI smoke from staging with remote control disabled
atomically replace output
retain the timestamped previous output for rollback
write/register desktop entry
print completion
```

Use `npm exec --yes @electron/asar@4.2.1 -- extract`. Run npm and rebuild through the selected Node 22 toolchain. `npm install` and `npm exec --yes @electron/rebuild@4.0.3` run inside the staging output.

- [ ] **Step 4: Implement staging and atomic replacement**

Build in:

```bash
STAGING_DIR="${OUTPUT_DIR}.staging.$$"
```

Before moving the existing output, validate the five required native modules through Electron-as-Node and run the bounded GUI smoke from staging. On success, move an existing generated output to a timestamped `${OUTPUT_DIR}.previous.*`, move staging into place, and retain that previous output for rollback. If promotion fails, restore it before returning failure. Generate/register desktop integration only after promotion.

- [ ] **Step 5: Implement build metadata and registration**

`build-info.json` records:

- installer version;
- ChatGPT app version/build;
- Electron runtime;
- main entry;
- DMG path and SHA-256;
- selected Node path/version;
- Codex CLI path/version.

Write `chatgpt-linux.desktop` to `${XDG_DATA_HOME:-$HOME/.local/share}/applications/`, run `xdg-mime default chatgpt-linux.desktop x-scheme-handler/codex`, and update the desktop database when available.

- [ ] **Step 6: Remove obsolete installer and verify GREEN**

Remove `install-codex-linux.sh`, make new scripts executable, then run:

```bash
bash tests/run-all.sh
```

Expected: all Bash syntax, CLI, library, metadata, and patch-engine tests pass.

- [ ] **Step 7: Record checkpoint**

No commit is possible because `.git` is absent.

---

### Task 7: Rename Project Documentation and Ignored Outputs

**Files:**
- Modify: `README.md`
- Modify: `.gitignore`

**Interfaces:**
- Documents the exact CLI and generated names from Task 6.

- [ ] **Step 1: Add a failing branding check**

Extend `tests/run-all.sh`:

```bash
rg -n 'install-codex-linux\.sh|codex-linux/|codex-linux\.desktop' \
  README.md .gitignore && {
    printf 'obsolete Codex Linux branding remains\n' >&2
    exit 1
  }
rg -q 'install-chatgpt-linux\.sh' README.md
rg -q 'chatgpt-linux/' README.md
rg -q 'ChatGPT-latest\\.dmg' .gitignore
```

- [ ] **Step 2: Verify RED**

Run `bash tests/run-all.sh`.

Expected: failure listing obsolete names in `README.md` and `.gitignore`.

- [ ] **Step 3: Rewrite current usage documentation**

Describe:

- current `ChatGPT.app`-only support;
- Node 22 and local bootstrap behavior;
- resumable DMG download;
- `./install-chatgpt-linux.sh`;
- `chatgpt-linux/chatgpt-linux.sh`;
- ChatGPT Linux desktop entry;
- internal Codex CLI and `codex://` requirements;
- feature-patch limitations.

Remove claims that the installer supports the older `Codex.app` DMG layout.

- [ ] **Step 4: Update ignored names and verify GREEN**

Ignore:

```gitignore
ChatGPT-latest.dmg
*.dmg
chatgpt-linux/
chatgpt-linux.staging.*
chatgpt-linux.previous.*
```

Run `bash tests/run-all.sh`. Expected: all checks pass.

- [ ] **Step 5: Record checkpoint**

No commit is possible because `.git` is absent.

---

### Task 8: Real DMG End-to-End Build

**Files:**
- Rename: `Codex-latest.dmg` to `ChatGPT-latest.dmg`
- Generate: `chatgpt-linux/`
- Generate: `${XDG_DATA_HOME:-$HOME/.local/share}/applications/chatgpt-linux.desktop`
- Modify tests or implementation only when a reproduced integration failure requires a regression test

**Interfaces:**
- Consumes the validated 609,303,023-byte DMG already present.
- Produces the final installed application and desktop registration.

- [ ] **Step 1: Preserve the completed download under its new name**

Verify:

```bash
stat -c '%s' Codex-latest.dmg
```

Expected: `609303023`.

Rename:

```bash
mv Codex-latest.dmg ChatGPT-latest.dmg
```

Verify the file still has the same size and passes `7z t`.

- [ ] **Step 2: Run the rebuilt installer**

Run:

```bash
./install-chatgpt-linux.sh
```

Capture the complete output in `/tmp/chatgpt-linux-install.log` while preserving the installer exit code.

- [ ] **Step 3: Handle any integration failure test-first**

For each failure:

1. preserve the exact error and failing boundary;
2. add the smallest fixture regression to the relevant test file;
3. run it and observe the expected failure;
4. make one focused implementation change;
5. rerun the targeted test and `bash tests/run-all.sh`; and
6. resume the installer.

Do not combine unrelated build fixes.

- [ ] **Step 4: Validate generated metadata**

Run:

```bash
node -e '
const p=require("./chatgpt-linux/package.json");
if (p.name!=="chatgpt-linux") throw Error("wrong package name");
if (p.productName!=="ChatGPT Linux") throw Error("wrong product name");
if (p.main!==".vite/build/early-bootstrap.js") throw Error("wrong main");
if (p.devDependencies.electron!=="42.3.0") throw Error("wrong Electron");
'
node -e '
const b=require("./chatgpt-linux/build-info.json");
if (b.nodeVersion<"v22.12.0") throw Error("Node too old");
'
test -x chatgpt-linux/chatgpt-linux.sh
test -f chatgpt-linux/chatgpt-linux-feature-manifest.json
```

- [ ] **Step 5: Confirm the installer's pre-promotion native gate**

The installer must already have used Electron's Node ABI to require each installed native module needed at startup before promotion. Recheck the promoted copy:

```bash
cd chatgpt-linux
./node_modules/.bin/electron -e '
for (const name of ["@parcel/watcher", "bufferutil", "utf-8-validate", "better-sqlite3", "node-pty"]) {
  require(name);
  console.log(`loaded ${name}`);
}
'
```

Expected: both modules load without ABI or shared-library errors.

- [ ] **Step 6: Smoke-test the launcher**

The installer runs this bounded smoke from staging with remote control disabled before promotion. Recheck the promoted launcher:

```bash
CODEX_LINUX_REMOTE_CONTROL=0 \
timeout 20s ./chatgpt-linux/chatgpt-linux.sh --enable-logging
```

Accept timeout status 124 only when logs show Electron stayed running without an uncaught exception. Any immediate nonzero exit is a failure.

- [ ] **Step 7: Verify desktop integration**

Run:

```bash
desktop_file="${XDG_DATA_HOME:-$HOME/.local/share}/applications/chatgpt-linux.desktop"
test -f "$desktop_file"
rg -q '^Name=ChatGPT Linux$' "$desktop_file"
rg -q '/chatgpt-linux/chatgpt-linux.sh %u$' "$desktop_file"
test "$(xdg-mime query default x-scheme-handler/codex)" = \
  "chatgpt-linux.desktop"
```

Expected: the file and protocol registration both match.

- [ ] **Step 8: Run final regression suite**

Run:

```bash
bash tests/run-all.sh
```

Expected: every test passes after the end-to-end build.

- [ ] **Step 9: Record final checkpoint**

No commit is possible because `.git` is absent. Report exact test commands, installer result, launcher result, generated paths, and any optional feature patches that were skipped.
