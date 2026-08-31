#!/usr/bin/env bash
#
# Assembles the USB stick that installs the display on a Windows PC.
#
#   ./tools/build-usb.sh [output-directory]
#
# Produces a folder you copy wholesale onto a USB stick. It carries its own Node
# runtime and dependencies, so the display PC needs nothing preinstalled and no
# internet connection during setup.

set -euo pipefail

NODE_VERSION="v24.20.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$HOME/Downloads/CathedralScheduleDisplay-USB}"
CACHE="${TMPDIR:-/tmp}/cathedral-node-cache"

say() { printf '\n\033[36m>> %s\033[0m\n' "$1"; }

say "Fetching the Windows Node runtime ($NODE_VERSION)"
mkdir -p "$CACHE"
NODE_EXE="$CACHE/node-$NODE_VERSION-win-x64/node.exe"

if [ ! -f "$NODE_EXE" ]; then
  ZIP="$CACHE/node-$NODE_VERSION-win-x64.zip"
  curl -fsSL -o "$ZIP" "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-win-x64.zip"
  curl -fsSL -o "$CACHE/SHASUMS256.txt" "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt"

  # Never ship a binary we have not checked against the published checksum.
  expected="$(grep "node-$NODE_VERSION-win-x64.zip" "$CACHE/SHASUMS256.txt" | awk '{print $1}')"
  actual="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    echo "Checksum mismatch for the Node download. Refusing to build." >&2
    exit 1
  fi
  echo "   checksum verified"

  unzip -o -q "$ZIP" "node-$NODE_VERSION-win-x64/node.exe" -d "$CACHE"
else
  echo "   using cached runtime"
fi

say "Installing production dependencies"
(cd "$REPO_ROOT" && npm install --omit=dev --silent)

say "Assembling $OUTPUT"
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/app/runtime"

cp "$REPO_ROOT/usb/INSTALL.bat" "$OUTPUT/"
cp "$REPO_ROOT/usb/UNINSTALL.bat" "$OUTPUT/"
cp "$REPO_ROOT/usb/READ ME FIRST.txt" "$OUTPUT/"

for dir in src public config tools windows; do
  cp -R "$REPO_ROOT/$dir" "$OUTPUT/app/"
done

# Dependencies travel as one zip rather than 1,500 loose files: a cheap USB
# stick writes small files at a crawl, and the installer expands it in seconds.
say "Packing dependencies"
(cd "$REPO_ROOT" && zip -rq "$OUTPUT/app/node_modules.zip" node_modules -x '*.DS_Store' '._*')
for file in package.json package-lock.json README.md .env.example; do
  cp "$REPO_ROOT/$file" "$OUTPUT/app/"
done
cp "$NODE_EXE" "$OUTPUT/app/runtime/node.exe"

# The stick is for installing, not for building.
rm -rf "$OUTPUT/app/tools/build-usb.sh"

# macOS writes AppleDouble sidecars onto FAT32 volumes, which look like junk on
# Windows. Keep them out of the build so a plain drag-and-drop copy stays clean.
export COPYFILE_DISABLE=1
find "$OUTPUT" -name '._*' -delete 2>/dev/null || true
find "$OUTPUT" -name '.DS_Store' -delete 2>/dev/null || true

say "Done"
du -sh "$OUTPUT"
echo
echo "Copy the CONTENTS of this folder onto a USB stick:"
echo "  $OUTPUT"
echo
echo "On the display PC, double-click INSTALL.bat"
