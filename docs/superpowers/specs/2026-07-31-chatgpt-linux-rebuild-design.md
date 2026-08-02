# ChatGPT Linux Rebuild Design

## Goal

Rebuild this project as a current-format, unofficial ChatGPT Linux installer. The installer targets only the `ChatGPT.app` payload distributed by the current OpenAI DMG. It does not preserve compatibility with older DMGs containing `Codex.app`.

The generated application is branded **ChatGPT Linux**:

- output directory: `chatgpt-linux/`
- launcher: `chatgpt-linux.sh`
- desktop file: `chatgpt-linux.desktop`
- product name: `ChatGPT Linux`

The embedded application still identifies itself as `com.openai.codex` and depends on the Codex CLI and `codex://` callback protocol. Those internal interfaces remain unchanged because renaming them would break authentication and desktop-to-CLI communication.

## Supported Input

The installer accepts the current OpenAI DMG layout:

```text
ChatGPT Installer/
└── ChatGPT.app/
    └── Contents/
        ├── Info.plist
        └── Resources/
            ├── app.asar
            ├── app.asar.unpacked/
            └── plugins/
```

Payload discovery is strict. The installer must locate the top-level `ChatGPT.app/Contents/Info.plist`, verify its bundle identifier is `com.openai.codex`, and require both the main ASAR and the expected extracted application structure. A DMG containing only `Codex.app` is rejected with a clear unsupported-layout error.

## Download and Validation

The default cached input is `ChatGPT-latest.dmg`. The already downloaded, valid `Codex-latest.dmg` will be renamed once to this new filename during implementation so it is not downloaded again.

For future downloads, the installer:

1. reads the expected size from the server when available;
2. prefers `wget --continue` for automatic range resumption;
3. falls back to a resumable `curl` loop when `wget` is unavailable;
4. compares the completed file size with the advertised size; and
5. tests the DMG with 7-Zip before extraction.

An incomplete cached file is resumed rather than treated as valid merely because it exists.

## Toolchain

The current application uses Electron 42 and current Electron build tooling, which require Node.js 22.12 or newer. The installer uses a suitable system Node.js when available. Otherwise, it downloads and uses a portable Node.js 22 runtime in its working directory without `sudo` or system-wide changes.

The installer uses an existing `7z` or `7zz` command when available. On Debian or Ubuntu, when neither exists and root access is unavailable, it downloads the `7zip` package and extracts its executable into the temporary work directory. Other distributions receive an exact prerequisite error rather than an attempted privileged system modification.

All downloaded tools are architecture-aware and limited to supported Linux architectures. Unsupported architectures fail before the output directory is changed.

## Extraction and Build

The installer extracts the complete DMG payload so `app.asar.unpacked` remains adjacent to `app.asar`. It then extracts the ASAR with a Node-22-compatible `@electron/asar` release.

The generated Linux package metadata:

- uses the application version and build from `ChatGPT.app/Contents/Info.plist`;
- preserves the current ASAR entry point, presently `.vite/build/early-bootstrap.js`;
- uses the Electron version declared by the current application, presently `42.3.0`;
- removes macOS-only, workspace, link, and unresolved file dependencies;
- installs the remaining runtime dependencies; and
- rebuilds native modules for the selected Linux Electron runtime.

The existing Linux patch engine remains only where its preconditions match the current extracted bundle. Every patch reports applied, skipped, or failed status. A required launcher or authentication patch failure stops installation; an optional feature patch may be skipped with a visible warning and recorded in the feature manifest.

The output directory is prepared only after input and toolchain validation. A failed build must not be reported as installed.

## Launcher and Desktop Integration

The generated `chatgpt-linux.sh` launcher:

- starts the Linux Electron runtime from `chatgpt-linux/`;
- retains the required `CODEX_*` environment variables;
- uses an installed Codex CLI when present and a local `npx` fallback otherwise;
- keeps the existing stable Linux graphics flags;
- supports `codex://` callback URLs passed as launcher arguments; and
- preserves remote-control setup where the current bundle still exposes it.

The desktop entry is named **ChatGPT Linux**, invokes `chatgpt-linux.sh %u`, and registers `x-scheme-handler/codex`.

## Error Handling

The installer emits a specific error for each boundary:

- incomplete or invalid DMG;
- unsupported DMG layout;
- wrong bundle identifier;
- missing `app.asar` or `app.asar.unpacked`;
- unsupported CPU architecture;
- unavailable Node.js 22 bootstrap;
- ASAR extraction failure;
- dependency installation or native rebuild failure;
- required patch failure; and
- launcher or desktop-entry generation failure.

Temporary build directories are removed on exit. The downloaded DMG and a successfully generated application are retained.

## Testing

Implementation follows test-driven development.

Pure installer functions are separated from the executable entry point so tests can source them without starting an installation. Tests use shell fixtures and Node's built-in test runner to cover:

- selecting only a `ChatGPT.app` payload;
- rejecting a `Codex.app`-only payload;
- rejecting missing `app.asar.unpacked`;
- validating the `com.openai.codex` bundle identifier;
- enforcing Node.js 22.12 or newer;
- generating ChatGPT Linux output and desktop names;
- preserving required Codex CLI and URL-scheme identifiers;
- refusing an incomplete cached download; and
- producing actionable error messages.

After unit tests pass, the real downloaded DMG is used for an end-to-end build. Completion requires:

1. all automated tests passing;
2. a complete `chatgpt-linux/` output tree;
3. valid generated package and build metadata;
4. native modules loadable by the selected Electron runtime;
5. a launcher smoke test with Electron logging enabled;
6. a valid `chatgpt-linux.desktop` entry; and
7. confirmation that `codex://` is registered to that desktop entry.

## Non-Goals

- Compatibility with older `Codex.app` DMGs.
- Renaming the internal Codex CLI, bundle identifier, environment variables, or URL scheme.
- Installing system packages with `sudo`.
- Claiming macOS-only Computer Use behavior works on Linux when its patch is absent or skipped.
- Supporting non-Linux hosts or CPU architectures for which the required portable runtime is unavailable.
