import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const compatibilityRoot = path.join(repositoryRoot, "compatibility");
const currentPath = path.join(compatibilityRoot, "current.json");
const allowedStatus = new Set(["verified", "partial", "skipped", "not-shipped", "unsupported"]);
const allowedVerification = new Set([
  "end-to-end",
  "gui-smoke",
  "availability-smoke",
  "build-only",
  "not-tested",
]);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function isPortableRelativePointer(pointer) {
  return (
    typeof pointer === "string" &&
    !path.isAbsolute(pointer) &&
    !/^(?:[\\/]|[A-Za-z]:[\\/])/.test(pointer)
  );
}

test("release pointers reject rooted paths on every host platform", () => {
  for (const pointer of [
    "/releases/current.json",
    "\\\\server\\share",
    "C:\\releases\\current.json",
    "C:/releases/current.json",
  ]) {
    assert.equal(isPortableRelativePointer(pointer), false, pointer);
  }
});

test("current release contract is a portable, pinned ChatGPT.app-only evidence record", () => {
  const current = readJson(currentPath);
  assert.equal(typeof current.release, "string");
  assert.equal(current.release, "releases/26.727.40816-6067.json");
  assert.ok(isPortableRelativePointer(current.release), "release pointer must be relative");

  const releasePath = path.resolve(compatibilityRoot, current.release);
  assert.ok(
    releasePath.startsWith(`${compatibilityRoot}${path.sep}`),
    "release pointer must not escape compatibility/",
  );

  const release = readJson(releasePath);
  assert.equal(release.schemaVersion, 1);
  assert.equal(release.application.profile, "chatgpt-app-only");
  assert.equal(release.application.bundleId, "com.openai.codex");
  assert.equal(release.application.version, "26.727.40816");
  assert.equal(release.application.build, "6067");
  assert.equal(release.application.architecture, "x64");
  assert.equal(release.application.electronVersion, "42.3.0");
  assert.equal(release.application.mainEntry, ".vite/build/early-bootstrap.js");
  assert.equal(release.dmg.observedBytes, 609303023);
  assert.match(release.dmg.sha256, /^[0-9a-f]{64}$/);
  assert.equal(release.dmg.sha256, "fb93a239c811c7639cf45a90ff36c262fa0290640140cd12da3fdc60b62255ae");

  assert.equal(release.toolchain.node.version, "22.23.2");
  assert.equal(release.toolchain.asar.version, "4.2.1");
  assert.equal(release.toolchain.electronRebuild.version, "4.0.3");
  assert.equal(release.repository.upstream.commit, "27371c24b143b1901a5c8c4059dd396ab34bc262");
  assert.equal(release.repository.fork.commit, "dc7e365c5de6649ed11df467e5ebc9d78a473543");
  assert.deepEqual(release.requiredPaths, [
    "ChatGPT.app/Contents/Info.plist",
    "ChatGPT.app/Contents/Resources/app.asar",
    "ChatGPT.app/Contents/Resources/app.asar.unpacked",
    "ChatGPT.app/Contents/Resources/plugins",
  ]);

  assert.equal(release.features.browserUse.status, "partial");
  assert.equal(release.features.browserUse.verification, "availability-smoke");
  assert.equal(release.features.appSnapshot.status, "skipped");
  assert.equal(release.features.appSnapshot.verification, "not-tested");
  for (const feature of Object.values(release.features)) {
    assert.ok(allowedStatus.has(feature.status));
    assert.ok(allowedVerification.has(feature.verification));
  }
  for (const featureName of ["mobilePairing", "browserUse", "appSnapshot", "chromeControl"]) {
    assert.notEqual(release.features[featureName].status, "verified");
  }

  assert.doesNotMatch(
    JSON.stringify(release),
    /\/home\/|\/Users\/|(?:^|[^A-Za-z])[A-Za-z]:[\\/]/,
  );
});
