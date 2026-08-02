#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const root = process.argv[2];

if (!root) {
  throw new Error("Usage: patch-chatgpt-linux.mjs <chatgpt-linux-output-dir>");
}

const assetsDir = path.join(root, "webview", "assets");
const buildDir = path.join(root, ".vite", "build");
const patches = [];
const warnings = [];
const features = {
  mobilePairingUi: {
    status: "partial",
    evidence: "Renderer feature gates for Codex Mobile pairing UI are patched.",
  },
};

function findAsset(pattern) {
  const matches = fs.readdirSync(assetsDir).filter((name) => pattern.test(name));
  if (matches.length === 0) {
    throw new Error(`Could not find asset matching ${pattern}`);
  }
  return path.join(assetsDir, matches[0]);
}

function findAssetOptional(pattern) {
  const matches = fs.readdirSync(assetsDir).filter((name) => pattern.test(name));
  return matches.length === 0 ? null : path.join(assetsDir, matches[0]);
}

function findBuildAsset(pattern) {
  const matches = fs.readdirSync(buildDir).filter((name) => pattern.test(name));
  if (matches.length === 0) {
    throw new Error(`Could not find build asset matching ${pattern}`);
  }
  return path.join(buildDir, matches[0]);
}

function feature(name, status, details = {}) {
  features[name] = { status, ...details };
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

function replaceAllOptional(file, from, to, label) {
  const input = fs.readFileSync(file, "utf8");
  if (input.includes(to)) {
    console.log(`Already patched ${label} in ${path.basename(file)}`);
    record(label, "already-patched", file);
    return true;
  }
  if (!input.includes(from)) {
    record(label, "skipped", file);
    return false;
  }
  fs.writeFileSync(file, input.split(from).join(to));
  console.log(`Patched ${label} in ${path.basename(file)}`);
  record(label, "patched", file);
  return true;
}

function replaceRegexOptional(file, regex, to, label) {
  const input = fs.readFileSync(file, "utf8");
  if (input.includes(to)) {
    console.log(`Already patched ${label} in ${path.basename(file)}`);
    record(label, "already-patched", file);
    return true;
  }
  if (!regex.test(input)) {
    warn(`Skipping ${label}; expected pattern not found in ${path.basename(file)}`);
    record(label, "skipped", file);
    return false;
  }
  fs.writeFileSync(file, input.replace(regex, to));
  console.log(`Patched ${label} in ${path.basename(file)}`);
  record(label, "patched", file);
  return true;
}

function writeExecutable(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  fs.chmodSync(file, 0o755);
}

function copyDirectory(src, dst) {
  fs.rmSync(dst, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.cpSync(src, dst, { recursive: true, force: true });
}

function patchMobilePairingUi() {
  const appMain = findAsset(/^app-main-.*\.js$/);
  const remoteConnections = findAsset(/^remote-connections-settings-.*\.js$/);
  const remoteConnectionVisibility = findAssetOptional(/^remote-connection-visibility-.*\.js$/);
  const remoteControlConnectionsVisibility = findAssetOptional(/^remote-control-connections-visibility-.*\.js$/);
  const codexMobileSetup = findAssetOptional(/^codex-mobile-setup-flow-.*\.js$/);

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

  replaceAllOptional(remoteConnections, "Keep this Mac awake", "Keep this computer awake", "Linux remote awake copy");
  replaceAllOptional(remoteConnections, "Control this Mac", "Control this computer", "Linux remote-control tab copy");
  replaceAllOptional(remoteConnections, "Devices you can control from this Mac", "Devices you can control from this computer", "Linux remote device header copy");
  replaceAllOptional(remoteConnections, "SSH connections from this Mac", "SSH connections from this computer", "Linux SSH header copy");

  if (codexMobileSetup) {
    replaceAllOptional(codexMobileSetup, "Keep this Mac awake", "Keep this computer awake", "Linux Codex Mobile awake copy");
    replaceOptional(
      codexMobileSetup,
      "function cn({remoteControlHostEnabled:e,hasEnrolledRemoteControlClient:t}){return e?t?`connected`:`waiting`:`initial`}",
      "function cn({remoteControlHostEnabled:e,hasEnrolledRemoteControlClient:t}){return e?t?`connected`:`allow-host`:`initial`}",
      "Linux Codex Mobile setup avoids QR-only half-enabled state",
    );
    replaceOptional(
      codexMobileSetup,
      "z=async()=>{let e=await Ce();return await l.mutateAsync({featureName:te,enabled:!0}),e?`connected`:`waiting`}",
      "z=async()=>{let e=await Ce();return e?`connected`:(await l.mutateAsync({featureName:te,enabled:!0}),await Ce()?`connected`:`waiting`)}",
      "Linux Codex Mobile enrollment recheck after authorization",
    );
  }

  replaceOptional(
    remoteConnections,
    "fe=ce(),pe=c==null",
    "fe=!0,pe=c==null",
    "Remote connections parent visibility gate",
  );

  if (remoteConnectionVisibility) {
    replaceOptional(
      remoteConnectionVisibility,
      "function d(){let e=(0,u.c)(3),{data:i}=n(s,r(t)),a=c(`4114442250`);if(i?.config[`features.remote_connections`]===!0)return!0;let o=i?.config.features;if(typeof o!=`object`||!o||Array.isArray(o))return a;let l;return e[0]!==o||e[1]!==a?(l=Object.getOwnPropertyDescriptor(o,`remote_connections`)?.value===!0||a,e[0]=o,e[1]=a,e[2]=l):l=e[2],l}",
      "function d(){return !0}",
      "Remote connections settings visibility gate",
    );
  }

  if (remoteControlConnectionsVisibility) {
    replaceOptional(
      remoteControlConnectionsVisibility,
      "function a({remoteControlConnectionsState:e,slingshotEnabled:t}){return t&&(e?.available??!0)&&e?.accessRequired!==!0}",
      "function a({remoteControlConnectionsState:e,slingshotEnabled:t}){return (e?.available??!0)&&e?.accessRequired!==!0}",
      "Remote-control connections settings visibility gate",
    );
  }

  feature("mobilePairingUi", "partial", {
    evidence: "Renderer feature gates, remote settings visibility gates, and Linux-neutral copy are patched.",
    warning: "UI visibility alone is not proof of mobile pairing.",
  });
}

function patchLinuxRemoteControlBridge() {
  const mainProcess = findBuildAsset(/^main-.*\.js$/);
  const linuxRemoteControlHostConfig = "(()=>{let __s=e=>{let t=e.split(/\\r?\\n/),n=[],r=!1,i=!1,a=!1;for(let e of t){if(/^\\s*\\[.*\\]\\s*$/.test(e)){r&&!a&&(n.push(`remote_control = true`),a=!0),r=/^\\s*\\[features\\]\\s*$/.test(e),i=i||r,n.push(e);continue}if(/^\\s*remote_control\\s*=/.test(e)){r&&!a&&(n.push(`remote_control = true`),a=!0);continue}n.push(e)}return r&&!a&&n.push(`remote_control = true`),i||n.unshift(`[features]`,`remote_control = true`,``),n.join(`\\n`).replace(/\\n*$/,`\\n`)};try{let e=process.getBuiltinModule(`fs`),t=process.getBuiltinModule(`path`),n=process.getBuiltinModule(`os`),r=process.env.CODEX_HOME||t.join(n.homedir(),`.codex`),i=t.join(r,`config.toml`);e.mkdirSync(r,{recursive:!0});let a=e.existsSync(i)?e.readFileSync(i,`utf8`):``;e.writeFileSync(i,__s(a))}catch(e){console.error(`Failed to enable Linux remote_control host config`,e)}})()";

  const linuxDeviceKeyProvider = String.raw`function wV({resourcesPath:e}){if(process.platform===` + "`linux`" + String.raw`){let e=require(` + "`crypto`" + String.raw`),t=require(` + "`fs`" + String.raw`),n=require(` + "`path`" + String.raw`),r=require(` + "`os`" + String.raw`),i=n.join(process.env.CODEX_LINUX_REMOTE_CONTROL_KEY_DIR||n.join(r.homedir(),` + "`.config`" + String.raw`,` + "`chatgpt-linux`" + String.raw`),` + "`remote-control-device-keys.json`" + String.raw`),a=()=>{try{return JSON.parse(t.readFileSync(i,` + "`utf8`" + String.raw`))}catch{return{keys:{}}}},o=e=>{t.mkdirSync(n.dirname(i),{recursive:!0}),t.writeFileSync(i,JSON.stringify(e,null,2)+` + "`\\n`" + String.raw`,{mode:384})},s=t=>e.createHash(` + "`sha256`" + String.raw`).update(t).digest(` + "`base64url`" + String.raw`),c=t=>Buffer.from(JSON.stringify({domain:SV,payload:EV(t)}),` + "`utf8`" + String.raw`),l=t=>{let n=a(),r=n.keys[t];if(!r)throw Error(` + "`Linux remote-control device key not found: ${t}`" + String.raw`);return r};return{createDeviceKey:async t=>{let r=e.generateKeyPairSync(` + "`ec`" + String.raw`,{namedCurve:` + "`prime256v1`" + String.raw`}),u=r.publicKey.export({type:` + "`spki`" + String.raw`,format:` + "`der`" + String.raw`}).toString(` + "`base64`" + String.raw`),d=` + "`linux-${Date.now().toString(36)}-${s(u).slice(0,16)}`" + String.raw`,f={algorithm:` + "`ecdsa_p256_sha256`" + String.raw`,keyId:d,protectionClass:` + "`os_protected_nonextractable`" + String.raw`,publicKeySpkiDerBase64:u,privateKeyPem:r.privateKey.export({type:` + "`pkcs8`" + String.raw`,format:` + "`pem`" + String.raw`})},p=a();return p.keys[d]=f,o(p),{algorithm:f.algorithm,keyId:f.keyId,protectionClass:f.protectionClass,publicKeySpkiDerBase64:f.publicKeySpkiDerBase64}},deleteDeviceKey:async e=>{let t=a();delete t.keys[e],o(t)},getDeviceKeyPublic:async e=>{let t=l(e);return{algorithm:t.algorithm,keyId:t.keyId,protectionClass:t.protectionClass,publicKeySpkiDerBase64:t.publicKeySpkiDerBase64}},signDeviceKey:async(t,n)=>{let r=l(t),i=c(n),a=e.createSign(` + "`SHA256`" + String.raw`);a.update(i),a.end();let o=a.sign(r.privateKeyPem);return{algorithm:r.algorithm,signatureDerBase64:o.toString(` + "`base64`" + String.raw`),signedPayloadBase64:i.toString(` + "`base64`" + String.raw`)}}}}let t=null,n=()=>{if(process.platform!==` + "`darwin`" + String.raw`)throw Error(` + "`Remote control device keys are only available on macOS`" + String.raw`);if(e==null)throw Error(` + "`Remote control device keys require resourcesPath`" + String.raw`);return t??=bV((0,i.join)(e,` + "`native`" + String.raw`,xV)),t};return{createDeviceKey:e=>n().createDeviceKey(e??` + "`hardware_only`" + String.raw`),deleteDeviceKey:e=>n().deleteDeviceKey(e),getDeviceKeyPublic:e=>n().getDeviceKeyPublic(e),signDeviceKey:async(e,t)=>{let r=TV(t);return{...await n().signDeviceKey(e,r),signedPayloadBase64:r.toString(` + "`base64`" + String.raw`)}}}}`;

  replaceRegexOptional(
    mainProcess,
    /function wV\(\{resourcesPath:e\}\)\{let t=null,n=\(\)=>\{if\(process\.platform!==`darwin`\)throw Error\(`Remote control device keys are only available on macOS`\);if\(e==null\)throw Error\(`Remote control device keys require resourcesPath`\);return t\?\?=bV\(\(0,i\.join\)\(e,`native`,xV\)\),t\};return\{createDeviceKey:e=>n\(\)\.createDeviceKey\(e\?\?`hardware_only`\),deleteDeviceKey:e=>n\(\)\.deleteDeviceKey\(e\),getDeviceKeyPublic:e=>n\(\)\.getDeviceKeyPublic\(e\),signDeviceKey:async\(e,t\)=>\{let r=TV\(t\);return\{\.\.\.await n\(\)\.signDeviceKey\(e,r\),signedPayloadBase64:r\.toString\(`base64`\)\}\}\}\}/,
    linuxDeviceKeyProvider,
    "Linux remote-control device-key provider",
  );

  replaceOptional(
    mainProcess,
    "async function mV({codexHome:e,hostConfig:n,logger:r=t.Jr()}){if(n.kind===`local`)try{",
    "async function mV({codexHome:e,hostConfig:n,logger:r=t.Jr()}){if(process.platform===`linux`)return;if(n.kind===`local`)try{",
    "Do not strip remote_control config on Linux",
  );

  replaceOptional(
    mainProcess,
    "\"set-local-app-server-feature-enablement\":async({enabled:e,featureName:n})=>{let r=t.et({enabled:e,featureName:n});return this.sharedObjectRepository?.set(`local_app_server_feature_enablement`,r),{enablement:r}}",
    "\"set-local-app-server-feature-enablement\":async({enabled:e,featureName:n})=>{let r=t.et({enabled:e,featureName:n});process.platform===`linux`&&n===`remote_control`&&e&&" + linuxRemoteControlHostConfig + ";return this.sharedObjectRepository?.set(`local_app_server_feature_enablement`,r),{enablement:r}}",
    "Persist Linux remote_control host config on feature toggle",
  );

  replaceOptional(
    mainProcess,
    "this.sharedObjectRepository.set(`local_app_server_feature_enablement`,t.$());let n=this.createAppServerConnection(this.hostId);",
    "process.platform===`linux`&&(" + linuxRemoteControlHostConfig + "),this.sharedObjectRepository.set(`local_app_server_feature_enablement`,t.$());let n=this.createAppServerConnection(this.hostId);",
    "Enable Linux remote_control host config before local app-server startup",
  );

  feature("mobilePairingBridge", "partial", {
    evidence: "Linux remote_control config persistence is patched; Linux device-key provider patch attempted.",
    caveat: "End-to-end server acceptance and account behavior still require the final runtime batch test.",
  });
}

function patchBrowserUse() {
  const appMain = findAsset(/^app-main-.*\.js$/);
  const browserUseAvailability = findAssetOptional(/^use-in-app-browser-use-availability-.*\.js$/);
  const mainProcess = findBuildAsset(/^main-.*\.js$/);

  replaceOptional(
    mainProcess,
    "ambientSuggestions:!1,artifactsPane:!1,browserPane:!1,inAppBrowserUse:!1,inAppBrowserUseAllowed:!1,externalBrowserUse:!1,externalBrowserUseAllowed:!1",
    "ambientSuggestions:!1,artifactsPane:!1,browserPane:!0,inAppBrowserUse:!0,inAppBrowserUseAllowed:!0,externalBrowserUse:!1,externalBrowserUseAllowed:!1",
    "Browser Use main-process feature defaults",
  );

  replaceOptional(
    appMain,
    "inAppBrowserUse:d.available,inAppBrowserUseAllowed:d.allowed,browserPane:o",
    "inAppBrowserUse:!0,inAppBrowserUseAllowed:!0,browserPane:!0",
    "Browser Use desktop feature broadcast",
  );

  if (browserUseAvailability) {
  replaceOptional(
    browserUseAvailability,
    "return n!=null&&r?.enabled!==!1",
    "return !0",
    "Browser Use sidebar availability",
  );

  replaceOptional(
    browserUseAvailability,
    "m=a&&o&&p&&!f.isLoading&&f.data!==!0",
    "m=!0",
    "Browser Use allowed state",
  );

  replaceOptional(
    browserUseAvailability,
    "g=u.isLoading||f.isLoading",
    "g=!1",
    "Browser Use loading state",
  );

  replaceOptional(
    browserUseAvailability,
    "_=f.data===!0",
    "_=!1",
    "Browser Use WSL disable gate",
  );

  replaceOptional(
    browserUseAvailability,
    "function S({isBrowserAgentGateEnabled:e,isBrowserSidebarEnabled:t,isBrowserUseEnabled:n,isLoading:r,runCodexInWsl:i}){return r?`loading`:t?e?n?i?`wsl-disabled`:`available`:`config-requirement-disabled`:`statsig-disabled`:`browser-pane-disabled`}",
    "function S({isBrowserAgentGateEnabled:e,isBrowserSidebarEnabled:t,isBrowserUseEnabled:n,isLoading:r,runCodexInWsl:i}){return `available`}",
    "Browser Use availability reason",
  );

  replaceOptional(
    browserUseAvailability,
    "let a=h(i),o=r&&a.enabled&&!a.isLoading,c;return t[2]!==o||t[3]!==a.isLoading?(c={allowed:o,available:o,isLoading:a.isLoading},t[2]=o,t[3]=a.isLoading,t[4]=c):c=t[4],c",
    "let a=h(i),o=!0,c;return t[2]!==o||t[3]!==!1?(c={allowed:!0,available:!0,isLoading:!1},t[2]=o,t[3]=!1,t[4]=c):c=t[4],c",
    "External Chrome Browser Use availability gate",
  );
  } else {
    warn("Browser Use renderer availability chunk was not present; continuing with main-process gates and the Linux shim.");
  }

  replaceOptional(
    mainProcess,
    "new gL(t=>this.canServeTurnForBrowserRoute(t,e)?this.getBrowserUseHost(t):null,e=>this.getDelegate().addBrowserUseNavigationBlockedListener(e),{appSessionId:this.options.appSessionId,browserRoute:e,buildFlavor:this.options.buildFlavor,canServeRoute:t=>this.canServeTurnForBrowserRoute(t,e)})",
    "new gL(t=>(t?.turnId??t?.turn_id)===`linux-browser-use-turn`&&(t?.conversationId??t?.session_id)===e.conversationId?this.getBrowserUseHost(e):this.canServeTurnForBrowserRoute(t,e)?this.getBrowserUseHost(t):null,e=>this.getDelegate().addBrowserUseNavigationBlockedListener(e),{appSessionId:this.options.appSessionId,browserRoute:e,buildFlavor:this.options.buildFlavor,canServeRoute:t=>this.canServeTurnForBrowserRoute(t,e)})",
    "Browser Use route metadata provider",
  );

  replaceOptional(
    mainProcess,
    "getMetadata(){let e={};return this.options.buildFlavor!=null&&(e.codexAppBuildFlavor=this.options.buildFlavor),this.options.appSessionId!=null&&(e.codexAppSessionId=this.options.appSessionId),this.options.browserRoute!=null&&(e.codexSessionId=this.options.browserRoute.conversationId,e.codexWindowId=String(this.options.browserRoute.windowId)),e}",
    "getMetadata(){let e={},t=this.options.getBrowserUseTurnId?.(),n=typeof t==`string`?t:this.options.browserRoute!=null?`linux-browser-use-turn`:null;return this.options.buildFlavor!=null&&(e.codexAppBuildFlavor=this.options.buildFlavor),this.options.appSessionId!=null&&(e.codexAppSessionId=this.options.appSessionId),this.options.browserRoute!=null&&(e.codexSessionId=this.options.browserRoute.conversationId,e.codexWindowId=String(this.options.browserRoute.windowId)),n!=null&&(e.codexTurnId=n,e.browserUseTurnId=n),e}",
    "Browser Use active turn metadata export",
  );

  replaceOptional(
    mainProcess,
    "canServeTurnForBrowserRoute(e,t){let n=this.turnRoutes.get(WL(e));return n==null||this.delegate?.isWindowAlive(n.windowId)!==!0?!1:n.conversationId===t.conversationId&&n.windowId===t.windowId}",
    "canServeTurnForBrowserRoute(e,t){let n=this.turnRoutes.get(WL(e));if(n==null){let e=this.windows.get(GL(t.windowId));return this.delegate?.isWindowAlive(t.windowId)===!0&&e?.conversations.has(t.conversationId)===!0}return this.delegate?.isWindowAlive(n.windowId)===!0&&n.conversationId===t.conversationId&&n.windowId===t.windowId}",
    "Browser Use route fallback from page state",
  );

  replaceOptional(
    mainProcess,
    "canServeTurnForBrowserRoute(e,t){let n=this.turnRoutes.get(WL(e));if(n==null){let e=this.windows.get(GL(t.windowId));return this.delegate?.isWindowAlive(t.windowId)===!0&&e?.conversationId===t.conversationId}return this.delegate?.isWindowAlive(n.windowId)===!0&&n.conversationId===t.conversationId&&n.windowId===t.windowId}",
    "canServeTurnForBrowserRoute(e,t){let n=this.turnRoutes.get(WL(e));if(n==null){let e=this.windows.get(GL(t.windowId));return this.delegate?.isWindowAlive(t.windowId)===!0&&e?.conversations.has(t.conversationId)===!0}return this.delegate?.isWindowAlive(n.windowId)===!0&&n.conversationId===t.conversationId&&n.windowId===t.windowId}",
    "Browser Use route fallback uses window conversation set",
  );

  replaceOptional(
    mainProcess,
    "resolveBrowserRoute(e){let t=this.turnRoutes.get(WL(e));if(t==null)throw zL().warning(`IAB_LIFECYCLE missing browser use turn route`,{safe:e,sensitive:{}}),Error(`No Codex browser route captured for browser session ${e.conversationId} turn ${e.turnId}`);let n={conversationId:t.conversationId,windowId:t.windowId};return this.assertWindowAlive(n),zL().info(`IAB_LIFECYCLE resolved browser use route`,{safe:{conversationId:t.conversationId,ownerWebContentsId:t.ownerWebContentsId,turnId:t.turnId,windowId:t.windowId},sensitive:{}}),n}",
    "resolveBrowserRoute(e){let t=this.turnRoutes.get(WL(e));if(t==null){for(let[t,n]of this.windows.entries())if(n.pages.has(e.conversationId)){let r={conversationId:e.conversationId,windowId:t};return this.assertWindowAlive(r),zL().info(`IAB_LIFECYCLE resolved browser use route from Linux page snapshot`,{safe:{conversationId:e.conversationId,turnId:e.turnId,windowId:t},sensitive:{}}),r}throw zL().warning(`IAB_LIFECYCLE missing browser use turn route`,{safe:e,sensitive:{}}),Error(`No Codex browser route captured for browser session ${e.conversationId} turn ${e.turnId}`)}let n={conversationId:t.conversationId,windowId:t.windowId};return this.assertWindowAlive(n),zL().info(`IAB_LIFECYCLE resolved browser use route`,{safe:{conversationId:t.conversationId,ownerWebContentsId:t.ownerWebContentsId,turnId:t.turnId,windowId:t.windowId},sensitive:{}}),n}",
    "Browser Use resolve route from Linux page snapshot",
  );

  replaceOptional(
    mainProcess,
    "registerThread(e){let t=this.ensureWindowRecord(e.windowId);t.conversations.add(e.conversationId),this.ensureBackendForBrowserRoute(e),zL().info(`IAB_LIFECYCLE registered browser sidebar thread`,{safe:e,sensitive:{}})}",
    "registerThread(e){let t=this.ensureWindowRecord(e.windowId);t.conversations.add(e.conversationId);let n=WL({conversationId:e.conversationId,turnId:`linux-browser-use-turn`});this.turnRoutes.has(n)||this.turnRoutes.set(n,{conversationId:e.conversationId,disposeAfterTurn:!1,ownerWebContentsId:t.ownerWebContentsId??0,turnId:`linux-browser-use-turn`,windowId:GL(e.windowId)}),this.ensureBackendForBrowserRoute(e),zL().info(`IAB_LIFECYCLE registered browser sidebar thread`,{safe:e,sensitive:{}})}",
    "Browser Use synthetic Linux turn route registration",
  );

  replaceOptional(
    mainProcess,
    "registerThread(e){this.ensureWindowRecord(e.windowId).conversations.add(e.conversationId),this.ensureBackendForBrowserRoute(e),zL().info(`IAB_LIFECYCLE registered browser sidebar thread`,{safe:e,sensitive:{}})}",
    "registerThread(e){let t=this.ensureWindowRecord(e.windowId);t.conversations.add(e.conversationId);let n=WL({conversationId:e.conversationId,turnId:`linux-browser-use-turn`});this.turnRoutes.has(n)||this.turnRoutes.set(n,{conversationId:e.conversationId,disposeAfterTurn:!1,ownerWebContentsId:t.ownerWebContentsId??0,turnId:`linux-browser-use-turn`,windowId:GL(e.windowId)}),this.ensureBackendForBrowserRoute(e),zL().info(`IAB_LIFECYCLE registered browser sidebar thread`,{safe:e,sensitive:{}})}",
    "Browser Use synthetic Linux turn route registration for compact build",
  );

  replaceOptional(
    mainProcess,
    "requireBrowserUseSession(e){let t=e?.session_id;if(typeof t!=`string`)throw Error(`Missing required browser session_id`);let n=e?.turn_id;if(typeof n!=`string`)throw Error(`Missing required browser turn_id`);let r={conversationId:t,turnId:n};if(this.options.browserRoute!=null&&r.conversationId!==this.options.browserRoute.conversationId)throw Error(`Browser session does not belong to this IAB pipe`);if(!this.canServeRoute(r))throw Error(`Browser turn does not belong to this IAB pipe`);return r}",
    "requireBrowserUseSession(e){let t=e?.session_id;if(typeof t!=`string`)throw Error(`Missing required browser session_id`);let n=e?.turn_id;if(typeof n!=`string`)throw Error(`Missing required browser turn_id`);let r={conversationId:t,turnId:n};if(this.options.browserRoute!=null&&r.conversationId!==this.options.browserRoute.conversationId)throw Error(`Browser session does not belong to this IAB pipe`);if(n===`linux-browser-use-turn`&&this.options.browserRoute!=null&&r.conversationId===this.options.browserRoute.conversationId)return r;if(!this.canServeRoute(r))throw Error(`Browser turn does not belong to this IAB pipe`);return r}",
    "Browser Use accept synthetic Linux turn id",
  );

  writeBrowserUseShim();

  features.browserUse = {
    status: "partial",
    evidence: browserUseAvailability ? "Feature gates are enabled and a Linux node_repl Browser Use MCP shim is generated." : "The legacy renderer availability chunk is absent; main-process patches and the Linux node_repl shim were attempted.",
    acceptance: "Must be tested in a fresh installed app by opening the in-app browser and asking Codex to browse the active tab.",
  };
}

function patchChromeControl() {
  const source = process.env.CODEX_CHROME_PLUGIN_SOURCE;
  if (!source || !fs.existsSync(path.join(source, ".codex-plugin", "plugin.json"))) {
    warn("Skipping Chrome Control; CODEX_CHROME_PLUGIN_SOURCE is not available from the extracted DMG resources.");
    feature("chromeControl", "skipped", {
      evidence: "Chrome plugin resources were not found outside app.asar.",
    });
    return;
  }

  const pluginRoot = path.join(root, "plugins", "openai-bundled", "plugins", "chrome");
  copyDirectory(source, pluginRoot);
  record("Chrome plugin resources", "copied", pluginRoot);

  for (const arch of ["x64", "arm64"]) {
    writeExecutable(
      path.join(pluginRoot, "extension-host", "linux", arch, "extension-host"),
      chromeExtensionHostScript(),
    );
  }
  record("Chrome Linux native messaging host", "written", path.join(pluginRoot, "extension-host", "linux", process.arch === "arm64" ? "arm64" : "x64", "extension-host"));

  patchChromeHelperScripts(pluginRoot);

  feature("chromeControl", "partial", {
    evidence: "Chrome plugin resources are copied, Linux native messaging host is generated, and Linux helper scripts are patched for Google Chrome.",
    caveat: "Requires Google Chrome plus Codex Chrome Extension runtime validation. Chromium-family browsers are intentionally out of scope.",
  });
}

function patchChromeHelperScripts(pluginRoot) {
  const scriptsDir = path.join(pluginRoot, "scripts");
  const checkManifest = path.join(scriptsDir, "check-native-host-manifest.js");
  const chromeRunning = path.join(scriptsDir, "chrome-is-running.js");
  const openChrome = path.join(scriptsDir, "open-chrome-window.js");

  replaceOptional(
    checkManifest,
    "  throw new Error(\n    `Unsupported platform for native host manifest check: ${process.platform}. This script supports macOS and Windows.`,\n  );",
    "  if (process.platform === \"linux\") {\n    return {\n      manifestPath: path.join(\n        os.homedir(),\n        \".config\",\n        \"google-chrome\",\n        \"NativeMessagingHosts\",\n        `${expectedHostName}.json`,\n      ),\n      registryKey: null,\n      registryManifestPath: null,\n      registryKeyExists: null,\n    };\n  }\n\n  throw new Error(\n    `Unsupported platform for native host manifest check: ${process.platform}. This script supports macOS, Linux, and Windows.`,\n  );",
    "Chrome native-host manifest checker Linux support",
  );

  replaceOptional(
    chromeRunning,
    "  win32: new Set([\"chrome.exe\"]),\n};",
    "  win32: new Set([\"chrome.exe\"]),\n  linux: new Set([\"chrome\", \"google-chrome\", \"google-chrome-stable\"]),\n};",
    "Chrome running Linux process names",
  );

  replaceOptional(
    openChrome,
    "const WINDOWS_CHROME_EXECUTABLE = \"chrome.exe\";\nconst ABOUT_BLANK_URL = \"about:blank\";",
    "const WINDOWS_CHROME_EXECUTABLE = \"chrome.exe\";\nconst LINUX_CHROME_COMMANDS = [\"google-chrome\", \"google-chrome-stable\"];\nconst ABOUT_BLANK_URL = \"about:blank\";",
    "Chrome launcher Linux command list",
  );

  replaceOptional(
    openChrome,
    "  return {\n    command: \"google-chrome\",\n    args: chromeArgs,\n  };",
    "  return {\n    command: findLinuxChromeExecutable(),\n    args: chromeArgs,\n  };",
    "Chrome launcher Linux command discovery call",
  );

  replaceOptional(
    openChrome,
    "function getOpenChromeCommand(profileDirectory) {",
    "function findLinuxChromeExecutable() {\n  for (const command of LINUX_CHROME_COMMANDS) {\n    const executable = commandPath(command);\n    if (executable) return executable;\n  }\n\n  throw new Error(\"Could not find Google Chrome. Install Google Chrome and make sure google-chrome is on PATH.\");\n}\n\nfunction getOpenChromeCommand(profileDirectory) {",
    "Chrome launcher Linux command discovery function",
  );
}

function chromeExtensionHostScript() {
  return String.raw`#!/usr/bin/env node
"use strict";

const fs = require("fs");
const net = require("net");
const os = require("os");
const path = require("path");

const SOCKET_DIR = process.env.CODEX_BROWSER_USE_PIPE_DIR || "/tmp/codex-browser-use";
const SOCKET_NAME = "chrome-" + process.pid + ".sock";
const SOCKET_PATH = path.join(SOCKET_DIR, SOCKET_NAME);
const MAX_FRAME_BYTES = 32 * 1024 * 1024;

let stdoutClosed = false;
let platformBuffer = Buffer.alloc(0);
let nextPlatformRequestId = 1;
const clients = new Map();
const pendingByPlatformId = new Map();

function log(...args) {
  try { console.error("[codex-chrome-host]", ...args); } catch {}
}

function readUInt32(buffer, offset) {
  return os.endianness() === "LE" ? buffer.readUInt32LE(offset) : buffer.readUInt32BE(offset);
}

function writeUInt32(buffer, value, offset) {
  return os.endianness() === "LE" ? buffer.writeUInt32LE(value, offset) : buffer.writeUInt32BE(value, offset);
}

function encode(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8");
  if (body.length > 0xffffffff) throw new Error("message too large for 4-byte length prefix");
  const frame = Buffer.allocUnsafe(4 + body.length);
  writeUInt32(frame, body.length, 0);
  body.copy(frame, 4);
  return frame;
}

function decodeInto(buffer, chunk) {
  buffer = Buffer.concat([buffer, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)]);
  const messages = [];
  while (buffer.length >= 4) {
    const length = readUInt32(buffer, 0);
    if (length > MAX_FRAME_BYTES) throw new Error("frame too large: " + length);
    if (buffer.length < 4 + length) break;
    messages.push(JSON.parse(buffer.subarray(4, 4 + length).toString("utf8")));
    buffer = buffer.subarray(4 + length);
  }
  return { buffer, messages };
}

function sendPlatform(message) {
  if (stdoutClosed) return;
  try {
    process.stdout.write(encode(message));
  } catch (error) {
    stdoutClosed = true;
    log("stdout write failed; exiting:", error && error.message || error);
    process.exit(1);
  }
}

function sendClient(clientId, message) {
  const client = clients.get(clientId);
  if (!client || client.socket.destroyed) return;
  client.socket.write(encode(message));
}

function normalizeRequestFromClient(message, clientId) {
  const platformId = "client:" + clientId + ":" + (nextPlatformRequestId++);
  pendingByPlatformId.set(platformId, {
    clientId,
    clientRequestId: Object.prototype.hasOwnProperty.call(message, "id") ? message.id : null,
  });

  return {
    ...message,
    id: platformId,
    client_id: clientId,
  };
}

function handleClientMessage(clientId, message) {
  if (!message || typeof message !== "object") return;
  if (!Object.prototype.hasOwnProperty.call(message, "id")) {
    sendPlatform({ ...message, client_id: clientId });
    return;
  }
  sendPlatform(normalizeRequestFromClient(message, clientId));
}

function handlePlatformMessage(message) {
  if (!message || typeof message !== "object") return;

  const id = Object.prototype.hasOwnProperty.call(message, "id") ? message.id : null;
  const pending = id == null ? null : pendingByPlatformId.get(id);
  if (pending) {
    pendingByPlatformId.delete(id);
    const response = { ...message, id: pending.clientRequestId };
    delete response.client_id;
    sendClient(pending.clientId, response);
    return;
  }

  const clientId = message.client_id ?? message.clientId;
  if (clientId != null && clients.has(clientId)) {
    const forwarded = { ...message };
    delete forwarded.client_id;
    delete forwarded.clientId;
    sendClient(clientId, forwarded);
    return;
  }

  for (const candidateClientId of clients.keys()) sendClient(candidateClientId, message);
}

function startSocketServer() {
  fs.mkdirSync(SOCKET_DIR, { recursive: true, mode: 0o700 });
  try { fs.chmodSync(SOCKET_DIR, 0o700); } catch {}
  try { fs.unlinkSync(SOCKET_PATH); } catch {}

  const server = net.createServer((socket) => {
    const clientId = String(Math.random()).slice(2) + "-" + Date.now().toString(36);
    clients.set(clientId, { socket, buffer: Buffer.alloc(0) });

    socket.on("data", (chunk) => {
      const client = clients.get(clientId);
      if (!client) return;
      try {
        const decoded = decodeInto(client.buffer, chunk);
        client.buffer = decoded.buffer;
        for (const message of decoded.messages) handleClientMessage(clientId, message);
      } catch (error) {
        sendClient(clientId, { id: null, error: { message: error && error.message || String(error) } });
        socket.destroy();
      }
    });

    socket.on("close", () => {
      clients.delete(clientId);
      for (const [platformId, pending] of pendingByPlatformId) {
        if (pending.clientId === clientId) pendingByPlatformId.delete(platformId);
      }
    });
  });

  server.listen(SOCKET_PATH, () => {
    try { fs.chmodSync(SOCKET_PATH, 0o600); } catch {}
    log("listening", SOCKET_PATH);
  });

  return server;
}

process.stdin.on("data", (chunk) => {
  try {
    const decoded = decodeInto(platformBuffer, chunk);
    platformBuffer = decoded.buffer;
    for (const message of decoded.messages) handlePlatformMessage(message);
  } catch (error) {
    log("platform reader error:", error && error.stack || error);
  }
});

process.stdin.on("end", () => process.exit(0));
process.stdout.on("error", () => { stdoutClosed = true; });
process.on("exit", () => { try { fs.unlinkSync(SOCKET_PATH); } catch {} });
process.on("SIGTERM", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));

startSocketServer();
`;
}

function patchRemoteBackground() {
  const mainProcess = findBuildAsset(/^main-.*\.js$/);

  replaceOptional(
    mainProcess,
    "process.platform!==`win32`&&process.platform!==`darwin`?null",
    "process.platform!==`win32`&&process.platform!==`darwin`&&process.platform!==`linux`?null",
    "Linux tray platform gate",
  );

  replaceOptional(
    mainProcess,
    "if(process.platform===`win32`&&!this.isAppQuitting&&this.options.canHideLastLocalWindowToTray?.()===!0&&!t){e.preventDefault(),M.hide();return}",
    "if((process.platform===`win32`||process.platform===`linux`)&&!this.isAppQuitting&&this.options.canHideLastLocalWindowToTray?.()===!0&&!t){e.preventDefault(),M.hide();return}",
    "Linux close-to-tray behavior",
  );

  replaceOptional(
    mainProcess,
    "E&&de();",
    "(E||process.platform===`linux`)&&de();",
    "Linux tray startup",
  );

  feature("trayBackground", "not-shipped", {
    evidence: "Tray snippets are patched opportunistically, but Linux desktop tray behavior is not reliable across environments.",
    caveat: "Do not advertise background/tray presence in this release. Keep the desktop app process running for mobile presence.",
  });
}

function patchExperimentalAppSnapshot() {
  const mainProcess = findBuildAsset(/^main-.*\.js$/);
  const annotationEditor = findAssetOptional(/^annotation-comment-editor-card-.*\.js$/);
  const composer = findAssetOptional(/^composer-.*\.js$/);

  if (!annotationEditor || !composer) {
    warn("Skipping experimental app snapshots; the required renderer chunks are not present in this ChatGPT.app release.");
    feature("appSnapshotScreenshot", "skipped", {
      evidence: "The release does not contain both legacy app-snapshot renderer chunks.",
    });
    return;
  }

  replaceOptional(
    mainProcess,
    "await n.app.whenReady(),w(`main app.whenReady resolved`,A),D&&",
    "await n.app.whenReady(),process.platform===`linux`&&n.session.defaultSession.setDisplayMediaRequestHandler(async(e,t)=>{try{let r=await n.desktopCapturer.getSources({types:[`window`,`screen`],thumbnailSize:{width:1600,height:1000},fetchWindowIcons:!0}),i=r.filter(e=>!/codex/i.test(e.name??``)),a=(i.length?i:r).find(e=>e.thumbnail!=null&&!e.thumbnail.isEmpty())??r[0];a?t({video:a}):t({})}catch(e){console.error(`Failed to provide Linux app snapshot source`,e),t({})}}),w(`main app.whenReady resolved`,A),D&&",
    "Linux display-media handler for experimental app snapshots",
  );

  replaceOptional(
    annotationEditor,
    "(0,Z.jsx)(_t,{conversationId:l,disabled:T,getAttachmentGen:o,handleAddFiles:G,handleSelectAndClose:de,hasGoal:_,hostId:d,ideContextStatus:g,isAutoContextOn:f,isDropdownOpen:z,isGoalActionAvailable:b,onAddNativeAppContext:t,",
    "(0,Z.jsx)(_t,{conversationId:l,disabled:T,getAttachmentGen:o,handleAddFiles:G,handleSelectAndClose:de,hasGoal:_,hostId:d,ideContextStatus:g,isAutoContextOn:f,isDropdownOpen:z,isGoalActionAvailable:b,onAddImageDataUrls:e,onAddNativeAppContext:t,",
    "App snapshot image attachment callback wiring",
  );

  replaceOptional(
    annotationEditor,
    "function _t(e){let t=(0,Q.c)(103),{conversationId:n,disabled:r,getAttachmentGen:i,handleAddFiles:a,handleSelectAndClose:s,hasGoal:c,hostId:l,ideContextStatus:u,isAutoContextOn:d,isDropdownOpen:f,isGoalActionAvailable:p,onAddNativeAppContext:m,",
    "function _t(e){let t=(0,Q.c)(103),{conversationId:n,disabled:r,getAttachmentGen:i,handleAddFiles:a,handleSelectAndClose:s,hasGoal:c,hostId:l,ideContextStatus:u,isAutoContextOn:d,isDropdownOpen:f,isGoalActionAvailable:p,onAddImageDataUrls:OIMG,onAddNativeAppContext:m,",
    "App snapshot dropdown prop",
  );

  replaceOptional(
    annotationEditor,
    "let W;t[35]!==r||t[36]!==i||t[37]!==_||t[38]!==s||t[39]!==f||t[40]!==m||t[41]!==v||t[42]!==y||t[43]!==b||t[44]!==E?(W=null,t[35]=r,t[36]=i,t[37]=_,t[38]=s,t[39]=f,t[40]=m,t[41]=v,t[42]=y,t[43]=b,t[44]=E,t[45]=W):W=t[45];",
    "let W=E?(0,Z.jsx)(H.Item,{LeftIcon:lt,leftIconClassName:`icon-xs`,onSelect:async()=>{if(r)return;s();let e=null;try{let t=globalThis.navigator?.mediaDevices?.getDisplayMedia;if(typeof t!=`function`)throw new Error(`screen capture is not available in this Electron renderer`);e=await t.call(globalThis.navigator.mediaDevices,{video:!0,audio:!1});let n=document.createElement(`video`);n.srcObject=e,n.muted=!0,n.playsInline=!0,await Promise.race([new Promise((e,t)=>{let r=globalThis.setTimeout(()=>t(new Error(`screen capture timed out`)),5e3);n.onloadedmetadata=()=>{globalThis.clearTimeout(r),e()};let i=n.play();i!=null&&typeof i.catch==`function`&&i.catch(t)}),new Promise(e=>globalThis.setTimeout(e,500))]);let r=n.videoWidth||1600,i=n.videoHeight||900,a=document.createElement(`canvas`);a.width=r,a.height=i;let o=a.getContext(`2d`);if(o==null)throw new Error(`canvas capture is not available`);o.drawImage(n,0,0,r,i),m({imageDataUrl:a.toDataURL(`image/png`),imageName:`app-snapshot.png`,linuxScreenshotFallback:!0})}catch(e){let t=e instanceof Error?e.message:String(e);e?.name===`NotAllowedError`||e?.name===`AbortError`||globalThis.alert?.(`Linux app snapshot failed: ${t}`),console.error(`Linux app snapshot capture failed`,e)}finally{e?.getTracks?.().forEach(e=>e.stop())}},children:(0,Z.jsx)(O,{id:`composer.addAppSnapshot.experimentalLinux`,defaultMessage:`Add app snapshot`,description:`Dropdown item label to attach a screenshot of another desktop app on Linux`})}):null;",
    "Experimental Linux app snapshot add menu item",
  );

  replaceOptional(
    composer,
    "t[45]!==n.length||t[46]!==u||t[47]!==r||t[48]!==c?(R=null,t[45]=n.length,t[46]=u,t[47]=r,t[48]=c,t[49]=R):R=t[49],",
    "t[45]!==n.length||t[46]!==u||t[47]!==r||t[48]!==c?(R=r.map((e,t)=>e.imageDataUrl?(0,Q.jsx)(Zd,{src:e.imageDataUrl,filename:e.imageName??`App snapshot`,alt:`App snapshot`,loading:!1,previewEnabled:l,previewIndex:0,previewItems:[{src:e.imageDataUrl,alt:e.imageName??`App snapshot`}],onRemove:()=>c(t)},`native-${t}`):null),t[45]=n.length,t[46]=u,t[47]=r,t[48]=c,t[49]=R):R=t[49],",
    "Experimental Linux app snapshot preview",
  );

  feature("appSnapshotScreenshot", "partial", {
    evidence: "Adds a Linux screenshot-based app snapshot menu item and composer preview.",
    caveat: "This is not full macOS Computer Use/Appshot parity. It attaches a screenshot-style native app context only.",
  });
}

function writeBrowserUseShim() {
  const nodeReplJs = String.raw`#!/usr/bin/env node
"use strict";

const fs = require("fs");
const net = require("net");
const os = require("os");
const path = require("path");
const readline = require("readline");
const util = require("util");
const vm = require("vm");

let context;
let activeRequestMeta = {};
let lastMetadataError = null;
const nativePipe = createNativePipeClient();

function createNativePipeClient() {
  let nextId = 1;
  let socket = null;
  let buffer = Buffer.alloc(0);
  let connecting = null;
  const pending = new Map();

  function listSocketCandidates() {
    const configured = process.env.CODEX_BROWSER_USE_PIPE_PATH || process.env.NODE_REPL_BROWSER_USE_PIPE_PATH;
    if (configured && fs.existsSync(configured)) return [configured];
    const root = process.env.CODEX_BROWSER_USE_PIPE_DIR || "/tmp/codex-browser-use";
    const candidates = [];
    function walk(dir, depth) {
      if (depth > 2) return;
      let entries = [];
      try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
      for (const entry of entries) {
        const full = path.join(dir, entry.name);
        try {
          if (entry.isDirectory()) walk(full, depth + 1);
          else if (entry.name.endsWith(".sock")) candidates.push({ path: full, mtimeMs: fs.statSync(full).mtimeMs });
        } catch {}
      }
    }
    walk(root, 0);
    return candidates.sort((a, b) => b.mtimeMs - a.mtimeMs).map((candidate) => candidate.path);
  }

  function encode(message) {
    const body = Buffer.from(JSON.stringify(message), "utf8");
    const frame = Buffer.allocUnsafe(4 + body.length);
    if (os.endianness() === "LE") frame.writeUInt32LE(body.length, 0);
    else frame.writeUInt32BE(body.length, 0);
    body.copy(frame, 4);
    return frame;
  }

  function decode(chunk) {
    buffer = Buffer.concat([buffer, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)]);
    const messages = [];
    while (buffer.length >= 4) {
      const length = os.endianness() === "LE" ? buffer.readUInt32LE(0) : buffer.readUInt32BE(0);
      if (length > 8 * 1024 * 1024) throw new Error("Native pipe frame too large: " + length);
      if (buffer.length < 4 + length) break;
      messages.push(JSON.parse(buffer.subarray(4, 4 + length).toString("utf8")));
      buffer = buffer.subarray(4 + length);
    }
    return messages;
  }

  function rejectAll(error) {
    for (const entry of pending.values()) entry.reject(error);
    pending.clear();
  }

  async function connect() {
    if (socket && !socket.destroyed) return socket;
    if (connecting) return connecting;
    connecting = (async () => {
      const candidates = listSocketCandidates();
      if (candidates.length === 0) throw new Error("No Codex Browser Use native pipe socket found under /tmp/codex-browser-use");
      let lastError = null;
      for (const pipePath of candidates) {
        try {
          return await connectPath(pipePath);
        } catch (error) {
          if (error && (error.code === "ECONNREFUSED" || error.code === "ENOENT")) {
            try { fs.unlinkSync(pipePath); } catch {}
          }
          lastError = error;
        }
      }
      throw lastError || new Error("No active Codex Browser Use native pipe accepted a connection");
    })().finally(() => { connecting = null; });
    return connecting;
  }

  function connectPath(pipePath) {
    return new Promise((resolve, reject) => {
      let settled = false;
      const s = net.createConnection(pipePath);
      const timer = setTimeout(() => finish(new Error("Timed out connecting to Codex Browser Use native pipe: " + pipePath)), 750);
      if (timer.unref) timer.unref();
      function finish(value) {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (value instanceof Error) {
          s.destroy();
          reject(value);
        } else {
          resolve(value);
        }
      }
      s.on("connect", () => { socket = s; finish(s); });
      s.on("data", (chunk) => {
        let messages;
        try { messages = decode(chunk); } catch (error) { rejectAll(error); s.destroy(); return; }
        for (const message of messages) {
          if (!message || !Object.prototype.hasOwnProperty.call(message, "id")) continue;
          const entry = pending.get(message.id);
          if (!entry) continue;
          pending.delete(message.id);
          if (message.error) entry.reject(new Error(message.error.message || "Native pipe request failed"));
          else entry.resolve(message.result);
        }
      });
      s.on("error", (error) => { rejectAll(error); if (!socket || socket === s) socket = null; finish(error); });
      s.on("close", () => { rejectAll(new Error("Codex Browser Use native pipe closed")); if (socket === s) socket = null; });
    });
  }

  async function sendRequest(method, params) {
    const s = await connect();
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      s.write(encode({ jsonrpc: "2.0", id, method, params: params || {} }), (error) => {
        if (!error) return;
        pending.delete(id);
        reject(error);
      });
    });
  }

  async function sendNotification(method, params) {
    const s = await connect();
    s.write(encode({ jsonrpc: "2.0", method, params: params || {} }));
  }

  const publicApi = {
    createConnection: connect,
    connect,
    sendRequest,
    sendNotification,
    setMessageCallback() {},
    addCloseListener() { return () => {}; },
    listSocketCandidates,
    findSocket: () => listSocketCandidates()[0] || null,
  };
  return Object.assign(publicApi, { publicApi });
}

function turnMetadata() {
  const meta = activeRequestMeta || {};
  const sessionId = meta.session_id || meta.sessionId || meta.codexSessionId || meta.conversationId || meta.conversation_id;
  const turnId = meta.turn_id || meta.turnId || meta.codexTurnId || meta.browserUseTurnId || meta.codexBrowserUseTurnId;
  const out = {};
  if (sessionId) out.session_id = String(sessionId);
  if (turnId) out.turn_id = String(turnId);
  return out;
}

async function resolveTurnMetadata() {
  const meta = turnMetadata();
  if (meta.session_id && meta.turn_id) return meta;
  try {
    const pipeMeta = await nativePipe.sendRequest("getMetadata", {});
    const sessionId = meta.session_id || pipeMeta.codexSessionId || pipeMeta.session_id || pipeMeta.sessionId;
    const turnId = meta.turn_id || pipeMeta.codexTurnId || pipeMeta.browserUseTurnId || pipeMeta.turn_id || pipeMeta.turnId || (sessionId ? "linux-browser-use-turn" : null);
    const out = {};
    if (sessionId) out.session_id = String(sessionId);
    if (turnId) out.turn_id = String(turnId);
    return out;
  } catch (error) {
    lastMetadataError = error;
    return meta;
  }
}

async function withTurn(params) {
  return Object.assign({}, params || {}, await resolveTurnMetadata());
}

function createBrowserApi(pipe) {
  return {
    nativePipe: pipe,
    connect: () => pipe.connect(),
    info: async (params) => pipe.sendRequest("getInfo", await withTurn(params)),
    tabs: {
      list: async (params) => pipe.sendRequest("getTabs", await withTurn(params)),
      create: async (params) => pipe.sendRequest("createTab", await withTurn(params)),
      attach: async (params) => pipe.sendRequest("attach", await withTurn(params)),
      detach: async (params) => pipe.sendRequest("detach", await withTurn(params)),
    },
    cdp: async (params) => pipe.sendRequest("executeCdp", await withTurn(params)),
    command: async (params) => pipe.sendRequest("executeUnhandledCommand", await withTurn(params)),
    moveMouse: async (params) => pipe.sendNotification("moveMouse", await withTurn(params)),
    show: async () => pipe.sendRequest("executeUnhandledCommand", await withTurn({ type: "browser.setVisible", visible: true })),
    hide: async () => pipe.sendRequest("executeUnhandledCommand", await withTurn({ type: "browser.setVisible", visible: false })),
    setViewport: async (width, height) => pipe.sendRequest("executeUnhandledCommand", await withTurn({ type: "browser.setViewport", width, height })),
    resetViewport: async () => pipe.sendRequest("executeUnhandledCommand", await withTurn({ type: "browser.resetViewport" })),
  };
}

async function requireTurnMetadata() {
  const meta = await resolveTurnMetadata();
  if (meta.session_id && meta.turn_id) return meta;
  if (lastMetadataError) {
    throw new Error("Codex Browser Use native pipe is not reachable: " + (lastMetadataError.message || String(lastMetadataError)) + ". Keep Codex running, open the in-app browser for this thread, then retry.");
  }
  throw new Error("Browser Use turn metadata is missing. Start this from an active Codex Browser Use turn so the app can provide session_id and turn_id.");
}

function normalizeTarget(args) {
  const target = args.target && typeof args.target === "object" ? Object.assign({}, args.target) : {};
  if (args.tabId != null && target.tabId == null) target.tabId = args.tabId;
  if (args.pageKey != null && target.pageKey == null) target.pageKey = args.pageKey;
  if (args.webContentsId != null && target.webContentsId == null) target.webContentsId = args.webContentsId;
  return Object.keys(target).length > 0 ? target : undefined;
}

async function defaultTarget(browser, args) {
  const explicit = normalizeTarget(args || {});
  if (explicit) return explicit;
  const tabs = await browser.tabs.list();
  const list = Array.isArray(tabs) ? tabs : tabs && tabs.tabs;
  const active = (list && list.find && list.find((tab) => tab && tab.active)) || (list && list[0]);
  if (active && active.pageKey != null) return { pageKey: active.pageKey };
  if (active && active.tabId != null) return { tabId: active.tabId };
  if (active && active.id != null) return { tabId: active.id };
  throw new Error("No active Codex in-app browser tab is available.");
}

async function handleBrowserUse(args) {
  args = args || {};
  await requireTurnMetadata();
  const browser = createBrowserApi(nativePipe);
  const action = String(args.action || "info");
  if (action === "info") return browser.info();
  if (action === "list_tabs") return browser.tabs.list();
  if (action === "create_tab") return browser.tabs.create(args);
  if (action === "show") return browser.show();
  if (action === "hide") return browser.hide();
  if (action === "set_viewport") return browser.setViewport(Number(args.width), Number(args.height));
  if (action === "reset_viewport") return browser.resetViewport();
  const target = await defaultTarget(browser, args);
  if (action === "attach") return browser.tabs.attach({ target });
  if (action === "detach") return browser.tabs.detach({ target });
  if (action === "navigate") {
    if (!args.url) throw new Error("browser_use.navigate requires a url.");
    return browser.cdp({ target, method: "Page.navigate", commandParams: { url: String(args.url) } });
  }
  if (action === "evaluate") {
    if (!args.expression) throw new Error("browser_use.evaluate requires an expression.");
    return browser.cdp({ target, method: "Runtime.evaluate", commandParams: { expression: String(args.expression), returnByValue: args.returnByValue !== false, awaitPromise: args.awaitPromise !== false } });
  }
  if (action === "screenshot") {
    return browser.cdp({ target, method: "Page.captureScreenshot", commandParams: { format: args.format || "png", captureBeyondViewport: args.captureBeyondViewport === true } });
  }
  if (action === "click") {
    const x = Number(args.x), y = Number(args.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error("browser_use.click requires numeric x and y.");
    await browser.cdp({ target, method: "Input.dispatchMouseEvent", commandParams: { type: "mousePressed", x, y, button: "left", clickCount: 1 } });
    return browser.cdp({ target, method: "Input.dispatchMouseEvent", commandParams: { type: "mouseReleased", x, y, button: "left", clickCount: 1 } });
  }
  if (action === "type") {
    if (args.text == null) throw new Error("browser_use.type requires text.");
    return browser.cdp({ target, method: "Input.insertText", commandParams: { text: String(args.text) } });
  }
  if (action === "press") {
    if (!args.key) throw new Error("browser_use.press requires key.");
    await browser.cdp({ target, method: "Input.dispatchKeyEvent", commandParams: { type: "keyDown", key: String(args.key) } });
    return browser.cdp({ target, method: "Input.dispatchKeyEvent", commandParams: { type: "keyUp", key: String(args.key) } });
  }
  throw new Error("Unsupported browser_use action: " + action);
}

function createContext() {
  const logs = [];
  const browserBackends = availableBrowserBackends();
  const sandbox = {
    Buffer, URL, URLSearchParams, TextDecoder, TextEncoder,
    clearInterval, clearTimeout, fetch: globalThis.fetch, process, require, setInterval, setTimeout,
    console: {
      debug: (...args) => logs.push(formatArgs(args)),
      error: (...args) => logs.push(formatArgs(args)),
      info: (...args) => logs.push(formatArgs(args)),
      log: (...args) => logs.push(formatArgs(args)),
      warn: (...args) => logs.push(formatArgs(args)),
    },
    nodeRepl: { fetch: globalThis.fetch, browserUseAvailableBackends: browserBackends, requestMeta: { "x-codex-browser-use-available-backends": browserBackends } },
    __codexNativePipe: nativePipe.publicApi,
    __codexNativePipeUnavailableMessage: "The Linux Browser Use shim could not find an active Codex in-app browser pipe. Open a Browser Use turn in Codex and retry.",
    browser: createBrowserApi(nativePipe.publicApi),
    codexTurnMetadata: {},
  };
  sandbox.global = sandbox;
  sandbox.globalThis = sandbox;
  context = { sandbox: vm.createContext(sandbox), logs };
}

function formatArgs(args) {
  return args.map((arg) => typeof arg === "string" ? arg : util.inspect(arg, { depth: 5, colors: false })).join(" ");
}

function serialize(value) {
  if (typeof value === "undefined") return "undefined";
  if (typeof value === "string") return value;
  return util.inspect(value, { depth: 8, colors: false, breakLength: 120 });
}

function chromeHostInstalled() {
  const configured = process.env.CODEX_CHROME_EXTENSION_HOST_PATH;
  if (configured && fs.existsSync(configured)) return true;
  const root = process.env.CODEX_CHROME_PLUGIN_ROOT || path.resolve(__dirname, "..", "plugins", "openai-bundled", "plugins", "chrome");
  const arch = process.arch === "arm64" ? "arm64" : "x64";
  return fs.existsSync(path.join(root, "extension-host", "linux", arch, "extension-host"));
}

function availableBrowserBackends() {
  const backends = ["iab"];
  if (chromeHostInstalled()) backends.push("chrome");
  return backends;
}

function browserUseMeta() {
  return { "codex/browserUse": true, "x-codex-browser-use-available-backends": availableBrowserBackends() };
}

async function runJs(code, timeoutMs) {
  if (!context) createContext();
  context.logs.length = 0;
  context.sandbox.codexTurnMetadata = turnMetadata();
  const timeout = Number.isFinite(timeoutMs) ? Math.max(1, Math.min(timeoutMs, 30000)) : 10000;
  let result;
  try {
    result = vm.runInContext(String(code || ""), context.sandbox, { timeout });
  } catch (error) {
    if (/^\s*await\b/.test(String(code || ""))) result = vm.runInContext("(async () => (" + code + "))()", context.sandbox, { timeout });
    else throw error;
  }
  if (result && typeof result.then === "function") {
    result = await Promise.race([result, new Promise((_, reject) => setTimeout(() => reject(new Error("JavaScript execution timed out after " + timeout + "ms")), timeout))]);
  }
  const parts = [];
  if (context.logs.length > 0) parts.push(context.logs.join("\n"));
  if (typeof result !== "undefined") parts.push(serialize(result));
  return parts.join("\n") || "undefined";
}

function extractRequestMeta(params) {
  const values = [];
  if (process.env.NODE_REPL_REQUEST_META) {
    try { values.push(JSON.parse(process.env.NODE_REPL_REQUEST_META)); } catch {}
  }
  for (const candidate of [params && params._meta, params && params.meta, params && params.arguments && params.arguments._meta, params && params.arguments && params.arguments.meta]) {
    if (candidate && typeof candidate === "object" && !Array.isArray(candidate)) values.push(candidate);
  }
  return Object.assign({}, ...values);
}

function toolList() {
  return [
    {
      name: "browser_use",
      description: "Control the Codex in-app browser on Linux through the Browser Use bridge.",
      inputSchema: {
        type: "object",
        properties: {
          action: { type: "string", enum: ["info","list_tabs","create_tab","attach","detach","navigate","evaluate","screenshot","click","type","press","show","hide","set_viewport","reset_viewport"] },
          url: { type: "string" },
          expression: { type: "string" },
          x: { type: "number" },
          y: { type: "number" },
          text: { type: "string" },
          key: { type: "string" },
          width: { type: "number" },
          height: { type: "number" },
          tabId: {},
          pageKey: { type: "string" },
          target: { type: "object" },
        },
        required: ["action"],
        additionalProperties: true,
      },
    },
    {
      name: "js",
      description: "Execute JavaScript in a persistent Node.js context. The context exposes browser.* and __codexNativePipe.",
      inputSchema: { type: "object", properties: { code: { type: "string" }, timeout_ms: { type: "number" } }, required: ["code"], additionalProperties: true },
    },
    { name: "js_reset", description: "Reset the persistent JavaScript context.", inputSchema: { type: "object", properties: {}, additionalProperties: true } },
  ];
}

function result(id, value) { process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result: value }) + "\n"); }
function error(id, code, message) { process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n"); }

async function handle(message) {
  if (!message || typeof message !== "object") return;
  const id = message.id, method = message.method, params = message.params;
  if (!Object.prototype.hasOwnProperty.call(message, "id")) return;
  try {
    if (method === "initialize") return result(id, { protocolVersion: (params && params.protocolVersion) || "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "node_repl", version: "linux-browser-use-shim-0.2.0" } });
    if (method === "ping") return result(id, {});
    if (method === "tools/list") return result(id, { tools: toolList() });
    if (method === "tools/call") {
      const name = params && params.name;
      const args = (params && params.arguments) || {};
      activeRequestMeta = extractRequestMeta(params);
      if (name === "js_reset") { createContext(); return result(id, { content: [{ type: "text", text: "js execution reset" }], isError: false, _meta: browserUseMeta() }); }
      if (name === "js") {
        try { return result(id, { content: [{ type: "text", text: await runJs(args.code, Number(args.timeout_ms)) }], isError: false, _meta: browserUseMeta() }); }
        catch (runError) { return result(id, { content: [{ type: "text", text: runError && runError.stack || String(runError) }], isError: true, _meta: browserUseMeta() }); }
      }
      if (name === "browser_use") {
        try { return result(id, { content: [{ type: "text", text: serialize(await handleBrowserUse(args)) }], isError: false, _meta: browserUseMeta() }); }
        catch (browserError) { return result(id, { content: [{ type: "text", text: browserError && browserError.stack || String(browserError) }], isError: true, _meta: browserUseMeta() }); }
      }
      return error(id, -32602, "Unknown tool: " + name);
    }
    return error(id, -32601, "Method not found: " + method);
  } catch (err) {
    return error(id, -32603, err && err.stack || String(err));
  }
}

createContext();
readline.createInterface({ input: process.stdin }).on("line", (line) => {
  if (!line.trim()) return;
  try { void handle(JSON.parse(line)); } catch (err) { error(null, -32700, err && err.message || String(err)); }
});
`;

  const wrapper = `#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
if [ -n "\${NODE_REPL_NODE_PATH:-}" ]; then
  exec "$NODE_REPL_NODE_PATH" "\${SCRIPT_DIR}/node_repl-linux.js" "$@"
fi
if [ -n "\${CODEX_BROWSER_USE_NODE_PATH:-}" ]; then
  exec "$CODEX_BROWSER_USE_NODE_PATH" "\${SCRIPT_DIR}/node_repl-linux.js" "$@"
fi
exec node "\${SCRIPT_DIR}/node_repl-linux.js" "$@"
`;

  writeExecutable(path.join(root, "bin", "node_repl-linux.js"), nodeReplJs);
  writeExecutable(path.join(root, "bin", "node_repl-linux"), wrapper);
  record("Browser Use node_repl Linux shim", "written", path.join(root, "bin", "node_repl-linux.js"));
}

function writeManifest() {
  const manifest = {
    generatedAt: new Date().toISOString(),
    patchEngine: "tools/patch-chatgpt-linux.mjs",
    features,
    patches,
    warnings,
  };

  fs.writeFileSync(
    path.join(root, "chatgpt-linux-feature-manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
}

patchMobilePairingUi();
patchLinuxRemoteControlBridge();
patchBrowserUse();
patchChromeControl();
patchExperimentalAppSnapshot();
patchRemoteBackground();
writeManifest();
