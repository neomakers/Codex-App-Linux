#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n install-chatgpt-linux.sh lib/chatgpt-installer.sh tests/*.sh
bash tests/installer-functions.test.sh
node --test tests/*.test.mjs

if rg -n 'install-codex-linux\.sh|codex-linux/|codex-linux\.desktop' \
  README.md .gitignore; then
  printf 'obsolete Codex Linux branding remains\n' >&2
  exit 1
fi

rg -q 'install-chatgpt-linux\.sh' README.md
rg -q 'chatgpt-linux/' README.md
rg -q 'ChatGPT-latest\.dmg' .gitignore

test ! -e install-codex-linux.sh
test ! -e tools/patch-codex-linux.mjs
