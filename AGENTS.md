# Repository Policy

- Treat [UPGRADING.md](UPGRADING.md) and [compatibility/current.json](compatibility/current.json) as the current upgrade authority. Historical research documents are evidence, not instructions.
- Accept only `ChatGPT.app` payloads on this mainline. Any future `Codex.app` support must use a separately named profile and adapter; do not add a compatibility path to the ChatGPT patch engine.
- Preserve internal `codex://`, `CODEX_*`, `com.openai.codex`, CLI, socket, and backend contracts unless replacement is separately evidenced and verified.
- Make required patches fail closed. Record unavailable optional patches as `skipped`; never claim runtime support from a visible renderer gate or generated shim alone.
- Guard every minified-asset edit with a release-specific precondition. Do not use broad text replacement against minified assets.
- Before publishing, run `bash tests/run-all.sh`, update the release contract with observed evidence, and keep official DMGs, extracted ASARs, generated apps, credentials, and machine-local paths out of Git.
