# Repository Memory and Upstream Sync Design

## Goal

Turn the verified ChatGPT.app-only Linux rebuild into the canonical GitHub project without losing the existing fork history, and make each future upstream refresh start from recorded evidence, executable checks, and explicit compatibility decisions.

## Current State

- The working directory is a ZIP-style snapshot with no `.git` metadata.
- The original upstream is `areu01or00/Codex-App-Linux`, currently at commit `27371c24b143b1901a5c8c4059dd396ab34bc262`.
- The writable fork is `neomakers/Codex-App-Linux`, currently at commit `dc7e365c5de6649ed11df467e5ebc9d78a473543` and one commit ahead of upstream.
- The local source has deliberately moved from a Codex.app compatibility installer to a ChatGPT.app-only rebuild.
- Downloaded DMGs, generated Electron applications, local paths, credentials, and proprietary application resources must not be committed.

## Git History and Publication Strategy

The writable fork remains the history source. Before importing the local rebuild, tag its current `main` as `codex-legacy-2026-07-16`. Create a feature branch from that commit, replace the tracked source with the verified ChatGPT.app-only source, and commit the migration normally. Do not force-push and do not synthesize an unrelated root commit.

The old Debian/Codex packaging files are removed from the new mainline because they target the retired Codex.app layout. Their complete contents remain recoverable from the legacy tag and Git history. The original repository is retained as an `upstream` remote for provenance and selective review, not for blind merges.

After validation, publish through a pull request and merge it into `main`. Keep the writable fork slug `neomakers/Codex-App-Linux` for this migration because it is the existing accessible repository and preserves the upstream fork relationship; product branding and the accepted payload profile are still ChatGPT Linux and ChatGPT.app-only. A later repository rename is a separate administrative change that must update and verify every clone/raw link atomically. The local working directory is then attached to the merged Git history without deleting its cached DMG or generated app.

## Repository Memory Layers

### Stable agent policy

`AGENTS.md` contains only durable rules:

- this mainline accepts `ChatGPT.app` payloads only;
- user-facing branding may be renamed, but internal `codex://`, `CODEX_*`, bundle, CLI, socket, and backend contracts are preserved unless separately proven replaceable;
- required patches fail closed, while optional patches are recorded as skipped;
- no broad replacement against minified assets without a versioned precondition;
- release contracts and `UPGRADING.md` must be read before an upgrade;
- `bash tests/run-all.sh` is mandatory before publication;
- no official DMG, ASAR, generated application, local absolute path, or credential is committed.

### Human and agent runbook

`UPGRADING.md` is the single upgrade workflow. It covers remote synchronization, versioned DMG acquisition, immutable evidence capture, payload inspection, patch classification, Electron ABI rebuild order, atomic installation, GUI verification, release-contract updates, and rollback. It also defines when a separate legacy profile is allowed instead of mixing Codex.app compatibility into the ChatGPT.app patch engine.

### Machine-readable release contracts

`compatibility/current.json` points to one file under `compatibility/releases/`. The current contract records:

- application profile, bundle ID, version, build, source macOS architecture, target Linux architecture, main entry, and exact Electron version;
- DMG source URL, observed size, SHA-256, and observation time;
- installer and pinned toolchain versions;
- original upstream and fork baseline commits;
- expected required paths;
- expected feature status and verification level;
- known release-specific observations, including renamed or absent hashed chunks.

It contains no machine-specific absolute paths. Generated `build-info.json` and the feature manifest remain per-install actual evidence rather than the durable expected contract.

### Executable memory

`tests/release-contract.test.mjs` validates the contract schema, current pointer, ChatGPT.app-only profile, exact release identifiers, allowed feature states, and absence of local paths. Existing tests continue to validate installer behavior and patch metadata.

`.github/workflows/test.yml` runs only `bash tests/run-all.sh`. It does not download or redistribute the official DMG. Full DMG and GUI verification remains a manual release gate on an authorized Linux machine.

## Upgrade Data Flow

1. Clone the writable repository and configure the original repository as `upstream`.
2. Fetch both remotes and record their exact heads before changing files.
3. Run the existing tests to establish a clean baseline.
4. Check the mutable official DMG endpoint without silently replacing a verified cached build.
5. Download a new candidate to a versioned temporary path and record HTTP metadata, size, and SHA-256.
6. Extract and audit `Info.plist`, Electron metadata, ASAR entrypoints, native dependencies, and feature surfaces.
7. Compare the candidate with the current release contract. Unknown required surfaces stop before the installed application is touched.
8. Update tests first, then the smallest compatible implementation.
9. Build into staging, validate Electron ABI and native modules, run a bounded GUI smoke test, and atomically switch the install only after success.
10. Update the release contract with observed evidence and honest capability levels, then publish through a reviewed branch.

## Feature Truthfulness

Feature states use `verified`, `partial`, `skipped`, `not-shipped`, or `unsupported`. A renderer gate, generated shim, or availability response alone cannot produce `verified`. Browser Use remains `partial` until a complete session performs an action and returns evidence. App Snapshot remains `skipped` for release `26.727.40816` because its legacy renderer chunks are absent. Mobile pairing, Chrome Control, and tray behavior remain no stronger than their actual runtime evidence.

## Failure and Rollback Rules

- Never mutate `main` or an installed application before the candidate passes source-level checks.
- Never resume into a cache whose remote identity or expected size changed.
- Never ignore a generic extraction, install, or rebuild error; only explicitly classified benign errors may be tolerated.
- Preserve the previous working install until the new GUI smoke test passes.
- Preserve the old GitHub mainline through the legacy tag and normal history.
- If a new ChatGPT.app cannot be supported, record it as unsupported and keep the last verified contract current. A Codex.app fallback, if ever revived, must be a separate profile and adapter.

## Acceptance Criteria

- The writable GitHub repository contains the current ChatGPT.app-only source and its prior history.
- The pre-migration fork head is reachable from `codex-legacy-2026-07-16`.
- `origin` points to the writable repository and `upstream` points to the original repository.
- Durable instructions, an upgrade runbook, a current release contract, contract tests, and CI are committed.
- The full local test suite passes in a clean clone.
- No DMG, generated app, local absolute path, secret, or proprietary extracted payload is committed.
- The local workspace gains Git metadata without losing its cached DMG or working generated application.
