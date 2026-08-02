# Upgrading a ChatGPT.app Release

This is the canonical procedure for taking a newer official macOS DMG into the Linux rebuild. [compatibility/current.json](compatibility/current.json) selects the current immutable evidence under [compatibility/releases](compatibility/releases). A successful download, renderer gate, or old reverse-engineering document is not compatibility proof.

## Boundaries

- This mainline accepts only `ChatGPT.app`; reject any other payload.
- Preserve `codex://`, `CODEX_*`, `com.openai.codex`, CLI, socket, backend, and native-host contracts unless compatible replacement is evidenced and verified.
- A future `Codex.app` fallback needs a separate profile, adapter, output name, cache identity, and test surface. It must not share the ChatGPT.app patch engine.
- Do not commit DMGs, extracted payloads, generated applications, credentials, or machine-local paths.
- Do not update the current pointer until a candidate has completed the audit, build, and smoke gates. Record unsupported candidates without replacing the last verified contract.

## 1. Fetch and record a baseline

Use a clean checkout of the writable ChatGPT project. Configure the original repository as `upstream` for provenance and selective review, never as a blind merge target.

```bash
if git remote get-url upstream >/dev/null 2>&1; then
  git remote set-url upstream https://github.com/areu01or00/Codex-App-Linux.git
else
  git remote add upstream https://github.com/areu01or00/Codex-App-Linux.git
fi
git fetch origin --prune
git fetch upstream --prune
git status --short --branch
git rev-parse origin/main upstream/main
git show --no-patch --format=fuller origin/main
git show --no-patch --format=fuller upstream/main
git show HEAD:compatibility/current.json
bash tests/run-all.sh
git switch -c upgrade/chatgpt-<version>-<build>
```

Record the two remote heads, starting branch/commit, selected contract, and full-suite result in the candidate evidence. Stop if the checkout is dirty or the suite fails. Review upstream changes against the contract; do not merge merely because filenames match.

## 2. Acquire immutable candidate evidence

The official endpoint is mutable. Reuse a cached DMG only when its remote identity and expected size match, `7z t` succeeds, and its SHA-256 is already recorded. Identity means requested and final URLs, redirect chain, HTTP status, `ETag`, `Last-Modified`, `Content-Length`, observation time, and SHA-256.

Download each investigated release to a versioned candidate path outside Git or under an ignored work directory. Never overwrite a complete prior release and never resume a partial file if its URL identity or expected size changed. Preserve the old file and evidence; start a different candidate instead.

```bash
work_dir="$(mktemp -d)"
candidate="$work_dir/ChatGPT-<version>-<build>.dmg"
url='https://persistent.oaistatic.com/codex-app-prod/Codex.dmg'
curl --fail --show-error --location --head "$url" >"$work_dir/http-headers.txt"
curl --fail --show-error --location --continue-at - --output "$candidate" "$url"
sha256sum "$candidate" >"$work_dir/sha256.txt"
7z t "$candidate" >"$work_dir/7z-test.txt"
```

Capture redirect/final-URL metadata when the HTTP client does not include it in the headers file. A changed identity, incomplete transfer, or failed integrity check is a stop condition. The installer convenience cache may be reused only for a known identity; the upgrade investigation retains versioned evidence first.

## 3. Extract and audit before editing

Extract into the work directory and compare the candidate with the selected contract. Confirm `ChatGPT.app`, required paths, version/build, bundle ID, Electron version, main entry, native dependencies, bundled plugins, and hashed renderer/main assets. Keep the `Info.plist`, ASAR listing, inventories, and plugin/native-module observations with the candidate evidence.

```bash
extract_dir="$work_dir/extracted"
7z x "$candidate" "-o$extract_dir" -y
find "$extract_dir" -type d -name ChatGPT.app -print
find "$extract_dir" -type d -name Codex.app -print
```

Audit every named feature surface: Browser Use, mobile pairing, App Snapshot, Chrome Control, `node_repl`, native-host assets, and callback handling. Renamed or missing chunks are an explicit compatibility decision: absent required paths or patches stop the upgrade; optional patches are recorded as `skipped` with their observed reason. Do not edit minified assets without a release-specific precondition identifying the exact file and expected surrounding code. A broad replacement, filename guess, or UI-only gate is invalid.

## 4. Test first, then apply the smallest patch

Update deterministic release-contract and implementation tests before changing the installer, generator, or patcher. Do not add source-grep tests for policy prose. Classify every patch:

- **Required:** stop with a clear error if its precondition is absent or it cannot apply.
- **Optional:** continue only after the feature manifest records `skipped` and why.
- **Unsupported:** retain evidence and keep the last verified release current.

Preserve internal Codex contracts behind the ChatGPT Linux name. A visible setting, availability response, or generated shim is only `partial` until the full runtime action is observed and recorded.

## 5. Rebuild for the candidate Electron ABI

Use a fresh output for candidate validation. Dependencies must be synthesized for the candidate, native install scripts must not run prematurely, and `@electron/rebuild` must run after the exact candidate Electron runtime is selected. Do not use the system Node ABI or a previous `node_modules` directory.

```bash
output_dir="$work_dir/chatgpt-linux-<version>-<build>"
./install-chatgpt-linux.sh --dmg "$candidate" --output "$output_dir"
```

Confirm generated build information records the candidate hash, version/build, Electron version, and native rebuild result. Extraction, dependency, ABI, or required-patch failure stops promotion; preserve evidence instead of accepting a partial build.

## 6. Stage, smoke test, and atomically promote

The installer must build in staging and retain the previous working output until validation succeeds. Test the new output first. Record a bounded GUI smoke result that covers:

1. Application launch without an Electron ABI or native-module error.
2. Desktop entry and preserved `codex://` callback handling.
3. Generated feature manifest against contract evidence.
4. Each required changed surface and failure mode; each optional surface as evidence or `skipped`.
5. One restart without reinstalling.

Only after this smoke test may a known-good output be atomically replaced. On failure, retain the prior output and mark the candidate incomplete or unsupported.

## 7. Update the contract and publish through review

After honest build and GUI evidence, add a new immutable JSON file under `compatibility/releases/` containing release identifiers, DMG identity/hash, toolchain versions, required paths, observations, and feature status/verification. Then point `compatibility/current.json` to it; never rewrite an existing release evidence file.

Use only contract-approved feature statuses and verification levels. `verified` requires the full claimed runtime behavior, not an installer run or a renderer gate. Before publication, review for stale instructions, machine-local paths, proprietary payloads, credentials, and unsupported claims, then run:

```bash
bash tests/run-all.sh
git diff --check
git status --short
```

Commit tests, implementation, evidence, and necessary docs on the upgrade branch. Push without force, open a pull request to `main` with the evidence and GUI smoke result, and merge only after review and passing checks.

## Rollback

On any failure, leave the current pointer and last working application unchanged. Keep candidate identity and failure evidence, restore the previous output if promotion was interrupted, and begin a later investigation as a new candidate with a new identity record.
