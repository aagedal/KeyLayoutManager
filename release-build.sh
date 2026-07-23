#!/usr/bin/env bash
# KeyLayoutManager
# Copyright © 2026 Truls Aagedal
#
# Build, sign, notarize, and publish a new release. After completing the build
# pipeline this script signs the resulting .zip with Sparkle's EdDSA key and
# appends a new <item> to appcast.xml so existing installs auto-update.
#
# Prerequisites (one-time setup):
#   1. Sparkle SDK is wired up via SPM (see project.yml).
#   2. EdDSA private key is in your Keychain. We reuse the same key as
#      Aagedal Media Converter — sign_update finds it by service name, no
#      per-app configuration needed. The matching public key is set as
#      SUPublicEDKey in Info.plist.
#   3. notarytool credentials stored in Keychain as the profile name below.
#      Set up once with:
#        xcrun notarytool store-credentials Notary \
#          --apple-id <appleid> --team-id <teamid> --password <app-specific-pw>
#   4. GitHub CLI (`gh`) installed and authenticated (or the script will skip
#      the upload step and print manual release instructions).
#
# Usage:
#   ./release-build.sh                 # uses MARKETING_VERSION from the project
#   ./release-build.sh 0.2.0 2         # override version + build number
#
set -euo pipefail

echo "==> release-build.sh starting"

# -----------------------------------------------------------------------------
# Toolchain resolution
# -----------------------------------------------------------------------------
# `xcode-select` is sometimes left pointing at /Library/Developer/CommandLineTools
# (e.g. after a CLI-tools update). In that state `xcodebuild` errors out and,
# combined with `set -e`, would kill this script silently on the first line that
# touches it. Resolve a usable Xcode here so the rest of the script can assume
# it works.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if ! xcrun --find xcodebuild >/dev/null 2>&1; then
        if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
            export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
            echo "    (auto-set DEVELOPER_DIR=$DEVELOPER_DIR — \`xcode-select -p\` pointed at CommandLineTools)"
        else
            echo "ERROR: xcodebuild not available. Run:" >&2
            echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
            echo "or export DEVELOPER_DIR to a valid Xcode install." >&2
            exit 1
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-Notary}"
SIGN_UPDATE_BIN="${SIGN_UPDATE_BIN:-./bin/sign_update}"
GITHUB_REPOSITORY="aagedal/KeyLayoutManager"
APPCAST="appcast.xml"

PROJECT="KeyLayoutManager.xcodeproj"
SCHEME="KeyLayoutManager"

# -----------------------------------------------------------------------------
# Resolve version / build
# -----------------------------------------------------------------------------
if [[ -z "${1:-}" || -z "${2:-}" ]]; then
    echo "    Reading version from xcodebuild -showBuildSettings (takes a few seconds)…"
    BUILD_SETTINGS=$(xcodebuild -project "$PROJECT" -showBuildSettings -scheme "$SCHEME")
fi
if [[ -n "${1:-}" ]]; then
    MARKETING_VERSION="$1"
else
    MARKETING_VERSION=$(echo "$BUILD_SETTINGS" | awk -F' = ' '/^[[:space:]]*MARKETING_VERSION/{print $2; exit}')
fi
if [[ -n "${2:-}" ]]; then
    CURRENT_PROJECT_VERSION="$2"
else
    CURRENT_PROJECT_VERSION=$(echo "$BUILD_SETTINGS" | awk -F' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION/{print $2; exit}')
fi

echo "==> Building $MARKETING_VERSION ($CURRENT_PROJECT_VERSION)"

# -----------------------------------------------------------------------------
# Build & export
# -----------------------------------------------------------------------------
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/KeyLayoutManager.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Inline export options — Developer ID, no provisioning profile rewriting.
cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>           <string>developer-id</string>
    <key>signingStyle</key>     <string>automatic</string>
    <key>destination</key>      <string>export</string>
</dict>
</plist>
EOF

# ARCHS=arm64 ONLY_ACTIVE_ARCH=NO: keep SwiftPM dependencies (Sparkle) from
# also compiling an x86_64 slice that the arm64-only main target would discard
# at link time.
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$EXPORT_DIR/$SCHEME.app"
[[ -d "$APP_PATH" ]] || { echo "Build produced no .app at $APP_PATH" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Notarize & staple
# -----------------------------------------------------------------------------
NOTARIZE_ZIP="$BUILD_DIR/notarize-input.zip"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

echo "==> Submitting to notarytool (profile: $NOTARYTOOL_PROFILE)"
xcrun notarytool submit "$NOTARIZE_ZIP" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# -----------------------------------------------------------------------------
# Final zip for distribution + Sparkle signature
# -----------------------------------------------------------------------------
# --norsrc --noextattr --noacl --noqtn: skip AppleDouble metadata. Without
# these flags ditto encodes xattrs (com.apple.provenance et al.), ACLs, and
# creation dates as `._<name>` companion files inside the zip. macOS Sequoia's
# Archive Utility no longer transparently merges those companions back into
# xattrs on extract; they instead surface as visible files inside the .app,
# which breaks the codesignature seal ("a sealed resource is missing or
# invalid") and Gatekeeper rejects the bundle as "damaged". The signature and
# notarization staple live inside the bundle (CodeResources + Mach-O LC), not
# in xattrs, so dropping the AppleDouble layer is safe.
SAFE_VERSION="${MARKETING_VERSION//./-}"
RELEASE_ZIP_NAME="KeyLayoutManager_${SAFE_VERSION}.zip"
RELEASE_ZIP="$BUILD_DIR/$RELEASE_ZIP_NAME"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr --noacl --noqtn "$APP_PATH" "$RELEASE_ZIP"

ZIP_SIZE=$(/usr/bin/stat -f%z "$RELEASE_ZIP")
echo "==> Release zip: $RELEASE_ZIP ($ZIP_SIZE bytes)"

if [[ ! -x "$SIGN_UPDATE_BIN" ]]; then
    echo "ERROR: $SIGN_UPDATE_BIN not found. Build Sparkle's sign_update tool first." >&2
    echo "       (See Sparkle's docs — the binary lives in their built products dir.)" >&2
    exit 1
fi

ED_SIGNATURE_LINE=$("$SIGN_UPDATE_BIN" "$RELEASE_ZIP")
echo "==> Sparkle signature: $ED_SIGNATURE_LINE"

# `sign_update` prints something like:
#   sparkle:edSignature="abc..." length="12345"
# We already have length from stat, so just extract the signature value.
ED_SIGNATURE=$(echo "$ED_SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')

# -----------------------------------------------------------------------------
# Upload to GitHub release
# -----------------------------------------------------------------------------
DOWNLOAD_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$MARKETING_VERSION/$RELEASE_ZIP_NAME"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh release view "$MARKETING_VERSION" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
        echo "==> Uploading $RELEASE_ZIP_NAME to existing GitHub release $MARKETING_VERSION"
        gh release upload "$MARKETING_VERSION" "$RELEASE_ZIP" \
            --repo "$GITHUB_REPOSITORY" \
            --clobber
    else
        echo "==> Creating GitHub release $MARKETING_VERSION"
        gh release create "$MARKETING_VERSION" "$RELEASE_ZIP" \
            --repo "$GITHUB_REPOSITORY" \
            --target main \
            --title "$MARKETING_VERSION" \
            --generate-notes
    fi
else
    echo "==> GitHub CLI is unavailable or unauthenticated — skipping upload."
    echo "    1. Create release $MARKETING_VERSION at https://github.com/$GITHUB_REPOSITORY/releases/new"
    echo "    2. Attach $RELEASE_ZIP"
fi

# -----------------------------------------------------------------------------
# Append appcast.xml entry
# -----------------------------------------------------------------------------
PUB_DATE=$(date "+%a, %d %b %Y %H:%M:%S %z")
RELEASE_NOTES_HTML="                <p>See <a href=\"https://github.com/$GITHUB_REPOSITORY/releases/tag/$MARKETING_VERSION\">release notes</a>.</p>"

NEW_ITEM=$(cat <<EOF
        <item>
            <title>Version $MARKETING_VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$CURRENT_PROJECT_VERSION</sparkle:version>
            <sparkle:shortVersionString>$MARKETING_VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="$DOWNLOAD_URL"
                length="$ZIP_SIZE"
                type="application/octet-stream"
                sparkle:edSignature="$ED_SIGNATURE" />
            <description><![CDATA[
$RELEASE_NOTES_HTML
            ]]></description>
        </item>
EOF
)

python3 - "$APPCAST" "$NEW_ITEM" <<'PYEOF'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
new_item = sys.argv[2]
text = path.read_text()
needle = "    </channel>"
if needle not in text:
    raise SystemExit(f"Could not find '{needle.strip()}' in {path}")
text = text.replace(needle, new_item + "\n" + needle, 1)
path.write_text(text)
PYEOF

echo "==> Appended appcast entry. Review and commit:"
echo "    git diff $APPCAST"
echo "    git add $APPCAST && git commit -m \"Release $MARKETING_VERSION\" && git push"

SHA256=$(shasum -a 256 "$RELEASE_ZIP" | awk '{print $1}')
echo "==> SHA256 of release zip: $SHA256"
