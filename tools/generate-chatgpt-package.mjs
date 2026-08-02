#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const excludedDependencies = new Set([
  "app-server-types",
  "browser-api",
  "browser-backend-common",
  "browser-common",
  "commands",
  "external-agent-migration",
  "protocol",
  "shared-node",
  "electron-liquid-glass",
  "objc-js",
]);

const localDependencyPrefixes = ["file:", "link:", "workspace:"];
const exactVersionPattern =
  /^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

export function buildLinuxPackage(sourcePackage, appVersion) {
  if (typeof sourcePackage?.main !== "string" || sourcePackage.main.trim() === "") {
    throw new Error("Source package is missing its main entry");
  }

  const electronVersion = sourcePackage?.devDependencies?.electron;
  if (
    typeof electronVersion !== "string" ||
    !exactVersionPattern.test(electronVersion)
  ) {
    throw new Error("Source package must declare an exact Electron version");
  }

  const dependencies = Object.fromEntries(
    Object.entries(sourcePackage.dependencies ?? {}).filter(
      ([name, version]) =>
        !excludedDependencies.has(name) &&
        !(
          typeof version === "string" &&
          localDependencyPrefixes.some((prefix) => version.startsWith(prefix))
        ),
    ),
  );

  return {
    name: "chatgpt-linux",
    productName: "ChatGPT Linux",
    version: `${appVersion}-linux`,
    description: "ChatGPT for Linux (unofficial port)",
    main: sourcePackage.main,
    scripts: {
      start: "electron .",
      "start:debug": "electron . --enable-logging",
    },
    dependencies,
    devDependencies: {
      electron: electronVersion,
      "@electron/rebuild": "4.0.3",
    },
  };
}

function runCli([sourcePath, outputPath, appVersion]) {
  if (!sourcePath || !outputPath || !appVersion) {
    throw new Error(
      "Usage: generate-chatgpt-package.mjs SOURCE_PACKAGE OUTPUT_PACKAGE APP_VERSION",
    );
  }

  const sourcePackage = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
  const linuxPackage = buildLinuxPackage(sourcePackage, appVersion);
  fs.writeFileSync(outputPath, `${JSON.stringify(linuxPackage, null, 2)}\n`);
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  runCli(process.argv.slice(2));
}
