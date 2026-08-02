import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import test from "node:test";

const enginePath = new URL("../tools/patch-chatgpt-linux.mjs", import.meta.url);

test("exposes ChatGPT Linux patch-engine metadata while retaining internal Codex contracts", () => {
  const source = fs.readFileSync(enginePath, "utf8");

  assert.match(source, /Usage: patch-chatgpt-linux\.mjs <chatgpt-linux-output-dir>/);
  assert.match(source, /patchEngine: "tools\/patch-chatgpt-linux\.mjs"/);
  assert.match(source, /chatgpt-linux-feature-manifest\.json/);
  assert.doesNotMatch(source, /codex-linux-feature-manifest\.json/);
  assert.match(source, /\.config.*chatgpt-linux/);

  assert.match(source, /CODEX_BROWSER_USE_PIPE_DIR/);
  assert.match(source, /Codex Mobile/);
  assert.match(source, /codex-browser-use/);
  assert.match(source, /NativeMessagingHosts/);
});

test("prints the ChatGPT Linux usage contract when the output directory is missing", () => {
  const result = spawnSync(process.execPath, [enginePath.pathname], {
    encoding: "utf8",
  });

  assert.notEqual(result.status, 0);
  assert.match(
    `${result.stdout}${result.stderr}`,
    /Usage: patch-chatgpt-linux\.mjs <chatgpt-linux-output-dir>/,
  );
});

test("treats the versioned Browser Use availability chunk as optional", () => {
  const source = fs.readFileSync(enginePath, "utf8");

  assert.match(
    source,
    /const browserUseAvailability = findAssetOptional\(\/\^use-in-app-browser-use-availability-/,
  );
  assert.doesNotMatch(
    source,
    /const browserUseAvailability = findAsset\(\/\^use-in-app-browser-use-availability-/,
  );
  assert.match(source, /if \(browserUseAvailability\) \{/);
  assert.match(source, /Browser Use renderer availability chunk was not present/);
  assert.match(source, /status: browserUseAvailability \? "patched-experimental" : "partial"/);
});

test("skips the experimental app snapshot when its renderer chunks are absent", () => {
  const source = fs.readFileSync(enginePath, "utf8");

  assert.match(source, /const annotationEditor = findAssetOptional\(/);
  assert.match(source, /const composer = findAssetOptional\(/);
  assert.doesNotMatch(source, /const annotationEditor = findAsset\(/);
  assert.doesNotMatch(source, /const composer = findAsset\(/);
  assert.match(source, /if \(!annotationEditor \|\| !composer\) \{/);
  assert.match(source, /feature\("appSnapshotScreenshot", "skipped"/);
});
