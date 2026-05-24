# Porting Surface Plan

Date: 2026-05-24

Branch baseline: `main`

Installer shape: Bash orchestration plus `tools/patch-codex-linux.mjs`.

## Current Main Surfaces

These are the surfaces present on `main` before new feature ports:

| Surface | Status | Evidence |
|---|---|---|
| DMG acquisition | present | Local DMG reuse plus OpenAI CDN fallback. |
| DMG extraction | present | Requires system `7z` / `7zz`. |
| ASAR extraction | present | Uses global `asar` or `npm exec @electron/asar`. |
| package synthesis | present | Inline Node block builds Linux `package.json` and filters unsupported deps. |
| Electron/native rebuild | present | `npm install` and `npx @electron/rebuild`. |
| macOS native stubs | present | Removes `sparkle.node`; writes `electron-liquid-glass` shim. |
| launcher | present | Generates `codex-linux.sh` with Linux graphics-stability flags. |
| desktop integration | present | Writes `.desktop` file and registers `codex://`. |
| build diagnostics | present | Writes `build-info.json`. |
| Codex Mobile UI gate | partial | Patch engine exposes mobile/remote UI gates only. |
| Browser Use | absent | Must be ported from first principles. |
| App snapshot | absent | Must be ported from first principles; screenshot-only is not parity. |
| remote-control daemon bridge | absent | Must be ported from first principles. |
| Linux device-key provider | absent | Required for real mobile pairing bridge. |
| tray/background mode | absent | Candidate feature, not current baseline. |

## Porting Method

For each surface:

1. Use the learning branch only as a primer.
2. Disassemble the current DMG and confirm the feature path independently.
3. Trace renderer UI, main-process IPC, native module calls, CLI calls, backend state, and config keys.
4. Write a feature contract before editing.
5. Patch only the minimal confirmed path in `tools/patch-codex-linux.mjs`.
6. Install into a clean output directory.
7. Launch, restart, and run the feature acceptance test.
8. Commit only after the acceptance test proves the real path.

## Non-Negotiable Rule

Do not claim a feature is ported because a renderer button appears. A feature is ported only when the underlying Linux substitute performs the same contract as the macOS path, or when the documentation explicitly names the gap as a limitation.

## Next Surface

Browser Use is the next candidate because the learning branch eventually produced live in-app browser control. The branch is still only a primer. The real source of truth must be the extracted current DMG.
