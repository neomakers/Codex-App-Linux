import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const enginePath = new URL("../tools/patch-chatgpt-linux.mjs", import.meta.url);

test("exposes ChatGPT Linux patch-engine metadata while retaining internal Codex contracts", () => {
  const source = fs.readFileSync(enginePath, "utf8");

  assert.match(source, /Usage: patch-chatgpt-linux\.mjs <chatgpt-linux-output-dir>/);
  assert.match(source, /patchEngine: "tools\/patch-chatgpt-linux\.mjs"/);
  assert.match(source, /chatgpt-linux-feature-manifest\.json/);
  assert.doesNotMatch(source, /codex-linux-feature-manifest\.json/);
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
});

test("generates only release-contract feature statuses from a patched fixture", (t) => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "chatgpt-linux-patch-engine-"));
  const assetsDir = path.join(fixtureRoot, "webview", "assets");
  const buildDir = path.join(fixtureRoot, ".vite", "build");
  const pluginRoot = path.join(fixtureRoot, "chrome-plugin-source");
  const scriptsDir = path.join(pluginRoot, "scripts");

  t.after(() => fs.rmSync(fixtureRoot, { recursive: true, force: true }));
  fs.mkdirSync(assetsDir, { recursive: true });
  fs.mkdirSync(buildDir, { recursive: true });
  fs.mkdirSync(path.join(pluginRoot, ".codex-plugin"), { recursive: true });
  fs.mkdirSync(scriptsDir, { recursive: true });

  for (const asset of [
    "app-main-fixture.js",
    "remote-connections-settings-fixture.js",
    "remote-connection-visibility-fixture.js",
    "remote-control-connections-visibility-fixture.js",
    "codex-mobile-setup-flow-fixture.js",
    "use-in-app-browser-use-availability-fixture.js",
    "annotation-comment-editor-card-fixture.js",
    "composer-fixture.js",
  ]) {
    fs.writeFileSync(path.join(assetsDir, asset), "");
  }
  fs.writeFileSync(
    path.join(buildDir, "main-fixture.js"),
    "function wV({resourcesPath:e}){let t=null,n=()=>{if(process.platform!==`darwin`)throw Error(`Remote control device keys are only available on macOS`);if(e==null)throw Error(`Remote control device keys require resourcesPath`);return t??=bV((0,i.join)(e,`native`,xV)),t};return{createDeviceKey:e=>n().createDeviceKey(e??`hardware_only`),deleteDeviceKey:e=>n().deleteDeviceKey(e),getDeviceKeyPublic:e=>n().getDeviceKeyPublic(e),signDeviceKey:async(e,t)=>{let r=TV(t);return{...await n().signDeviceKey(e,r),signedPayloadBase64:r.toString(`base64`)}}}}",
  );
  fs.writeFileSync(path.join(pluginRoot, ".codex-plugin", "plugin.json"), "{}");
  for (const script of [
    "check-native-host-manifest.js",
    "chrome-is-running.js",
    "open-chrome-window.js",
  ]) {
    fs.writeFileSync(path.join(scriptsDir, script), "");
  }

  const result = spawnSync(process.execPath, [enginePath.pathname, fixtureRoot], {
    encoding: "utf8",
    env: { ...process.env, CODEX_CHROME_PLUGIN_SOURCE: pluginRoot },
  });

  assert.equal(result.status, 0, result.stderr);
  const manifest = JSON.parse(
    fs.readFileSync(path.join(fixtureRoot, "chatgpt-linux-feature-manifest.json"), "utf8"),
  );
  assert.equal(manifest.features.mobilePairingUi.status, "partial");
  assert.equal(manifest.features.mobilePairingBridge.status, "partial");
  assert.equal(manifest.features.chromeControl.status, "partial");
  assert.equal(
    manifest.patches.find(({ name }) => name === "Linux remote-control device-key provider")
      ?.status,
    "skipped",
  );
  assert.doesNotMatch(
    fs.readFileSync(path.join(buildDir, "main-fixture.js"), "utf8"),
    /os_protected_nonextractable|privateKeyPem|pkcs8/i,
  );
  for (const value of Object.values(manifest.features)) {
    assert.ok(["verified", "partial", "skipped", "not-shipped", "unsupported"].includes(value.status));
  }
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
