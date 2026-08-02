# ChatGPT Linux (Unofficial)

<p align="left">
  <img src="https://img.shields.io/badge/platform-linux-2ea44f" alt="Linux" />
  <img src="https://img.shields.io/badge/status-active-1f6feb" alt="Status" />
  <img src="https://img.shields.io/badge/installer-one--script-orange" alt="One script installer" />
  <img src="https://img.shields.io/badge/Codex%20Mobile-experimental-d97706" alt="Codex Mobile pairing experimental" />
  <img src="https://img.shields.io/badge/In--app%20Browser-partial-d97706" alt="In-app Browser Use partial" />
  <img src="https://img.shields.io/badge/App%20Snapshots-skipped-lightgrey" alt="App Snapshots skipped in the current release" />
  <img src="https://img.shields.io/badge/Chrome%20Control-in%20progress-fbbc04" alt="Chrome Control in progress" />
  <img src="https://img.shields.io/badge/runtime-electron-black" alt="Electron" />
  <img src="https://img.shields.io/badge/source-current%20ChatGPT.app-blue" alt="Current ChatGPT.app source" />
  <img src="https://img.shields.io/badge/project-unofficial-red" alt="Unofficial" />
</p>

<p align="center">
  <img src="demo/codex-mobile-pairing.png" alt="Codex Mobile pairing screen running in the Linux port with the QR code scrambled for safety" width="820" />
</p>

OpenAI does not currently ship the ChatGPT desktop app for Linux. This project rebuilds the exact official macOS ChatGPT DMG selected by `compatibility/current.json` as an unofficial Linux Electron bundle and applies selected Linux runtime patches.

Only the current DMG layout containing `ChatGPT.app` is supported. Older DMGs containing `Codex.app` are intentionally rejected instead of being handled by a compatibility path.

Run the installer and it builds a runnable `chatgpt-linux/` directory plus a **ChatGPT Linux** desktop entry.

For a later DMG release, follow [UPGRADING.md](UPGRADING.md) and compare it with the [current compatibility contract](compatibility/current.json). Those files are the current source of upgrade truth.

## Why this exists

The current ChatGPT desktop package is Electron-based. The installer extracts `ChatGPT.app`, removes dependencies that cannot be installed on Linux, rebuilds native modules for the bundled Electron version, and stages the result under Linux-specific user-visible names.

The latest Codex mobile workflow also depends on desktop-side authentication and device approval. Without this port, Linux users can get stuck at the mobile app's **Waiting for desktop** step because there is no official Linux desktop client to approve the connection.

## What this gives Linux users

- A runnable ChatGPT desktop app on Linux built from the repository's current verified official ChatGPT DMG.
- A one-script install flow: run `install-chatgpt-linux.sh`, then launch `chatgpt-linux/chatgpt-linux.sh`.
- Experimental Codex Mobile pairing surfaces through **Settings → Connections → Control other devices**; end-to-end enrollment remains release-dependent.
- A Linux Browser Use `node_repl` bridge. The current upstream Browser Use data flow has changed, so treat it as partial until an active turn succeeds end to end.
- Explicit feature-manifest reporting when App Snapshot or other version-sensitive patches are unavailable.
- Chrome Control groundwork using Google Chrome, the Codex Chrome Extension, and a generated Linux native messaging host. This is still in progress until runtime validation is complete.
- `codex://` URL handler registration so auth callbacks can return to the desktop app.
- Linux dependency filtering and native-module rebuilds for the exact bundled Electron runtime.

## Features

- **Current ChatGPT package rebuild**: converts the official macOS DMG containing `ChatGPT.app` into a runnable Linux Electron app.
- **Codex Mobile pairing, partial**: exposes the upstream approval flow, but remote control is opt-in and a protected Linux device-key provider is not available. Availability and server-side enrollment remain unverified.
- **In-app Browser Use, partial**: generates the Linux `node_repl` bridge. In ChatGPT 26.727 the upstream availability and routing code was refactored, so legacy renderer/route replacements are skipped and end-to-end control remains unverified.
- **App Snapshot, skipped in 26.727**: the renderer chunks used by the experimental screenshot patch are absent from the current app. The installer records this as `skipped` instead of failing or claiming support.
- **Chrome Control, in progress**: ports the upstream Chrome plugin contract for Google Chrome by installing the Codex Chrome Extension native messaging manifest and generating a Linux host bridge. Treat it as groundwork until Chrome runtime testing is complete.
- **One-script installer**: accepts only the DMG identity and application metadata pinned by the current release contract, then validates staging before promotion.
- **Desktop integration**: adds a **ChatGPT Linux** app-menu entry and registers the upstream `codex://` callback handler.
- **Current-layout validation**: accepts `ChatGPT.app` and fails clearly when an older or incomplete package layout is supplied.

## Quick start

### Option A: existing checkout

Run the installer from the project root. It uses the adjacent `lib/` and `tools/` files, so the entry script is not intended to be piped by itself from `curl`.

```bash
./install-chatgpt-linux.sh
```

If you are inside an existing generated `chatgpt-linux/` folder, run `cd ..` first.

### Option B: clone and run

```bash
git clone https://github.com/neomakers/Codex-App-Linux.git
cd Codex-App-Linux
chmod +x install-chatgpt-linux.sh
./install-chatgpt-linux.sh
```

Then launch:

```bash
cd chatgpt-linux
./chatgpt-linux.sh
```

The installer also creates `chatgpt-linux.desktop`, so after the first install you can usually launch **ChatGPT Linux** from your app menu.

The launcher defaults to a Linux stable graphics mode that avoids common Electron flicker/jank on Wayland, VAAPI, and Vulkan stacks. To use Electron's native graphics path instead:

```bash
CODEX_LINUX_GRAPHICS_MODE=native ./chatgpt-linux.sh
```

## Installer flags

```bash
./install-chatgpt-linux.sh --dmg /path/to/ChatGPT.dmg
./install-chatgpt-linux.sh --output /path/to/chatgpt-linux
./install-chatgpt-linux.sh --skip-cli-install
./install-chatgpt-linux.sh --skip-gui-smoke  # expert/headless use; recorded as skipped
./install-chatgpt-linux.sh --audit-candidate --dmg /path/to/future.dmg \
  --audit-source-url https://example.invalid/future.dmg \
  --audit-output /tmp/chatgpt-audit
```

## What the installer does

Normal installation is bound to `compatibility/current.json`. The mutable download URL is not treated as “latest”; an exact cached contract DMG remains valid even if that URL changes.

1. Loads the selected immutable release contract and requires the exact DMG byte size and SHA-256 before extraction. A changed remote `Content-Length` is rejected before download.
2. Requires the contract's `ChatGPT.app` profile, bundle ID, version/build, source macOS architecture, target Linux architecture, Electron version, main entry, and every required path.
3. Uses system Node.js 22.12 or newer; otherwise caches portable Node.js 22.23.2 under `${XDG_CACHE_HOME:-$HOME/.cache}/chatgpt-linux/toolchain` without changing the system installation.
4. Installs dependencies without running Node-ABI install scripts, downloads the exact Electron runtime, then rebuilds native modules once for that Electron ABI. Network-sensitive stages retry up to three times.
5. Runs `tools/patch-chatgpt-linux.mjs` for selected Linux feature surfaces. Every patch is version-sensitive and recorded.
6. Loads `@parcel/watcher`, `bufferutil`, `utf-8-validate`, `node-pty`, and `better-sqlite3` through Electron-as-Node from staging, then runs a bounded 40-second GUI smoke in an isolated state directory and owned process group with remote control disabled. `CHATGPT_GUI_SMOKE_SECONDS` may set an explicit 1–90 second bound for slower or faster hosts.
7. Promotes only validated staging, restores the old output on promotion failure, and retains one timestamped previous output for rollback.
8. Generates the launcher and `build-info.json`, then creates desktop integration only after promotion.
9. Registers the upstream `codex://` scheme so authentication callbacks still reach the application.

`--audit-candidate` is a non-installing path for a future DMG. It derives architecture from the candidate macOS executable, accepts a future bundle ID as evidence instead of as an install contract, writes portable identity/application evidence, then exits before dependency installation, patching, desktop registration, or output promotion. Remote audits always use a new candidate filename and never move or overwrite an earlier candidate in the audit directory.

The patch engine writes `chatgpt-linux/chatgpt-linux-feature-manifest.json` so each install records which Linux patches were applied or skipped.

## Internal Codex contracts

The public product and generated files are named **ChatGPT Linux**, but the current upstream package still relies on several Codex identifiers:

- the `@openai/codex` CLI and its `codex` executable;
- environment variables such as `CODEX_CLI_PATH`, `CODEX_BROWSER_USE_NODE_PATH`, `CODEX_NODE_REPL_PATH`, `CODEX_LINUX_GRAPHICS_MODE`, and `CODEX_LINUX_REMOTE_CONTROL`;
- the `com.openai.codex` bundle identity and `codex://` authentication callback scheme.

These identifiers are intentionally preserved because changing them would break communication with the bundled app, CLI, or authentication flow.

## Codex Mobile pairing

The current `ChatGPT.app` contains upstream Codex phone-pairing surfaces. The patch engine exposes those controls and preserves `codex://` callbacks, but it does not patch an exportable software key as protected hardware. The launcher neither edits `~/.codex/config.toml` nor starts the daemon unless `CODEX_LINUX_REMOTE_CONTROL=1` is explicitly set. Mobile pairing remains partial.

After installing:

1. Launch ChatGPT Linux from `chatgpt-linux/chatgpt-linux.sh` or the desktop app entry.
2. Open **Settings**.
3. Go to **Connections**.
4. Use the Codex Mobile / **Control other devices** setup flow.
5. Allow this device to be discovered and controlled.
6. Open the Codex mobile app and tap **Connect**.

If you only see fields such as **Display Name**, **Hostname**, and **SSH port**, that is the SSH remote-host setup form, not the phone pairing flow. Re-run the latest installer so the mobile pairing UI patch is applied.

To experiment with the partial bridge, keep the desktop app running and opt in explicitly:

```bash
CODEX_LINUX_REMOTE_CONTROL=1 ./chatgpt-linux.sh
```

If the mobile app stays on **Waiting for desktop**, inspect:

```bash
tail -n 100 "${XDG_CONFIG_HOME:-$HOME/.config}/chatgpt-linux/remote-control-daemon.log"
tail -n 100 "${XDG_CONFIG_HOME:-$HOME/.config}/chatgpt-linux/remote-control-start.stderr"
```

## Browser Use

The installer generates a Linux `node_repl` bridge used by Codex Browser Use turns. ChatGPT 26.727 contains a redesigned upstream Browser Use session router, so the legacy gate and synthetic-turn patches are intentionally skipped. The installed manifest reports this feature as `partial`.

The GUI smoke test confirms that the browser pane can resolve as available on Linux, but that is not proof of end-to-end tool control. To validate it manually:

1. Open the in-app browser panel.
2. Navigate to a site in that panel.
3. Ask Codex to browse or interact with the open page.
4. Codex should use Browser Use rather than generic web search when the active turn has browser metadata.

If Browser Use reports missing turn metadata or no active browser pane, restart Codex and reopen the site from the same chat thread. Do not treat web-search fallback as Browser Use success.

## Chrome Control

Chrome Control is in progress and intentionally matches the upstream DMG contract first:

- supported browser: Google Chrome
- required extension: Codex Chrome Extension
- native messaging host: `com.openai.codexextension`
- manifest path: `~/.config/google-chrome/NativeMessagingHosts/com.openai.codexextension.json`

The installer copies the bundled Chrome plugin, generates a Linux native messaging host at `plugins/openai-bundled/plugins/chrome/extension-host/linux/<arch>/extension-host`, and patches the Chrome helper scripts for Linux manifest checks and Google Chrome process/launcher detection.

This release includes the Linux host groundwork, but Chrome Control is not yet advertised as complete until it is tested end-to-end with regular Google Chrome and the Codex Chrome Extension. Chromium, Brave, Edge, Vivaldi, Snap/Flatpak Chrome profiles, and Chrome Beta/Dev/Canary are not first-pass targets.

## App Snapshot

App Snapshot is not enabled for ChatGPT 26.727. Its former annotation-editor and composer chunks are absent, so the installer safely skips the experimental patch and records `appSnapshotScreenshot: skipped` in `chatgpt-linux-feature-manifest.json`.

This is preferable to applying a broad match to unrelated minified files. Restoring screenshot context requires a new version-specific implementation and runtime test; full macOS Computer Use parity remains out of scope.

## Background Presence

This release does not ship reliable Linux tray/background presence. Keep the ChatGPT Linux process running for phone/mobile presence. If you launch with `./chatgpt-linux.sh` from a terminal and close or quit the app, mobile will see the desktop as offline.

Remote control is off by default. Enable the partial bridge only for an explicit test:

```bash
CODEX_LINUX_REMOTE_CONTROL=1 ./chatgpt-linux.sh
```

## Known limitations

- Normal installation accepts only the exact release selected by `compatibility/current.json`; use `--audit-candidate` to inspect a future DMG without installing it. Older `Codex.app` layouts are deliberately rejected.
- Feature patches match minified upstream code and may be skipped when a new ChatGPT release changes those snippets. Review the generated feature manifest.
- Mobile pairing requires the Linux desktop app process to keep running.
- Browser Use is partial/unverified in the current release and depends on active in-app browser session metadata.
- App Snapshot is skipped in ChatGPT 26.727; full macOS Computer Use/Appshot parity is not available.
- Chrome Control is in progress and Google-Chrome-only for the first pass. It requires the Codex Chrome Extension and runtime validation on the target machine.
- Reliable tray/background presence is not part of this release.

## Version diagnostics

After install, the script writes:

`chatgpt-linux/build-info.json`

This includes:
- installer version
- ChatGPT app version/build from the DMG
- Electron runtime version
- selected main entrypoint
- DMG path + SHA256
- release contract, DMG byte size, selected Node/npm paths, and staging validation result
- Codex CLI path + version

Attach this file in issues. It makes compatibility debugging much faster.

## Requirements

- Linux (tested on Ubuntu 22.04+)
- Node.js 22.12+ and npm, or permission for the installer to download portable Node.js 22.23.2 locally
- `curl` for metadata and resumable downloads
- `wget` is optional and used for resumable transfers when available
- `7z` or `7zz` for DMG extraction; Debian-family systems can cache the `7zip` package under the user toolchain cache without sudo
- Several GB of free disk for the DMG, extracted app, Electron runtime, and staging output

If local 7-Zip bootstrap is unavailable on your distribution, install it before running the installer:

```bash
# Ubuntu/Debian
sudo apt install 7zip

# Fedora
sudo dnf install 7zip

# Arch
sudo pacman -S 7zip

# openSUSE
sudo zypper install 7zip
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `Cannot find module ...` on startup | Re-run installer so dependencies are regenerated for that DMG build |
| `codex-app-server-version-unsupported` | Update CLI: `npm i -g @openai/codex@latest`; launcher should use `which codex` |
| CLI not found | Install CLI globally or let the launcher use its recorded Node/npm fallback |
| Recorded Node runtime is unavailable | Re-run the installer to restore the persistent cached toolchain; the launcher will not silently fall back to an incompatible runtime |
| `7zip not found` | Install your distribution's `7zip` package, then rerun the installer |
| Blank/failed window | Ensure `.vite` and `webview` exist under install output directory |
| Flickering, white panels, or janky settings UI | Use the default launcher. It applies stable Linux graphics flags. To opt out, run `CODEX_LINUX_GRAPHICS_MODE=native ./chatgpt-linux.sh` |
| Phone/browser auth does not return to the app | Re-run installer, then verify `xdg-mime query default x-scheme-handler/codex` returns `chatgpt-linux.desktop` |

## Authentication callbacks

The upstream application retains the internal `codex://` URL scheme. ChatGPT Linux preserves it by creating a desktop entry with:

```desktop
MimeType=x-scheme-handler/codex;
Exec=/path/to/chatgpt-linux/chatgpt-linux.sh %u
```

The `%u` is important: it passes the callback URL, such as `codex://connector/oauth_callback`, into Electron so the app can complete the desktop authentication flow.

## What is not committed

The repository intentionally does not commit downloaded or generated app files:

- `ChatGPT-latest.dmg` / `*.dmg`: official app binaries downloaded from OpenAI
- `chatgpt-linux/`: generated Linux app output
- `node_modules/`, logs, and temporary build folders

That is the correct setup: this repo distributes the installer and docs only, not OpenAI application binaries or generated dependency trees.

## Repo files

- `install-chatgpt-linux.sh`: one-click installer
- `.gitignore`: excludes downloaded DMGs and generated install output
- `UPGRADING.md`: canonical evidence, audit, rebuild, and release workflow
- `compatibility/current.json`: pointer to the current executable release contract
- `Reverse-engineering-guide.md`: historical technical evidence from the original approach
- `README.md`: usage and troubleshooting

## Legal

This project distributes tooling/instructions only. It does not distribute OpenAI app binaries.

You must obtain the ChatGPT DMG containing `ChatGPT.app` from official OpenAI sources.

Not affiliated with OpenAI.
