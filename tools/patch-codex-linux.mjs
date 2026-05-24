#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const root = process.argv[2];

if (!root) {
  throw new Error("Usage: patch-codex-linux.mjs <codex-linux-output-dir>");
}

const assetsDir = path.join(root, "webview", "assets");
const patches = [];
const warnings = [];

function findAsset(pattern) {
  const matches = fs.readdirSync(assetsDir).filter((name) => pattern.test(name));
  if (matches.length === 0) {
    throw new Error(`Could not find asset matching ${pattern}`);
  }
  return path.join(assetsDir, matches[0]);
}

function record(name, status, file) {
  patches.push({
    name,
    status,
    file: path.relative(root, file),
  });
}

function warn(message) {
  warnings.push(message);
  console.warn(message);
}

function replaceOptional(file, from, to, label) {
  const input = fs.readFileSync(file, "utf8");
  if (input.includes(to)) {
    console.log(`Already patched ${label} in ${path.basename(file)}`);
    record(label, "already-patched", file);
    return;
  }
  if (!input.includes(from)) {
    warn(`Skipping ${label}; expected snippet not found in ${path.basename(file)}`);
    record(label, "skipped", file);
    return;
  }
  fs.writeFileSync(file, input.replace(from, to));
  console.log(`Patched ${label} in ${path.basename(file)}`);
  record(label, "patched", file);
}

function patchMobilePairingUi() {
  const appMain = findAsset(/^app-main-.*\.js$/);
  const remoteConnections = findAsset(/^remote-connections-settings-.*\.js$/);

  replaceOptional(
    appMain,
    "i=Pl(),a=Is(`2798711298`)",
    "i=!0,a=!0",
    "Codex Mobile announcement feature gate",
  );

  replaceOptional(
    appMain,
    "remoteControlFeaturesVisible:Pl(),remoteControlOnboardingEnabled:Is(`2798711298`)",
    "remoteControlFeaturesVisible:!0,remoteControlOnboardingEnabled:!0",
    "Codex Mobile sidebar feature gate",
  );

  replaceOptional(
    remoteConnections,
    "if(r)return null;if(!n){let t;",
    "if(r)return null;{let t;",
    "Connections tab mobile setup visibility",
  );
}

function writeManifest() {
  const manifest = {
    generatedAt: new Date().toISOString(),
    patchEngine: "tools/patch-codex-linux.mjs",
    features: {
      mobilePairingUi: {
        status: "patched-experimental",
        evidence: "Renderer feature gates for Codex Mobile pairing UI are patched.",
      },
    },
    patches,
    warnings,
  };

  fs.writeFileSync(
    path.join(root, "codex-linux-feature-manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
}

patchMobilePairingUi();
writeManifest();
