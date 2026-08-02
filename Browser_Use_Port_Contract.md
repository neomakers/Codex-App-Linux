# Browser Use Port Contract

> **Historical evidence — not current instructions.** The observed `Codex.app` release, filenames, paths, and `main` status below are preserved for forensic comparison. For the current ChatGPT.app-only workflow and release truth, use [UPGRADING.md](UPGRADING.md) and [compatibility/current.json](compatibility/current.json).

Date: 2026-05-24

Branch baseline: `main`

Status: reverse-engineered, not yet ported on `main`.

## Purpose

This document records the actual Browser Use contract in the current Codex DMG before Linux patching. The goal is to avoid the previous pattern where a visible UI toggle was mistaken for a working port.

Browser Use is ported only when Codex can open or attach to the in-app browser, expose a Browser Use MCP tool to the model, route each tool call to the correct browser pane, and survive a desktop app restart without stale turn metadata.

## Current Main State

`main` does not currently ship Browser Use. It ships:

- Bash installer orchestration.
- `tools/patch-codex-linux.mjs` for Linux patching.
- Codex Mobile renderer gate patches.
- Stable Linux Electron launch flags.

The Browser Use menu, MCP server, native pipe, bundled plugins, and route/session logic are not yet ported on `main`.

## DMG Ground Truth

The current DMG contains Browser Use in multiple places. It is not contained entirely in `app.asar`.

Observed package version:

- Codex app: `26.513.20950`
- Build: `2816`
- Electron: `42.0.1`

Important ASAR assets:

- `.vite/build/main-*.js`
- `.vite/build/app-session-*.js`
- `webview/assets/use-in-app-browser-use-availability-*.js`
- `webview/assets/browser-use-settings-*.js`
- `webview/assets/browser-*.js`
- `webview/assets/thread-side-panel-browser-tab-state-*.js`
- `webview/assets/app-main-*.js`

Important non-ASAR resources:

- `Contents/Resources/node`
- `Contents/Resources/node_repl`
- `Contents/Resources/native/browser-use-peer-authorization.node`
- `Contents/Resources/plugins/openai-bundled/.agents/plugins/marketplace.json`
- `Contents/Resources/plugins/openai-bundled/plugins/browser/.codex-plugin/plugin.json`
- `Contents/Resources/plugins/openai-bundled/plugins/browser/scripts/browser-client.mjs`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/.codex-plugin/plugin.json`
- `Contents/Resources/plugins/openai-bundled/plugins/chrome/scripts/browser-client.mjs`

On macOS these binaries are Mach-O, so they cannot be reused directly on Linux. The Linux port must either replace them or provide compatible behavior through Linux-native components.

## Renderer Contract

The renderer has a Browser Use availability hook in `use-in-app-browser-use-availability-*.js`.

Observed gates:

- Platform support check returns true for `macOS` and `windows`.
- In-app Browser Use depends on feature name `browser_use`.
- External Browser Use depends on feature name `browser_use_external`.
- Browser pane availability, Statsig gates, config requirements, loading state, and WSL disable state all contribute to availability.

Observed desktop feature broadcast in `app-main-*.js`:

- `inAppBrowserUse`
- `inAppBrowserUseAllowed`
- `browserPane`
- `externalBrowserUse`
- `externalBrowserUseAllowed`
- `computerUse`

Linux patching may need to change renderer availability, but this is only the UI layer. It does not create a working Browser Use backend.

## Main-Process Contract

The main process has default desktop feature availability set to false for Browser Use:

- `browserPane: false`
- `inAppBrowserUse: false`
- `inAppBrowserUseAllowed: false`
- `externalBrowserUse: false`
- `externalBrowserUseAllowed: false`

When Browser Use is enabled, main process setup builds a `node_repl` MCP server configuration.

Observed runtime selection:

- `CODEX_CLI_PATH` can override Codex CLI path.
- `CODEX_BROWSER_USE_NODE_PATH` can override Node runtime path.
- `CODEX_NODE_REPL_PATH` can override `node_repl` path.
- `CODEX_ELECTRON_RESOURCES_PATH` can override packaged resources path.

Observed MCP server:

- server name: `node_repl`
- command: resolved `node_repl` runtime
- `startup_timeout_sec`: `120`

Observed environment for Browser Use:

- `NODE_REPL_NATIVE_PIPE_CONNECT_TIMEOUT_MS`
- `NODE_REPL_NODE_MODULE_DIRS`
- `NODE_REPL_NODE_PATH`
- `NODE_REPL_REQUEST_META`
- `NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S`
- `NODE_REPL_BROWSER_CLIENT_MARKETPLACE_NAME`
- `CODEX_HOME`

Important Linux implication:

The upstream main process expects a `node_repl` runtime. The current Linux installer does not copy or replace the DMG's `Contents/Resources/node_repl`. Because the DMG binary is macOS-only, a Linux-compatible replacement is required.

## Native Pipe And Route Contract

The in-app browser backend is route-bound. A tool call is not just "control whatever browser is visible".

Observed concepts in main-process code:

- window record
- conversation id
- turn id
- page snapshot
- guest webContents id
- Browser Use host
- browser route
- native pipe

Observed lifecycle methods:

- `recordPageSnapshot(...)`
- `registerThread(...)`
- `resolveBrowserRoute(...)`
- `canServeTurnForBrowserRoute(...)`
- `requireBrowserUseSession(...)`
- `getLiveWindowState`

Observed failure modes:

- missing `session_id`
- missing `turn_id`
- browser session does not belong to this in-app-browser pipe
- browser turn does not belong to this in-app-browser pipe
- no active browser pane
- stale or missing route after restart

Linux must preserve the route contract. Bypassing it globally can make a demo work but risks controlling the wrong browser pane or the wrong thread.

## Plugin Contract

The DMG bundles Browser and Chrome plugins under `Contents/Resources/plugins/openai-bundled`.

`browser` plugin:

- Controls the Codex in-app browser.
- Intended for local web targets, file URLs, and the current in-app browser tab.
- Exposes `browser-client.mjs`.

`chrome` plugin:

- Controls Chrome for remote URLs, authenticated pages, existing tabs, cookies, and extensions.
- Exposes a separate `browser-client.mjs`.
- Requires Chrome/native-host work that is separate from in-app Browser Use.

These plugins are part of the real feature surface. The Linux installer currently discards them. The port needs to decide whether to copy these plugin bundles as data and connect them to a Linux-compatible runtime, or to provide an explicit Linux replacement.

## Learning Branch Evidence

The learning branch proved that Browser Use can be made to work on Linux, but the implementation mixed valid findings with reactive fallbacks.

Useful evidence:

- `df90fe1 Enable Browser Use on Linux`
- `bf01621 Add Linux Browser Use node_repl shim`
- `aa7df0a Bridge Browser Use shim to native pipe`
- `301737c Expose Browser Use MCP tool on Linux`
- `b86a943 Auto-fill Browser Use turn metadata`
- `bd3d81f Fix Browser Use route registration after restart`

Debt to avoid blindly copying:

- Hard forcing every renderer gate without proving backend readiness.
- Synthetic `linux-browser-use-turn` route acceptance as a broad bypass.
- Multiple fallbacks for missing turn metadata before proving why metadata was missing.
- Large generated JavaScript embedded directly in the Bash installer.
- Treating Chrome, in-app Browser Use, and Browser plugin availability as the same surface.

The learning branch should be used as a primer, not as the final patch set.

## Linux Port Requirements

Minimum Linux-compatible Browser Use implementation:

1. Preserve or explicitly replace the Browser/Chrome plugin assets.
2. Provide a Linux `node_repl` command compatible with the MCP protocol expected by Codex.
3. Make `CODEX_NODE_REPL_PATH` point to that Linux `node_repl`.
4. Ensure `NODE_REPL_REQUEST_META` and per-turn `_meta` can supply `session_id` and `turn_id`.
5. Connect the Linux `node_repl` to the in-app browser native pipe.
6. Route browser commands only to the active thread/browser pane unless a narrower safe fallback is proven.
7. Start the backend when the browser pane/page snapshot exists.
8. Keep Browser Use available after app restart.
9. Report explicit errors when the backend, route, or pane is missing.

## Implementation Shape For Main

Keep `install-codex-linux.sh` as orchestration for now.

Move feature logic into files under `tools/`:

- `tools/patch-codex-linux.mjs` for minified app patches.
- `tools/node_repl-linux.mjs` for the Linux MCP bridge.

The installer should copy these files into the output directory rather than embedding hundreds of lines in a heredoc.

Expected generated files:

- `codex-linux/bin/node_repl-linux`
- `codex-linux/bin/node_repl-linux.mjs`
- `codex-linux/codex-linux-feature-manifest.json`

Expected launcher environment:

- `CODEX_NODE_REPL_PATH="$SCRIPT_DIR/bin/node_repl-linux"`

## Main Branch Implementation Slice

Current `main` now carries the first Browser Use implementation slice:

- `tools/patch-codex-linux.mjs` enables Browser Use renderer and main-process gates.
- `tools/patch-codex-linux.mjs` patches route metadata provider/export behavior based on the working learning-branch path.
- `tools/patch-codex-linux.mjs` generates a Linux `node_repl` MCP shim with:
  - `browser_use`
  - `js`
  - `js_reset`
- The generated launcher exports:
  - `CODEX_NODE_REPL_PATH`
  - `NODE_REPL_NODE_PATH`
  - `CODEX_BROWSER_USE_NODE_PATH`

This remains experimental until tested through a fresh install and a real Codex in-app browser turn. The patch engine validates against the current extracted DMG asset names and snippets, but runtime success requires the Electron app to create the Browser Use native pipe under `/tmp/codex-browser-use`.

## Acceptance Tests

Browser Use is accepted only when all of these pass:

1. Fresh install into a clean output directory.
2. Launch app.
3. Open in-app browser to `https://www.amazon.com/`.
4. Ask Codex to inspect the page.
5. Codex uses Browser Use instead of generic web search.
6. Codex can navigate to a search URL.
7. Codex can read active page state.
8. Restart the desktop app without reinstalling.
9. Reopen the same thread/browser pane.
10. Ask Codex to inspect the page again.
11. No `missing session_id`, `missing turn_id`, `No active Codex browser pane`, or `Browser turn does not belong to this IAB pipe` errors occur.

## Non-Goals For This Surface

Do not claim Chrome support from in-app Browser Use work. Chrome support is a separate surface involving the bundled `chrome` plugin, Chrome installation/discovery, native host setup, and extension/profile access. See `Chrome_Control_Port_Contract.md`.

Do not claim app snapshot parity from screenshot attachment. App snapshot is a separate surface with window enumeration, snapshot metadata, and context attachment behavior. See `App_Snapshot_Computer_Use_Port_Contract.md`.

Do not claim mobile pairing parity from Browser Use work. Mobile pairing depends on remote-control/device-auth surfaces.
