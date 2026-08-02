# Chrome Control Port Contract

> **Historical evidence — not current instructions.** The observed `Codex.app` release, filenames, paths, and `main` status below are preserved for forensic comparison. For the current ChatGPT.app-only workflow and release truth, use [UPGRADING.md](UPGRADING.md) and [compatibility/current.json](compatibility/current.json).

Date: 2026-05-24

Last forensic update: 2026-05-25

Branch baseline: `main`

Status: experimental Linux host implementation ported on `main`; runtime validation still required.

## Purpose

This document records the macOS Chrome Control contract before Linux patching. Chrome Control is separate from in-app Browser Use and separate from generic Computer Use.

Chrome Control is ported only when Codex can connect to the user's Chrome profile through the Codex Chrome Extension/native host path, list or claim tabs, read DOM/screenshot state, interact with pages, and clean up tabs according to the plugin contract.

Linux must replicate the same upstream contract first: Google Chrome plus the Codex Chrome Extension plus the native messaging host. Generic Chromium-family browser support is not part of the first port.

## Current Main State

`main` now experimentally ports the Chrome Control surface by installing:

- bundled Chrome plugin assets
- Codex Chrome Extension native messaging host
- generated Linux extension-host script
- Chrome backend metadata for Browser Use
- plugin setup/check scripts in the installed output

## DMG Ground Truth

The DMG bundles Chrome as a plugin:

- `Contents/Resources/plugins/openai-bundled/plugins/chrome/.codex-plugin/plugin.json`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/skills/chrome/SKILL.md`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/browser-client.mjs`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/installManifest.mjs`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/check-extension-installed.js`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/check-native-host-manifest.js`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/chrome-is-running.js`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/installed-browsers.js`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/open-chrome-window.js`

The plugin manifest says Chrome automation is for:

- remote URLs
- authenticated/profile-dependent pages
- existing Chrome tabs
- cookies
- extensions
- Codex Chrome Extension setup

This means Chrome Control is intended for the user's real browser state, not the app's in-app browser pane.

The extracted DMG contract is Google Chrome-specific:

- plugin display name: `Chrome`
- macOS app bundle id: `com.google.Chrome`
- Windows executable: `chrome.exe`
- Linux helper launcher command: `google-chrome`
- default Linux profile root in helper code: `~/.config/google-chrome`
- default Linux native messaging manifest root in installer code: `~/.config/google-chrome/NativeMessagingHosts`

Chromium, Brave, Edge, Vivaldi, Flatpak/Snap browser profiles, and other Chromium-family variants are outside the first Linux parity target.

## Native Host Ground Truth

The Chrome plugin uses a native messaging host:

- extension id: `hehggadaopoacecdllhhajmbjkdcmajg`
- native host name: `com.openai.codexextension`

`scripts/installManifest.mjs` has Linux-aware manifest paths:

- macOS: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts`
- Linux: `~/.config/google-chrome/NativeMessagingHosts`
- Windows: registry plus `%LOCALAPPDATA%`

But the bundled host binary path must exist:

```text
extension-host/<platform>/<arch>/extension-host
```

The extracted DMG currently ships:

```text
extension-host/macos/arm64/extension-host
```

It does not ship:

```text
extension-host/linux/x64/extension-host
extension-host/linux/arm64/extension-host
```

Therefore Linux Chrome Control cannot be completed by only copying the plugin and writing the manifest. The missing Linux native host is a real parity blocker.

## 2026-05-25 Forensic Probe Findings

The Chrome feature is an external browser-control surface. It is not the in-app browser and it is not App Snapshot.

Confirmed artifacts:

- Chrome plugin id: `chrome`
- Chrome extension id: `hehggadaopoacecdllhhajmbjkdcmajg`
- native messaging host name: `com.openai.codexextension`
- macOS host binary: `extension-host/macos/arm64/extension-host`
- expected Linux host paths:
  - `extension-host/linux/x64/extension-host`
  - `extension-host/linux/arm64/extension-host`
- Browser Use socket family: `/tmp/codex-browser-use`

The macOS `extension-host` binary is a Rust native host/router. Strings and bundled client code show these components:

- Chrome native messaging transport over stdio.
- Unix socket transport for Codex Browser Use clients.
- RPC routing between extension-side messages and Codex-side Browser Use messages.
- client registration and removal.
- session/turn lifecycle messages such as `turnEnded`, `session_id`, and `turn_id`.
- macOS peer/code-identity checks around socket clients.

The plugin's `browser-client.mjs` already understands these backend concepts:

- `extension`
- `iab`
- `cdp`

It maps backend type `extension` to user-facing browser id `chrome`. That means Linux does not need a new high-level Browser Use API for Chrome. It needs the missing lower-level transport host and the Linux helper patches that let the existing plugin install and verify it.

## Host Protocol Shape

The observed architecture is:

```text
Codex Browser Use runtime
        |
        | length-prefixed JSON over Unix socket
        v
/tmp/codex-browser-use/* socket
        |
        v
extension-host
        |
        | Chrome Native Messaging stdio frames
        v
Codex Chrome Extension
        |
        v
Google Chrome tabs/profile/session
```

The Codex-side socket framing is length-prefixed JSON. The Chrome native messaging side is also length-prefixed JSON by Chrome's native messaging contract. Message bodies are JSON-RPC-like and include fields such as `id`, `method`, `params`, `result`, `error`, `session_id`, and `turn_id`.

The host is not optional. Without it, the renderer can show Chrome UI, helper scripts can detect Chrome, and a manifest file can be written, but Codex cannot list, claim, inspect, or control Chrome tabs.

## Script Support Matrix

Observed helper script state:

| Script | Linux state | Notes |
|---|---|---|
| `installManifest.mjs` | partially supports Linux | Writes Linux manifest path but fails if Linux `extension-host` binary is missing. |
| `installed-browsers.js` | supports Linux | Detects Chrome/Chromium-style installs. |
| `open-chrome-window.js` | supports Linux | Launches `google-chrome` with profile/user-data arguments. |
| `check-extension-installed.js` | supports Linux | Reads Linux Chrome profile roots. |
| `chrome-is-running.js` | partial Linux support | Falls back to `chrome`; likely misses `google-chrome`, `google-chrome-stable`, and Chromium variants. |
| `check-native-host-manifest.js` | does not support Linux | Throws unsupported platform even though `installManifest.mjs` can write Linux manifests. |

## Browser Client Contract

Chrome plugin `browser-client.mjs` exposes Browser Use-style browser APIs for the `extension` backend.

Observed backend concepts:

- `extension`
- `iab`
- `cdp`
- `browser_id`
- `x-codex-browser-use-available-backends`
- `browser.user.openTabs()`
- `browser.user.claimTab(tab)`
- `browser.tabs.finalize({ keep })`

Chrome Control depends on the Browser Use runtime and `node_repl` style MCP execution. It is not only a Chrome installer problem.

Important Browser Use methods observed in the bundled runtime:

- `ping`
- `getInfo`
- `getTabs`
- `getUserTabs`
- `getUserHistory`
- `claimUserTab`
- `createTab`
- `attach`
- `attachTarget`
- `detach`
- `detachTarget`
- `executeCdp`
- `executeUnhandledCommand`
- `moveMouse`
- `finalizeTabs`
- `nameSession`

## Mac Lifecycle Model

Current inferred lifecycle:

1. Chrome plugin is visible when external Browser Use / Computer Use availability gates pass.
2. User enables or invokes Chrome access.
3. Codex checks Chrome install/running/profile state.
4. Codex Chrome Extension communicates with native host `com.openai.codexextension`.
5. Native host connects extension/browser state to Codex Browser Use runtime.
6. `browser-client.mjs` selects backend `extension`.
7. Agent lists tabs, claims a tab, interacts, reads DOM/screenshot, and finalizes tabs.

## Linux Parity Requirements

Minimum Linux-compatible Chrome Control implementation:

1. Copy Chrome plugin assets into installed output.
2. Provide Linux `extension-host` binaries for supported architectures.
3. Make `installManifest.mjs` install a correct Linux native messaging manifest.
4. Patch or replace `check-native-host-manifest.js` to support Linux.
5. Ensure `chrome-is-running.js` detects real Linux Google Chrome process names.
6. Ensure Browser Use runtime exposes the `extension` backend.
7. Verify the Codex Chrome Extension can connect to the Linux native host.
8. Keep the plugin's safety and tab-finalization contract.

First-release Linux scope:

- Supported browser: Google Chrome.
- Supported profile root: `~/.config/google-chrome`, plus existing override env vars already used by upstream helper scripts.
- Supported native manifest root: `~/.config/google-chrome/NativeMessagingHosts`.
- Optional command alias: `google-chrome-stable`, only if it is the local Google Chrome command.
- Unsupported until separately implemented and tested: Chromium, Chrome Beta/Dev/Canary, Brave, Edge, Vivaldi, Flatpak/Snap browser profile sandboxes.

## Linux Implementation Decision Gate

Do not patch renderer availability until one of these host paths exists and passes smoke tests:

1. Source or build the real upstream Linux `extension-host` for `linux/x64` and `linux/arm64`.
2. Implement a compatible Linux host in the current repo shape, most likely as a Node/MJS executable, after capturing the extension-host message schema.

The current project shape is Bash orchestration plus MJS patching. A Node/MJS compatibility host is acceptable only if it is protocol-compatible and testable. A fake manifest pointing at a missing binary or the macOS Mach-O binary is not acceptable.

Security requirement: the Linux host must create owner-only socket paths and must not expose a world-writable control surface. The macOS host appears to rely on platform peer/code-identity checks. Linux needs an equivalent practical boundary: per-user socket directory, restrictive permissions, and no cross-user socket access.

## Compatible Linux Host Plan

The project should implement the missing host rather than rewriting the whole installer. That keeps the port shape aligned with the rest of this repository:

- Bash orchestrates extraction, dependency install, and launcher generation.
- `tools/patch-codex-linux.mjs` patches upstream JS and emits Linux helper files.
- A generated Chrome host replaces only the missing native `extension-host/linux/<arch>/extension-host` boundary.

The compatible host must provide:

1. **Chrome Native Messaging server side**
   - read 4-byte native-message length prefixes from stdin;
   - parse JSON payloads from the Codex Chrome Extension;
   - write 4-byte length-prefixed JSON responses/events to stdout;
   - never write logs to stdout, only stderr or a file, because stdout is protocol traffic.
2. **Codex Browser Use socket side**
   - create `/tmp/codex-browser-use` if needed;
   - bind an owner-only Unix socket path under that directory;
   - remove stale sockets on startup;
   - accept Codex Browser Use clients;
   - read/write the same 4-byte length-prefixed JSON framing used by `browser-client.mjs`.
3. **RPC router**
   - route Codex client requests to the Chrome extension;
   - route extension responses/events back to the requesting Codex client;
   - track pending request ids;
   - register and remove client writers;
   - handle extension disconnect and client disconnect without leaving stale pending requests.
4. **Turn/session lifecycle**
   - preserve `session_id` and `turn_id` fields;
   - forward `turnEnded`/`native-turn-ended` style messages if the extension expects them;
   - avoid reusing stale turn metadata across unrelated sessions.
5. **Security and isolation**
   - create socket directories and files with owner-only permissions;
   - reject sockets not owned by the current user where Linux APIs expose peer credentials;
   - never make `/tmp/codex-browser-use` a world-controllable command surface.

Implementation should begin as a generated Node executable script because Node is already required by this installer and the bundled Browser Use client is JS. This does not preclude a later native binary, but it avoids another toolchain migration while the protocol is still being validated.

The host is accepted only if it can support this minimum round trip:

```text
browser-client.mjs -> socket -> linux extension host -> Chrome extension -> real Chrome tab
```

If that round trip is not proven, Chrome Control remains unshipped even if setup UI appears.

## Implementation Recipe For Main

Do not start by only enabling the Chrome settings UI. The order should be:

1. Preserve/copy the bundled Chrome plugin into the Linux output.
2. Identify whether a Linux extension-host implementation exists in another upstream package or must be written.
3. Emit a compatible Linux `extension-host` at `extension-host/linux/<arch>/extension-host`.
4. Patch `installManifest.mjs` only if needed so the generated host path is selected and executable.
5. Patch `check-native-host-manifest.js` for Linux manifest validation.
6. Patch `chrome-is-running.js` for Linux process names.
7. Patch `open-chrome-window.js` only enough to find Google Chrome reliably on Linux. Prefer `google-chrome`; optionally accept `google-chrome-stable` if it is the installed command for the same Google Chrome product. Do not broaden to Chromium-family browsers in the first port.
8. Install the native messaging manifest only when the Linux host is executable.
9. Connect Chrome backend metadata into the Linux `node_repl` Browser Use runtime by advertising `chrome` only when the host is installed.
10. Only then patch renderer settings availability.
11. Test with Chrome installed and then with Chrome missing.

## Acceptance Tests

Chrome Control is accepted only when all of these pass:

1. Fresh install into a clean output directory.
2. Chrome installed on Linux.
3. Codex Chrome Extension installed and enabled.
4. Native host manifest exists at `~/.config/google-chrome/NativeMessagingHosts/com.openai.codexextension.json`.
5. Manifest `path` points to an executable Linux `extension-host`.
6. `check-native-host-manifest.js --json` reports correct on Linux.
7. Codex can list open Chrome tabs.
8. Codex can claim a selected tab.
9. Codex can read DOM/screenshot state.
10. Codex can perform a harmless navigation/click after user request.
11. `browser.tabs.finalize({ keep })` closes or releases tabs correctly.

## Known Gaps

- Linux `extension-host` binary is missing from the DMG.
- Linux manifest checker is missing.
- Need capture real extension-host request/response payloads before writing a compatibility host.
- Need verify whether the public Codex Chrome Extension is installed through Web Store, bundled unpacked extension, or a first-run setup link in the current app flow.
- Chromium-family browser support is intentionally out of scope for the first Linux host. The upstream DMG contract is Chrome.
- Need decide whether this release ships Chrome as absent/coming-soon or starts the host implementation now.
