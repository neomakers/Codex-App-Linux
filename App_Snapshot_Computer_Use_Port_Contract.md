# App Snapshot / Computer Use Port Contract

Date: 2026-05-24

Branch baseline: `main`

Status: reverse-engineered first pass; experimental screenshot-context slice ported on `main`; full parity not ported.

## Purpose

This document records the actual macOS contract behind App Snapshot and Computer Use before Linux patching. The goal is to prevent treating a pasted screenshot as parity.

App Snapshot appears to be a Computer Use sub-surface. On macOS, it is backed by a native `Codex Computer Use.app` bundle that can inspect windows, capture screenshots, read accessibility trees, manage permissions, and serve MCP tools for live app interaction.

## Current Main State

`main` currently ports only an experimental screenshot-context slice of App Snapshot. It does not port full App Snapshot or Computer Use parity.

The experimental slice provides:

- a Linux **Add app snapshot** menu item in the composer plus menu,
- Electron display-media handling for screen/window capture,
- screenshot-style native-app context preview in the composer,
- a feature manifest entry named `appSnapshotScreenshot`.

It does not provide:

- Linux window enumeration.
- Linux app chooser / app approval store.
- Linux screenshot capture tied to durable app/window identity.
- Linux accessibility tree extraction.
- Linux input control.
- Computer Use MCP server.
- Appshot capture transition or sound.

Any current screenshot attachment should be treated as a partial visual attachment only. It is useful for visual reasoning, but it is not macOS Appshot or Computer Use parity.

## DMG Ground Truth

The DMG bundles Computer Use as a plugin:

- `Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/plugin.json`
- `Contents/Resources/plugins/openai-bundled/plugins/computer-use/.mcp.json`
- `Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app`
- `Contents/Resources/plugins/openai-bundled/plugins/computer-use/skills/computer-use/SKILL.md`

The plugin manifest says:

- plugin name: `computer-use`
- version: `1.0.791`
- short description: control Mac apps from Codex
- long description: Codex can use any app, including browsers and files the user allows; it may take screenshots or page content.

The MCP config launches:

```json
{
  "mcpServers": {
    "computer-use": {
      "command": "./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient",
      "args": ["mcp"],
      "cwd": "."
    }
  }
}
```

The native bundle contains:

- `Contents/MacOS/SkyComputerUseService`
- `Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`
- `Contents/SharedSupport/CUALockScreenGuardian.app`
- `Contents/SharedSupport/Codex Computer Use Installer.app`
- `Contents/Resources/Package_Appshot.bundle`
- `Contents/Resources/Package_ComputerUse.bundle`
- `Contents/Resources/Package_ComputerUseClient.bundle`

The `Package_Appshot.bundle` and `Appshot.wav` entries are direct evidence that Appshot is a native packaged component, not just renderer image upload.

## Native Capability Evidence

String inspection of `SkyComputerUseService` and `SkyComputerUseClient` shows macOS-specific dependencies and concepts:

- `ScreenCaptureKit.framework`
- `SCScreenshotManager`
- `SCWindow`
- `CGWindowListCopyWindowInfo`
- `CGWindowListCreateDescriptionFromArray`
- `CGWindowListCreate`
- `AXUIElement`
- `AccessibilityPermission`
- `ScreenRecordingPermission`
- `AppshotCaptureStore`
- `AppshotCaptureSound`
- `AppshotCaptureTransition`
- `WindowServerCaptureOptions`
- `ComputerUseIPCFrontmostWindow`
- `ComputerUseIPCScreenshot`
- `ComputerUseMCPServer`
- `ComputerUseMCPToolName`
- `computer_use_mcp_app_approval_requested`
- `computer_use_mcp_app_approval_resolved`

This proves the macOS feature does at least four things:

1. Finds relevant app/window targets.
2. Captures screenshots through macOS screen/window APIs.
3. Extracts accessibility context for UI elements.
4. Serves MCP tools for interaction and app approval.

## Renderer Contract

Computer Use availability is gated in `webview/assets/use-in-app-browser-use-availability-*.js`.

Observed renderer gates:

- feature name: `computer_use`
- Statsig gate: observed id `1506311413`
- platform support: `macOS` and `windows`
- host requirement: local host only

The renderer broadcasts desktop feature state through `app-main-*.js`:

- `computerUse`
- `computerUseNodeRepl`
- `externalBrowserUse`
- `externalBrowserUseAllowed`

Settings routes include:

- `/settings/computer-use`
- `/settings/computer-use/google-chrome`

Computer Use settings expose:

- allowed apps list
- app approval removal
- background/locked use
- sound mode
- Chrome setup status

### Composer Attachment Path

The composer has a dedicated native-app context path. This is separate from normal pasted image attachments:

- `composer-*.js` initializes composer state with `nativeAppContexts: []`.
- Queued-message edit restore reads `context.nativeAppContexts ?? []`.
- The attachment preview component receives:
  - `nativeAppContexts`
  - `pendingNativeAppCaptureRequestIds`
  - `onRemoveNativeAppContext`
- The composer footer receives:
  - `onAddNativeAppContext`
  - `onNativeAppCaptureAnimationDuration`
  - `onNativeAppCaptureStarted`
  - `onNativeAppCaptureSettled`
  - `getNativeAppCaptureAnimationDestinationFrame`

This proves that App Snapshot is modeled as "native app context", not as a generic image upload.

Important current-DMG finding: the add-context dropdown component receives all native-app capture props, but the menu item slot currently evaluates to `null` in the extracted renderer bundle:

```js
W = null
```

That `W` value is placed between "Add photos & files" and "Add remote files" in the plus menu. In other words, the renderer has the wiring shape for native app capture, but this DMG does not render an App Snapshot menu action from that slot. If a later upstream build shows "Add App Snapshot", that build must be re-extracted and this section revalidated.

The attachment preview component also appears to reserve a native-app context slot but sets the rendered native-context preview to `null` in the currently extracted bundle. Normal image attachments are rendered by mapping `imageAttachments`; native app contexts are included in the visibility condition but not visibly rendered in the extracted preview path.

The prompt text builder in `app-server-manager-signals-*.js` accepts `nativeAppContexts = []`, but the currently extracted function does not serialize those contexts into the text prompt. It serializes IDE context, files, image-derived attachments, comments, selections, PR checks, and in-app browser URL. Therefore App Snapshot parity must either:

1. pass native app context through a non-text attachment/API channel, or
2. depend on renderer/backend code that is not active in this DMG, or
3. be behind a rollout/build split not present in the extracted artifact.

Do not implement App Snapshot by only appending screenshot markdown to the prompt and call it parity. That would bypass the native-app context contract.

## Experimental Linux Screenshot Slice

The current `main` implementation deliberately takes the smallest useful release slice:

1. Patch Electron main process after `app.whenReady()` to install `session.defaultSession.setDisplayMediaRequestHandler`.
2. Use `desktopCapturer.getSources({ types: ["window", "screen"] })` to provide a capturable source to `getDisplayMedia`.
3. Patch the add-context dropdown's previously-null native-app slot into **Add app snapshot**.
4. On click, call `navigator.mediaDevices.getDisplayMedia({ video: true, audio: false })`.
5. Draw the first video frame into a canvas and call the existing `onAddNativeAppContext` path with:

```js
{
  imageDataUrl: "...png data url...",
  imageName: "app-snapshot.png",
  linuxScreenshotFallback: true
}
```

6. Patch the composer preview path so native contexts with `imageDataUrl` render visibly before send.

This is a release compromise, not the final architecture. It is acceptable to ship only if the README and manifest describe it as screenshot-context, not Computer Use. It should not enable `computer_use` settings gates or claim Chrome/app control.

Required final runtime checks for this slice:

1. `+ -> Add app snapshot` appears.
2. Canceling capture leaves the composer usable.
3. Successful capture creates a visible composer preview.
4. Sending the message lets Codex inspect visible screenshot content.
5. No Computer Use or Chrome Control claim is made in UI/docs beyond the screenshot-context note.

## Main-Process Contract

Observed IPC and main-process handlers include:

- `computer-use-app-approvals-visibility`
- `computer-use-app-approvals-read`
- `computer-use-app-approval-remove`
- `computer-use-sound-mode-read`
- `computer-use-sound-mode-write`
- `computer-use-background-auth-read`
- `computer-use-background-auth-write`
- `capture-computer-use-turn-route`
- `chronicle-permissions`

Observed native/runtime constants include:

- `SKY_CUA_SERVICE_PATH`
- `SKY_CUA_NATIVE_PIPE`
- `SKY_CUA_NATIVE_PIPE_DIRECTORY`
- `Codex Computer Use.app`

The macOS path is not just "renderer calls screenshot". It involves app-server state, route capture, plugin/MCP lifecycle, native service paths, and permission checks.

## Mac Lifecycle Model

Current inferred lifecycle, adjusted by renderer evidence:

1. Renderer checks Computer Use availability for the local host.
2. Settings surfaces show Computer Use configuration when gates pass.
3. Composer carries native-app context state and native capture callbacks.
4. In this DMG, the plus-menu App Snapshot action is not rendered; the slot is `null`.
5. When the action exists in a future build, user chooses an app/window or starts an App Snapshot action.
6. Main/app-server captures a Computer Use route for the current conversation/turn.
7. Native Computer Use service validates Screen Recording and Accessibility permissions.
8. User approves a target app when required.
9. Appshot captures the selected/frontmost app/window screenshot and transition state.
10. Computer Use client returns native app context through a payload channel that still needs confirmation.
11. If the task proceeds beyond snapshot, Computer Use MCP tools can click/type/scroll/set values against the approved app.
12. Allowed-app decisions and sound/background settings persist through settings IPC.

The exact payload attached to the conversation still needs capture from a live macOS session or deeper minified renderer tracing. Based on native strings, the payload is expected to contain more than a bitmap: app identity, window title, screenshot metadata, and possibly accessibility/tree context.

## Linux Parity Requirements

Minimum Linux replacement:

1. Preserve or replace the `computer-use` plugin metadata so Codex can expose the same surface.
2. Provide a Linux `computer-use` MCP server compatible with the expected tool contract.
3. Implement app/window enumeration:
   - X11: `wmctrl`, `xdotool`, `xprop`, EWMH, or direct XCB.
   - Wayland: compositor-specific APIs or xdg-desktop-portal where available.
4. Implement screenshot capture:
   - X11: `xwd`, ImageMagick `import`, grim alternatives where available.
   - Wayland: `org.freedesktop.portal.Screenshot` or compositor-specific tools.
5. Implement app/window identity:
   - process id
   - window id
   - title
   - desktop file / app id where available
   - icon if available
6. Implement accessibility context:
   - AT-SPI tree where available.
   - Browser DOM context only when browser-specific bridges are available.
   - Explicitly mark unavailable accessibility data instead of pretending screenshot is parity.
7. Implement app approval persistence.
8. Wire renderer feature gates only after backend readiness can be checked.
9. Ensure composer remains usable after snapshot failure.
10. Add deterministic errors for missing portal, no capturable windows, denied permission, and unsupported display server.

## Chrome Relationship

Chrome can be controlled through two different surfaces:

- Chrome plugin / Chrome Extension: browser-specific, DOM and tab control.
- Computer Use: generic desktop control of the Chrome app window.

Mac Computer Use likely can operate Chrome as an app because it controls generic Mac apps. That is not the same as the Chrome plugin. Linux parity should preserve both concepts:

- Use Chrome plugin for authenticated browser automation where extension/native-host is available.
- Use Computer Use for visual app/window interaction, including Chrome windows, only after Linux desktop control exists.

## Implementation Recipe For Main

For full parity, do not begin with renderer button patches. The order should be:

1. Do not patch the App Snapshot plus-menu item yet. The extracted current DMG has the native-app menu slot as `null`.
2. Re-extract any newer DMG that actually displays "Add App Snapshot" and compare the add-context dropdown slot against this artifact.
3. Trace the non-text payload path for `nativeAppContexts`; the prompt builder currently accepts but does not serialize it.
4. Define a Linux MCP server interface matching the Computer Use client enough for `get_app_state` first.
5. Implement read-only Linux app snapshot:
   - enumerate windows
   - choose frontmost or selected window
   - capture screenshot
   - return app/window metadata
6. Wire backend readiness check.
7. Patch feature availability to show Computer Use/App Snapshot only when the Linux backend exists and the renderer action exists in the upstream artifact.
8. Add app approval persistence.
9. Add accessibility tree extraction.
10. Add write actions only after read-only state works reliably.

## Acceptance Tests

App Snapshot is accepted only when all of these pass:

1. Fresh install into a clean output directory.
2. Launch app.
3. Open an external app with visible content.
4. Click `+` and choose Add App Snapshot.
5. A chooser, approval, or clear target selection flow appears.
6. Snapshot attaches without freezing composer input.
7. The model can identify the app, window title, and visible contents.
8. The attached context includes app/window metadata, not just a raw screenshot.
9. Restart app without reinstalling.
10. Repeat snapshot; approvals/settings persist or fail with a clear permission prompt.

Computer Use control is accepted only when these additional tests pass:

1. Ask Codex to inspect the approved app state.
2. Codex uses Computer Use MCP rather than generic image reasoning.
3. Codex can perform a harmless click or text entry after explicit user instruction.
4. Denied app approval stops the action and leaves the composer usable.

## Known Gaps

- Current extracted renderer has the native-app plus-menu action slot set to `null`; no active App Snapshot dispatch was found in that slot.
- Exact non-text payload path for `nativeAppContexts` is not yet confirmed.
- Exact conversation attachment payload is not yet captured.
- Linux display-server strategy is not chosen.
- No Linux Computer Use MCP server exists on `main`.
- No Linux app approval store exists on `main`.
- No Linux accessibility extraction exists on `main`.
