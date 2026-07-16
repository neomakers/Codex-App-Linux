#!/bin/bash
# Build a self-contained amd64 Debian package from an already-tested Linux app.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"

APP_DIR="${CODEX_APP_DIR:-$HOME/Applications/codex-linux}"
CLI_DIR="${CODEX_CLI_DIR:-}"
NODE_BIN="${CODEX_NODE_BIN:-}"
OUTPUT_DIR="${CODEX_DEB_OUTPUT_DIR:-$REPO_ROOT/dist}"

usage() {
  cat <<'USAGE'
Usage: packaging/debian/build-deb.sh [options]

Options:
  --app-dir DIR       Tested Codex Linux app directory.
  --cli-dir DIR       Directory containing the standalone codex binary.
  --node-bin FILE     Node.js executable to bundle for Browser Use and Node REPL.
  --output-dir DIR    Directory for the resulting .deb.
  -h, --help          Show this help.

Environment equivalents: CODEX_APP_DIR, CODEX_CLI_DIR, CODEX_NODE_BIN,
CODEX_DEB_OUTPUT_DIR.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app-dir)
      APP_DIR="${2:?--app-dir requires a directory}"
      shift 2
      ;;
    --cli-dir)
      CLI_DIR="${2:?--cli-dir requires a directory}"
      shift 2
      ;;
    --node-bin)
      NODE_BIN="${2:?--node-bin requires a file}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:?--output-dir requires a directory}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$(dpkg --print-architecture)" != "amd64" ]; then
  echo "This package builder only supports an amd64 build host." >&2
  exit 1
fi

for tool in dpkg-deb dpkg node install cp find sed du; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Required tool not found: $tool" >&2
    exit 1
  }
done

APP_DIR="$(cd "$APP_DIR" && pwd)"
[ -d "$APP_DIR/.vite" ] || { echo "App directory is missing .vite: $APP_DIR" >&2; exit 1; }
[ -d "$APP_DIR/webview" ] || { echo "App directory is missing webview: $APP_DIR" >&2; exit 1; }
[ -d "$APP_DIR/node_modules" ] || { echo "App directory is missing node_modules: $APP_DIR" >&2; exit 1; }
[ -f "$APP_DIR/package.json" ] || { echo "App directory is missing package.json: $APP_DIR" >&2; exit 1; }

if [ -z "$CLI_DIR" ]; then
  for candidate in "$HOME"/.vscode/extensions/openai.chatgpt-*-linux-x64/bin/linux-x86_64; do
    if [ -x "$candidate/codex" ]; then
      CLI_DIR="$candidate"
      break
    fi
  done
fi
[ -n "$CLI_DIR" ] && [ -x "$CLI_DIR/codex" ] || {
  echo "Standalone Codex CLI not found. Pass --cli-dir." >&2
  exit 1
}
CLI_DIR="$(cd "$CLI_DIR" && pwd)"

if [ -z "$NODE_BIN" ]; then
  NODE_BIN="$(command -v node)"
fi
NODE_BIN="$(readlink -f "$NODE_BIN")"
[ -x "$NODE_BIN" ] || { echo "Node executable not found: $NODE_BIN" >&2; exit 1; }

APP_VERSION="$(node -e 'const p=require(process.argv[1]); process.stdout.write(String(p.version || "0"))' "$APP_DIR/package.json")"
APP_VERSION="${APP_VERSION%-linux}"
if ! [[ "$APP_VERSION" =~ ^[0-9][0-9A-Za-z.+:~]*$ ]]; then
  echo "Unsupported Debian upstream version: $APP_VERSION" >&2
  exit 1
fi
PACKAGE_VERSION="${APP_VERSION}-1"
PACKAGE_NAME="codex-app-linux_${PACKAGE_VERSION}_amd64.deb"

BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-app-linux-deb.XXXXXX")"
STAGE="$BUILD_ROOT/stage"
PACKAGE_TMP=""
trap 'rm -rf "$BUILD_ROOT"; [ -z "${PACKAGE_TMP:-}" ] || rm -f "$PACKAGE_TMP"' EXIT

mkdir -p "$STAGE/DEBIAN" "$STAGE/opt/codex-app-linux" \
  "$STAGE/opt/codex-app-linux/runtime/codex-cli" \
  "$STAGE/opt/codex-app-linux/runtime/node/bin" \
  "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/512x512/apps" \
  "$STAGE/usr/share/icons/hicolor/1024x1024/apps" \
  "$STAGE/usr/share/doc/codex-app-linux"

# Only copy runtime assets. This intentionally excludes every user data directory,
# including ~/.codex, auth.json, config.toml, caches, logs, and plugin state.
for entry in .vite bin native node_modules plugins webview package.json package-lock.json build-info.json codex-linux-feature-manifest.json; do
  if [ -e "$APP_DIR/$entry" ]; then
    cp -a "$APP_DIR/$entry" "$STAGE/opt/codex-app-linux/"
  fi
done
install -m 0755 "$TEMPLATE_DIR/codex-linux.sh" "$STAGE/opt/codex-app-linux/codex-linux.sh"
install -m 0755 "$TEMPLATE_DIR/codex-app" "$STAGE/usr/bin/codex-app"
install -m 0755 "$TEMPLATE_DIR/codex" "$STAGE/usr/bin/codex"
install -m 0755 "$TEMPLATE_DIR/postinst" "$STAGE/DEBIAN/postinst"
install -m 0755 "$TEMPLATE_DIR/postrm" "$STAGE/DEBIAN/postrm"
install -m 0644 "$TEMPLATE_DIR/codex.desktop" "$STAGE/usr/share/applications/codex.desktop"
install -m 0644 "$TEMPLATE_DIR/copyright" "$STAGE/usr/share/doc/codex-app-linux/copyright"
install -m 0644 "$REPO_ROOT/README.md" "$STAGE/usr/share/doc/codex-app-linux/README.md"

install -m 0755 "$NODE_BIN" "$STAGE/opt/codex-app-linux/runtime/node/bin/node"
cp -a "$CLI_DIR/." "$STAGE/opt/codex-app-linux/runtime/codex-cli/"

ICON_SOURCE="$APP_DIR/icon.png"
[ -f "$ICON_SOURCE" ] || { echo "App icon not found: $ICON_SOURCE" >&2; exit 1; }
install -m 0644 "$ICON_SOURCE" "$STAGE/usr/share/icons/hicolor/512x512/apps/codex-linux.png"
install -m 0644 "$ICON_SOURCE" "$STAGE/usr/share/icons/hicolor/1024x1024/apps/codex-linux.png"

# The source runtime and staging directories are created by the build user.
# Debian installs this tree as root, so remove inherited group/other write bits.
chmod -R go-w "$STAGE"

INSTALLED_SIZE="$(du -sk "$STAGE" | awk '{print $1}')"
sed \
  -e "s/@VERSION@/$PACKAGE_VERSION/g" \
  -e "s/@INSTALLED_SIZE@/$INSTALLED_SIZE/g" \
  "$TEMPLATE_DIR/control.in" > "$STAGE/DEBIAN/control"

mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/$PACKAGE_NAME"
PACKAGE_TMP="$OUTPUT_DIR/.${PACKAGE_NAME}.tmp"
rm -f "$PACKAGE_TMP"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(stat -c %Y "$APP_DIR/package.json")}" \
  dpkg-deb --root-owner-group --build -Zxz "$STAGE" "$PACKAGE_TMP"

dpkg-deb -f "$PACKAGE_TMP" Package Version Architecture Installed-Size
if dpkg-deb -c "$PACKAGE_TMP" | grep -E '(/auth\.json|/config\.toml|/\.codex/)'; then
  echo "Sensitive Codex state unexpectedly found in package." >&2
  exit 1
fi

mv -f "$PACKAGE_TMP" "$OUTPUT_FILE"
PACKAGE_TMP=""
echo "Built: $OUTPUT_FILE"
echo "Version: $PACKAGE_VERSION"
echo "Architecture: amd64"
echo "Installed size: ${INSTALLED_SIZE} KiB"
