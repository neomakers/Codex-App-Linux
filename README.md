# Codex App Linux (Unofficial)

<p align="left">
  <img src="https://img.shields.io/badge/platform-linux-2ea44f" alt="Linux" />
  <img src="https://img.shields.io/badge/status-active-1f6feb" alt="Status" />
  <img src="https://img.shields.io/badge/installer-one--script-orange" alt="One script installer" />
  <img src="https://img.shields.io/badge/Codex%20Mobile-ported-2ea44f" alt="Codex Mobile pairing ported" />
  <img src="https://img.shields.io/badge/In--app%20Browser-working-0969da" alt="In-app Browser Use working" />
  <img src="https://img.shields.io/badge/App%20Snapshots-WIP-7c3aed" alt="App Snapshots work in progress" />
  <img src="https://img.shields.io/badge/Chrome%20Control-in%20progress-fbbc04" alt="Chrome Control in progress" />
  <img src="https://img.shields.io/badge/runtime-electron-black" alt="Electron" />
  <img src="https://img.shields.io/badge/version-2026.05.25--chrome--host-blue" alt="Installer version 2026.05.25-chrome-host" />
  <img src="https://img.shields.io/badge/project-unofficial-red" alt="Unofficial" />
</p>

<p align="center">
  <img src="demo/codex-mobile-pairing.png" alt="Codex Mobile pairing screen running in the Linux port with the QR code scrambled for safety" width="820" />
</p>

OpenAI does not currently ship a native Codex desktop app for Linux. That matters more now because newer Codex workflows expect a desktop Codex app for phone pairing, in-app Browser Use, Chrome control, and app context capture. This project fills that gap by converting the official macOS Codex `.dmg` into a Linux-compatible Electron bundle and patching selected desktop surfaces for Linux.

Download the script, execute it, and it builds a runnable `codex-linux` app directory for you.

## Why this exists

Codex desktop is distributed for macOS, while Linux users are left without a first-party desktop app. The core app is Electron-based, so with extraction, dependency filtering, native module rebuilds, and a few Linux compatibility patches, it can run on Linux.

The latest Codex mobile workflow also depends on desktop-side authentication and device approval. Without this port, Linux users can get stuck at the mobile app's **Waiting for desktop** step because there is no official Linux desktop client to approve the connection.

## What this gives Linux users

- A runnable Codex desktop app on Linux from the official Codex DMG.
- A one-script install flow: run `install-codex-linux.sh`, then launch `codex-linux/codex-linux.sh`.
- Codex Mobile pairing support through the desktop **Settings → Connections → Control other devices** flow.
- In-app Browser Use support for the Codex browser pane.
- Work-in-progress App Snapshot screenshot attachment for Linux. This is useful visual context, not full macOS Computer Use parity.
- Chrome Control groundwork using Google Chrome, the Codex Chrome Extension, and a generated Linux native messaging host. This is still in progress until runtime validation is complete.
- `codex://` URL handler registration so auth callbacks can return to the desktop app.
- Linux rebuilds/stubs for native and macOS-only Electron dependencies.

## Features

- **Unofficial Linux desktop port**: converts the official Codex macOS DMG into a runnable Linux Electron app.
- **Codex Mobile pairing**: exposes the desktop approval flow Linux users need when the phone app says **Waiting for desktop**, and starts the remote-control bridge expected by recent Codex builds. Mobile pairing is the primary completed port surface in this release.
- **In-app Browser Use**: enables Codex to inspect and operate the app's browser pane when the active turn has Browser Use metadata.
- **App Snapshot screenshot context, WIP**: adds a Linux **Add app snapshot** path that captures a desktop/window screenshot into the composer. It does not yet include macOS Computer Use metadata, accessibility context, or app control.
- **Chrome Control, in progress**: ports the upstream Chrome plugin contract for Google Chrome by installing the Codex Chrome Extension native messaging manifest and generating a Linux host bridge. Treat it as groundwork until Chrome runtime testing is complete.
- **One-script installer**: downloads or reuses a DMG, extracts the app, installs dependencies, rebuilds native modules, and creates a launcher.
- **Desktop integration**: adds a Linux app menu entry and registers `codex://` callback handling.
- **Latest-DMG compatibility patches**: filters macOS/workspace-only dependencies and applies Linux-specific runtime fixes.

## Quick start

### Option A: one command

Run this from the directory where you want the generated `codex-linux/` app folder to live:

```bash
curl -fsSL https://raw.githubusercontent.com/areu01or00/Codex-App-Linux/main/install-codex-linux.sh | bash
```

If you are already inside an existing generated `codex-linux/` folder, run `cd ..` first or re-run the installer from the parent directory.

### Option B: clone and run

```bash
git clone https://github.com/areu01or00/Codex-App-Linux.git
cd Codex-App-Linux
chmod +x install-codex-linux.sh
./install-codex-linux.sh
```

Then launch:

```bash
cd codex-linux
./codex-linux.sh
```

The installer also creates a desktop entry, so after the first install you can usually launch **Codex (Linux Port)** from your app menu.

The launcher defaults to a Linux stable graphics mode that avoids common Electron flicker/jank on Wayland, VAAPI, and Vulkan stacks. To use Electron's native graphics path instead:

```bash
CODEX_LINUX_GRAPHICS_MODE=native ./codex-linux.sh
```

## Installer flags

```bash
./install-codex-linux.sh --dmg /path/to/Codex.dmg
./install-codex-linux.sh --output /path/to/codex-linux
./install-codex-linux.sh --skip-cli-install
```

## What the installer does

Installer version: `2026.05.25-chrome-host`

1. Uses a local DMG if available, otherwise downloads latest from OpenAI CDN.
2. Extracts `app.asar` from the app bundle.
3. Builds Linux runtime metadata from extracted app version/dependencies.
4. Installs Electron + dependencies and rebuilds native modules for Linux.
5. Stubs macOS-only modules (`sparkle`, `electron-liquid-glass`).
6. Runs `tools/patch-codex-linux.mjs` to patch selected Linux feature surfaces: mobile pairing UI/bridge, in-app Browser Use, App Snapshot screenshot context, and Chrome Control groundwork.
7. Generates launcher script and desktop entry.
8. Registers `codex://` as a Linux URL handler for desktop auth callbacks.

The patch engine writes `codex-linux/codex-linux-feature-manifest.json` so each install records which Linux compatibility patches were applied or skipped.

## Codex Mobile pairing

This Linux port supports the newer Codex phone pairing flow used by the Codex mobile app. The official Codex desktop app is not distributed for Linux, so the mobile app can otherwise wait for a desktop approval step Linux users cannot complete. This installer patches the desktop web UI so the mobile pairing controls are visible on Linux, registers the `codex://` URL scheme used by auth callbacks, enables the `remote_control` feature flag, and starts the Codex remote-control bridge from the launcher.

After installing:

1. Launch Codex from `codex-linux/codex-linux.sh` or the desktop app entry.
2. Open **Settings**.
3. Go to **Connections**.
4. Use the Codex Mobile / **Control other devices** setup flow.
5. Allow this device to be discovered and controlled.
6. Open the Codex mobile app and tap **Connect**.

If you only see fields such as **Display Name**, **Hostname**, and **SSH port**, that is the SSH remote-host setup form, not the phone pairing flow. Re-run the latest installer so the mobile pairing UI patch is applied.

Mobile pairing requires the Linux desktop app process to stay running. If the mobile app stays on **Waiting for desktop**, keep the desktop app open and inspect:

```bash
tail -n 100 "${XDG_CONFIG_HOME:-$HOME/.config}/codex-linux/remote-control-daemon.log"
tail -n 100 "${XDG_CONFIG_HOME:-$HOME/.config}/codex-linux/remote-control-start.stderr"
```

## Browser Use

The installer enables the in-app Browser Use path on Linux and generates a Linux `node_repl` bridge used by Codex Browser Use turns. Expected behavior:

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

The Linux port currently provides a work-in-progress screenshot-context version of **Add app snapshot**:

1. Click `+` in the composer.
2. Choose **Add app snapshot**.
3. Select a screen/window if your desktop environment prompts.
4. Confirm that a snapshot preview appears in the composer.

This is intentionally not advertised as full macOS Computer Use parity. The upstream macOS feature is backed by a native Computer Use bundle with app/window metadata, permissions, accessibility context, and MCP control. The Linux port currently attaches screenshot-style visual context only. It should help Codex inspect what is visible, but it does not give Codex control over that app.

## Background Presence

This release does not ship reliable Linux tray/background presence. Keep the Codex desktop app process running for phone/mobile presence. If you launch with `./codex-linux.sh` from a terminal and close or quit the app, mobile will see the desktop as offline.

Disable the remote-control bridge for debugging:

```bash
CODEX_LINUX_REMOTE_CONTROL=0 ./codex-linux.sh
```

## Known limitations

- This is an unofficial port of a macOS app; upstream DMG changes can break patch snippets.
- Mobile pairing requires the Linux desktop app process to keep running.
- Browser Use depends on active in-app browser turn metadata.
- App Snapshot is screenshot-context only, not full macOS Computer Use/Appshot parity.
- Chrome Control is in progress and Google-Chrome-only for the first pass. It requires the Codex Chrome Extension and runtime validation on the target machine.
- Reliable tray/background presence is not part of this release.

## Version diagnostics

After install, the script writes:

`codex-linux/build-info.json`

This includes:
- installer version
- Codex app version/build from the DMG
- Electron runtime version
- selected main entrypoint
- DMG path + SHA256
- Codex CLI path + version

Attach this file in issues. It makes compatibility debugging much faster.

## Requirements

- Linux (tested on Ubuntu 22.04+)
- Node.js + npm
- `curl`
- `7z` or `7zz` for DMG extraction
- ~500MB free disk

Install 7zip before running the installer:

```bash
# Ubuntu/Debian
sudo apt install p7zip-full

# Fedora
sudo dnf install p7zip p7zip-plugins

# Arch
sudo pacman -S p7zip

# openSUSE
sudo zypper install p7zip
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `Cannot find module ...` on startup | Re-run installer so dependencies are regenerated for that DMG build |
| `codex-app-server-version-unsupported` | Update CLI: `npm i -g @openai/codex@latest`; launcher should use `which codex` |
| CLI not found | Install CLI globally or let launcher use built-in `npx` fallback |
| `7zip not found` | Install `p7zip-full`, `p7zip`, or your distro's 7zip package, then rerun the installer |
| Blank/failed window | Ensure `.vite` and `webview` exist under install output directory |
| Flickering, white panels, or janky settings UI | Use the default launcher. It applies stable Linux graphics flags. To opt out, run `CODEX_LINUX_GRAPHICS_MODE=native ./codex-linux.sh` |
| Phone/browser auth does not return to Codex | Re-run installer, then verify `xdg-mime query default x-scheme-handler/codex` returns `codex-linux.desktop` |

## Authentication callbacks

Recent Codex desktop builds register a `codex://` URL scheme. The Linux port mirrors that by creating a desktop entry with:

```desktop
MimeType=x-scheme-handler/codex;
Exec=/path/to/codex-linux/codex-linux.sh %u
```

The `%u` is important: it passes the callback URL, such as `codex://connector/oauth_callback`, into Electron so the app can complete the desktop authentication flow.

## What is not committed

The repository intentionally does not commit downloaded or generated app files:

- `Codex-latest.dmg` / `*.dmg`: official app binaries downloaded from OpenAI
- `codex-linux/`: generated Linux app output
- `node_modules/`, logs, and temporary build folders

That is the correct setup: this repo distributes the installer and docs only, not OpenAI application binaries or generated dependency trees.

## Repo files

- `install-codex-linux.sh`: one-click installer
- `.gitignore`: excludes downloaded DMGs and generated install output
- `Reverse-engineering-guide.md`: technical breakdown of the original approach
- `README.md`: usage and troubleshooting

## Legal

This project distributes tooling/instructions only. It does not distribute OpenAI app binaries.

You must obtain `Codex.dmg` from official OpenAI sources.

Not affiliated with OpenAI.
