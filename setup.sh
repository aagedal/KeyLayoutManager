#!/usr/bin/env bash
# Bootstrap: install XcodeGen if missing, generate PremiereKeyboarder.xcodeproj.
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "→ Installing xcodegen via Homebrew…"
        brew install xcodegen
    else
        echo "✗ xcodegen not found and Homebrew not installed."
        echo "  Install Homebrew from https://brew.sh, then re-run ./setup.sh"
        exit 1
    fi
fi

ACTIVE_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$ACTIVE_DEV_DIR" != *"Xcode.app"* ]]; then
    if [[ -d "/Applications/Xcode.app" ]]; then
        echo "ℹ️  Active developer dir is '$ACTIVE_DEV_DIR'."
        echo "    To build the .app you'll need full Xcode selected. Run:"
        echo "      sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    fi
fi

echo "→ Generating Xcode project…"
xcodegen generate

echo
echo "✓ Done."
echo "  Open with: open PremiereKeyboarder.xcodeproj"
