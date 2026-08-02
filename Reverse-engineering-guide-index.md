# Reverse Engineering Guide Index

> **Historical evidence — not current instructions.** The observed `Codex.app` release, filenames, paths, and `main` status below are preserved for forensic comparison. For the current ChatGPT.app-only workflow and release truth, use [UPGRADING.md](UPGRADING.md) and [compatibility/current.json](compatibility/current.json).

Date: 2026-05-25

This index preserves the former feature-porting map. `Reverse-engineering-guide.md` explains the historical base DMG-to-Linux conversion. The feature contracts below retain evidence about individual Codex app surfaces, what the macOS app did, and the Linux replacements that were investigated.

## Rule For This Repo

A feature is not ported because the button appears. A feature is ported only when the Linux implementation satisfies the same runtime contract as the macOS path, or the documented limitation explicitly says what parity is missing.

## Current Feature Contracts

| Surface | Contract | Current `main` status | Ground truth summary |
|---|---|---|---|
| Browser Use, in-app browser | `Browser_Use_Port_Contract.md` | Experimental Linux port on `main` | Requires renderer availability, main-process feature flags, `node_repl`, native-pipe routing, per-turn browser route metadata, and bundled browser plugin assets. |
| Chrome Control | `Chrome_Control_Port_Contract.md` | Documented, not ported on `main` | Requires the bundled Chrome plugin, Codex Chrome Extension, native messaging host manifest, Linux extension-host binary, and Browser Use backend selection for `extension`. |
| App Snapshot / Computer Use | `App_Snapshot_Computer_Use_Port_Contract.md` | Experimental screenshot-context slice on `main`; full parity not ported | App Snapshot is part of Computer Use. macOS uses ScreenCaptureKit, Accessibility, WindowServer state, app approvals, and a Computer Use MCP server. Screenshot-only attachment is useful context but not parity. |
| Codex Mobile / remote pairing | pending feature contract | Experimental UI/bridge port on `main`; behavior is account-sensitive | Needs a separate forensic pass for device auth, desktop approval, account/backend state, local config, remote daemon presence, and online/offline heartbeats. |

## Required Workflow Per Surface

1. Extract current DMG and app ASAR.
2. Identify renderer entry points: routes, buttons, settings pages, feature gates, and composer integration.
3. Identify main-process IPC: message names, handlers, environment variables, feature defaults, and app-server calls.
4. Identify plugins and MCP servers: `plugin.json`, `.mcp.json`, skills, scripts, native binaries, and marketplace visibility.
5. Identify native dependencies: Mach-O binaries, macOS frameworks, private APIs, permissions, launch helpers, and app bundle assets.
6. Write or update the feature contract with ground truth and open assumptions.
7. Design the Linux replacement against that contract.
8. Patch only the confirmed path.
9. Test fresh install, restart-without-reinstall, and failure modes.
10. Commit only after the acceptance test matches the contract.

## Evidence Sources

The current forensic baseline used these local extraction paths:

- `/tmp/codex-dmg-re/extracted/Codex.app`
- `/tmp/codex-dmg-re/app`
- `/tmp/codex-dmg-re/extracted/Codex.app/Contents/Resources/plugins/openai-bundled/plugins`

Observed app version:

- Codex app: `26.513.20950`
- Build: `2816`
- Electron: `42.0.1`

If a new DMG is used, this index and every feature contract must be revalidated. Minified asset filenames and feature gates can change between releases.

## Open High-Risk Areas

- Mobile pairing/remote device online state is not yet a first-principles contract.
- App Snapshot has renderer state plumbing as `nativeAppContexts`, but the current extracted DMG sets the upstream plus-menu native-app action slot to `null`. The current Linux patch adds screenshot-context only. Do not confuse that release slice with full Computer Use parity.
- Chrome control has Linux-aware helper scripts, but the DMG does not ship a Linux `extension-host` binary. That is a real implementation gap, not a missing flag.
- Computer Use parity requires a Linux desktop automation backend. On Linux this will likely differ between X11, Wayland, GNOME/KDE, and sandboxed portal environments.
