# Repository Memory and Upstream Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the verified ChatGPT.app-only rebuild to the writable GitHub fork while preserving history and adding executable upgrade memory.

**Architecture:** Keep the existing fork ancestry, tag the last Codex.app state, import the current source through a normal feature branch, and merge without force-pushing. Store durable policy in `AGENTS.md`, the upgrade procedure in `UPGRADING.md`, expected release evidence in versioned JSON contracts, and enforcement in tests plus a minimal GitHub Actions workflow.

**Tech Stack:** Bash, Node.js built-in test runner, JSON, Git, GitHub Actions, GitHub pull requests.

## Global Constraints

- Mainline accepts only the `ChatGPT.app` payload profile.
- Preserve internal `codex://`, `CODEX_*`, CLI, backend, bundle, socket, and native-host contracts unless replacement is separately proven.
- Never commit a DMG, ASAR, generated application, local absolute path, credential, or proprietary extracted resource.
- Never force-push the migration.
- Required patches fail closed; optional patches are explicitly skipped and recorded.
- The full `bash tests/run-all.sh` suite must pass before publication.
- The original fork head `dc7e365c5de6649ed11df467e5ebc9d78a473543` must remain reachable from tag `codex-legacy-2026-07-16`.

---

### Task 1: Add the executable release contract

**Files:**
- Create: `tests/release-contract.test.mjs`
- Create: `compatibility/current.json`
- Create: `compatibility/releases/26.727.40816-6067.json`

**Interfaces:**
- Consumes: repository-relative JSON files and Node's `node:test`, `assert`, `fs`, and `path` modules.
- Produces: a validated current release pointer and immutable expected evidence for ChatGPT `26.727.40816` build `6067`.

- [ ] **Step 1: Write the failing contract test**

The test must resolve `compatibility/current.json`, reject absolute or escaping pointers, load the selected release, require `schemaVersion: 1`, `profile: "chatgpt-app-only"`, preserved internal bundle ID `com.openai.codex`, exact version/build/Electron/main entry values, a 64-character lowercase DMG hash, allowed feature status and verification enums, and no `/home/`, `/Users/`, or Windows drive path anywhere in serialized JSON.

```js
const allowedStatus = new Set(["verified", "partial", "skipped", "not-shipped", "unsupported"]);
const allowedVerification = new Set(["end-to-end", "gui-smoke", "availability-smoke", "build-only", "not-tested"]);
assert.equal(release.application.profile, "chatgpt-app-only");
assert.equal(release.application.version, "26.727.40816");
assert.match(release.dmg.sha256, /^[0-9a-f]{64}$/);
for (const feature of Object.values(release.features)) {
  assert.ok(allowedStatus.has(feature.status));
  assert.ok(allowedVerification.has(feature.verification));
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/release-contract.test.mjs`

Expected: FAIL because `compatibility/current.json` does not exist.

- [ ] **Step 3: Add the current pointer and release evidence**

`compatibility/current.json` points to `releases/26.727.40816-6067.json`. The release file records the exact application, DMG, toolchain, repository baselines, required paths, release observations, and honest feature levels. Browser Use is `partial/availability-smoke`; App Snapshot is `skipped/not-tested`; no experimental surface is marked verified.

- [ ] **Step 4: Run the contract and full suites**

Run: `node --test tests/release-contract.test.mjs && bash tests/run-all.sh`

Expected: all tests pass.

### Task 2: Add durable repository instructions and upgrade workflow

**Files:**
- Create: `AGENTS.md`
- Create: `UPGRADING.md`
- Modify: `.gitignore`
- Modify: `README.md`
- Modify: `Reverse-engineering-guide-index.md`
- Modify: `Reverse-engineering-guide.md`
- Modify: `Browser_Use_Port_Contract.md`
- Modify: `Chrome_Control_Port_Contract.md`
- Modify: `App_Snapshot_Computer_Use_Port_Contract.md`
- Modify: `Porting_Surface_Plan.md`

**Interfaces:**
- Consumes: the design spec and release contract from Task 1.
- Produces: one stable policy entrypoint, one canonical upgrade runbook, and clearly marked historical documents.

- [ ] **Step 1: Write the policy and runbook**

Keep `AGENTS.md` short and normative. Put the full fetch → evidence → audit → TDD → ABI rebuild → staged install → GUI smoke → release contract → branch/PR sequence in `UPGRADING.md`, including cache identity rules and the separate-profile requirement for any future Codex.app fallback.

- [ ] **Step 2: Mark old contracts as historical evidence**

Add a banner to the legacy reverse-engineering and feature-contract documents saying their observed Codex.app release and filenames are historical, while `UPGRADING.md` plus `compatibility/current.json` own current truth.

- [ ] **Step 3: Update repository links and ignore local agent artifacts**

Point README clone/raw links at the writable ChatGPT project name, add links to the runbook and compatibility contract, and ignore `.superpowers/` while continuing to ignore DMGs and generated applications.

- [ ] **Step 4: Review documentation and verify repository links**

Read the changed documentation as rendered Markdown, verify every repository-relative link target exists, confirm no current instructions point at retired installer paths, and run `bash tests/run-all.sh`. Human/agent prose does not gain source-grep tests; its value is enforced through the canonical ownership rules and executable release contract.

Expected: documentation is internally consistent, link targets exist, and all tests pass.

### Task 3: Make generated feature claims match evidence

**Files:**
- Modify: `tests/patch-engine-metadata.test.mjs`
- Modify: `tools/patch-chatgpt-linux.mjs`

**Interfaces:**
- Consumes: patch results already collected by the patch engine.
- Produces: generated feature statuses no stronger than the current release contract.

- [ ] **Step 1: Add failing metadata assertions**

```js
assert.doesNotMatch(source, /mobilePairingUi:\s*\{\s*status:\s*"patched-experimental"/s);
assert.doesNotMatch(source, /chromeControl:\s*\{\s*status:\s*"patched-experimental"/s);
assert.match(source, /mobilePairingUi:\s*\{\s*status:\s*"partial"/s);
assert.match(source, /chromeControl:\s*\{\s*status:\s*"partial"/s);
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `node --test tests/patch-engine-metadata.test.mjs`

Expected: FAIL because both features currently overstate patch completion.

- [ ] **Step 3: Lower claims to `partial` and state the caveats**

Change only the two generated feature summaries. Preserve individual patch records and all internal Codex identifiers.

- [ ] **Step 4: Run focused and full tests**

Run: `node --test tests/patch-engine-metadata.test.mjs && bash tests/run-all.sh`

Expected: all tests pass.

### Task 4: Add the CI gate

**Files:**
- Create: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: the repository's existing `tests/run-all.sh` entrypoint.
- Produces: a GitHub Actions check for pushes and pull requests without downloading the official DMG.

- [ ] **Step 1: Add the workflow**

```yaml
name: test
on:
  push:
  pull_request:
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "22.23.2"
      - run: bash tests/run-all.sh
```

- [ ] **Step 2: Validate workflow scope**

Run: `rg -n 'bash tests/run-all.sh|node-version: "22.23.2"' .github/workflows/test.yml` and `! rg -n 'Codex\.dmg|ChatGPT-latest\.dmg|curl.+oaistatic' .github/workflows/test.yml`.

Expected: the test entrypoint and pinned Node are present; no DMG acquisition appears.

### Task 5: Import, publish, merge, and attach local history

**Files:**
- Remove from new mainline: `install-codex-linux.sh`, `tools/patch-codex-linux.mjs`, `packaging/debian/**`
- Import: all current tracked-source candidates except ignored binaries, generated output, `.superpowers/`, and local logs.

**Interfaces:**
- Consumes: writable fork `neomakers/Codex-App-Linux` and original upstream `areu01or00/Codex-App-Linux`.
- Produces: a merged history-preserving ChatGPT.app branch, legacy tag, correctly configured remotes, and a Git-backed local workspace.

- [ ] **Step 1: Create an isolated publication clone**

Clone the writable fork into a `mktemp -d` directory, add `upstream`, fetch both remotes, and assert `origin/main` is exactly `dc7e365c5de6649ed11df467e5ebc9d78a473543` before mutation.

- [ ] **Step 2: Preserve the old mainline**

Create annotated tag `codex-legacy-2026-07-16` at the asserted fork head and push the tag. If the tag already exists, require it to resolve to the same commit.

- [ ] **Step 3: Import through a normal branch**

Create `agent/chatgpt-app-rebuild-2026-08-02` from `origin/main`, remove the old tracked tree inside the isolated clone, bulk-copy only the current source candidates, and verify that no ignored artifact or absolute local path is staged.

- [ ] **Step 4: Test and commit**

Run `bash tests/run-all.sh`, inspect `git diff --check`, commit the migration, and push the feature branch without force.

- [ ] **Step 5: Open and merge a pull request**

Open a PR to `main` describing the ChatGPT.app-only migration, durable repository memory, release evidence, and verification. Merge only after tests pass. Preserve branch history through a regular merge or squash supported by the repository.

- [ ] **Step 6: Rename the writable repository when available**

Rename `neomakers/Codex-App-Linux` to `neomakers/ChatGPT-App-Linux` only after the merge. Verify the new URL and GitHub redirect before changing local links.

- [ ] **Step 7: Attach the current workspace non-destructively**

Initialize Git metadata in the current directory, fetch the merged origin, point local `main` at the fetched commit, populate only the index from `HEAD`, configure `upstream`, and confirm `git status` is clean apart from ignored DMG/generated output. Do not check out over or delete the working application.

- [ ] **Step 8: Final verification**

Run `bash tests/run-all.sh`, `git status --short --branch`, `git remote -v`, `git tag --list codex-legacy-2026-07-16`, and repository secret/binary scans.

Expected: tests pass, the source tree is clean, origin/upstream are correct, the legacy tag exists, and generated artifacts remain ignored locally.
