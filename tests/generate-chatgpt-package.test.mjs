import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { buildLinuxPackage } from "../tools/generate-chatgpt-package.mjs";

const generatorPath = new URL("../tools/generate-chatgpt-package.mjs", import.meta.url);

function currentSourcePackage(overrides = {}) {
  return {
    main: ".vite/build/early-bootstrap.js",
    dependencies: {
      "better-sqlite3": "^12.9.0",
      "objc-js": "1.5.0",
      "app-server-types": "workspace:*",
      "browser-api": "file:../../../lib/browser-api",
      "browser-backend-common": "1.0.0",
      "browser-common": "link:../../../lib/browser-common",
      commands: "1.0.0",
      "external-agent-migration": "1.0.0",
      protocol: "1.0.0",
      "shared-node": "1.0.0",
      "electron-liquid-glass": "1.0.0",
      "another-workspace-package": "workspace:^",
      "another-file-package": "file:../another-file-package",
      "another-link-package": "link:../another-link-package",
      ws: "^8.21.1",
    },
    devDependencies: { electron: "42.3.0" },
    ...overrides,
  };
}

test("generates ChatGPT Linux metadata for Electron 42 and removes non-installable dependencies", () => {
  const result = buildLinuxPackage(currentSourcePackage(), "26.727.40816");

  assert.deepEqual(result, {
    name: "chatgpt-linux",
    productName: "ChatGPT Linux",
    version: "26.727.40816-linux",
    description: "ChatGPT for Linux (unofficial port)",
    main: ".vite/build/early-bootstrap.js",
    scripts: {
      start: "electron .",
      "start:debug": "electron . --enable-logging",
    },
    dependencies: {
      "better-sqlite3": "^12.9.0",
      ws: "^8.21.1",
    },
    devDependencies: {
      electron: "42.3.0",
      "@electron/rebuild": "4.0.3",
    },
  });
});

test("rejects a source package without a main entry", () => {
  assert.throws(
    () => buildLinuxPackage(currentSourcePackage({ main: "" }), "26.727.40816"),
    /main entry/i,
  );
});

test("rejects missing or non-exact Electron versions", () => {
  for (const electron of [undefined, "", "^42.3.0", "~42.3.0", "latest"]) {
    assert.throws(
      () =>
        buildLinuxPackage(
          currentSourcePackage({ devDependencies: { electron } }),
          "26.727.40816",
        ),
      /exact Electron version/i,
    );
  }
});

test("CLI reads the source package and writes generated metadata", (t) => {
  const temporaryDirectory = fs.mkdtempSync(
    path.join(os.tmpdir(), "generate-chatgpt-package-"),
  );
  t.after(() => fs.rmSync(temporaryDirectory, { recursive: true, force: true }));

  const sourcePath = path.join(temporaryDirectory, "source-package.json");
  const outputPath = path.join(temporaryDirectory, "package.json");
  fs.writeFileSync(
    sourcePath,
    JSON.stringify(
      currentSourcePackage({
        dependencies: {
          "better-sqlite3": "^12.9.0",
          "objc-js": "1.5.0",
          ws: "^8.21.1",
        },
      }),
    ),
  );

  const result = spawnSync(
    process.execPath,
    [generatorPath.pathname, sourcePath, outputPath, "26.727.40816"],
    { encoding: "utf8" },
  );

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(fs.readFileSync(outputPath, "utf8")), {
    name: "chatgpt-linux",
    productName: "ChatGPT Linux",
    version: "26.727.40816-linux",
    description: "ChatGPT for Linux (unofficial port)",
    main: ".vite/build/early-bootstrap.js",
    scripts: {
      start: "electron .",
      "start:debug": "electron . --enable-logging",
    },
    dependencies: {
      "better-sqlite3": "^12.9.0",
      ws: "^8.21.1",
    },
    devDependencies: {
      electron: "42.3.0",
      "@electron/rebuild": "4.0.3",
    },
  });
});
