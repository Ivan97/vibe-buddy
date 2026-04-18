#!/usr/bin/env bash
# Builds a Release archive of VibeBuddy, zips the .app, and signs the zip with
# Sparkle's ed25519 private key (stored in Keychain by `generate_keys`).
#
# Usage:
#   ./scripts/release.sh 0.1.0
#   NOTARIZE=1 ./scripts/release.sh 0.1.0   # also run notarization (needs Apple creds)
#
# On success, prints the appcast <enclosure> line you'll need — or run
# ./scripts/publish.sh to do the GitHub release + appcast commit for you.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>    e.g.  $0 0.1.0" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RELEASE_DIR=".build/release"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.1}"
SPARKLE_BIN=".build/sparkle-$SPARKLE_VERSION/bin"
ZIP_NAME="VibeBuddy-$VERSION.zip"
NOTARIZE="${NOTARIZE:-0}"

# --- pre-flight -------------------------------------------------------------

if ! command -v xcodegen >/dev/null; then
    echo "✗ xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

PUB_KEY=$(awk -F '"' '/SUPublicEDKey:/ {print $2}' project.yml | head -1)
if [[ -z "$PUB_KEY" ]]; then
    cat >&2 <<EOF
✗ project.yml:SUPublicEDKey is empty.

First-time setup:
  make sparkle-keys         # generates ed25519 keypair, stores private in Keychain
  make sparkle-public-key   # prints the public key
  # Paste the public key into project.yml's SUPublicEDKey, commit, then re-run.
EOF
    exit 1
fi

./scripts/bootstrap-sparkle.sh

# --- bump version in project.yml --------------------------------------------

echo "→ Setting MARKETING_VERSION=$VERSION in project.yml"
# GNU vs BSD sed compatibility — we're on macOS so BSD sed.
/usr/bin/sed -i '' -E "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml

# Use commit distance as CFBundleVersion so Sparkle's version compare works
# monotonically even when the marketing string repeats (pre-release / rc).
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml

echo "→ Regenerating Xcode project"
xcodegen > /dev/null

# --- build ------------------------------------------------------------------

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "→ Archiving (Release)"
xcodebuild \
    -project VibeBuddy.xcodeproj \
    -scheme VibeBuddy \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath "$RELEASE_DIR/VibeBuddy.xcarchive" \
    archive \
    | grep -E '^(===|⚠|error:|warning:|\*\*)' || true

APP_IN_ARCHIVE="$RELEASE_DIR/VibeBuddy.xcarchive/Products/Applications/VibeBuddy.app"
if [[ ! -d "$APP_IN_ARCHIVE" ]]; then
    echo "✗ Archive produced no .app at $APP_IN_ARCHIVE" >&2
    exit 1
fi

echo "→ Staging .app"
cp -R "$APP_IN_ARCHIVE" "$RELEASE_DIR/VibeBuddy.app"

# --- notarize (optional) ----------------------------------------------------

if [[ "$NOTARIZE" = "1" ]]; then
    echo "→ Notarizing"
    ./scripts/notarize.sh "$RELEASE_DIR/VibeBuddy.app"
else
    echo "⚠ Skipping notarization (NOTARIZE=0). First-run Gatekeeper will block on other machines."
fi

# --- zip + sign -------------------------------------------------------------

echo "→ Zipping into $ZIP_NAME"
(cd "$RELEASE_DIR" && /usr/bin/ditto -c -k --keepParent VibeBuddy.app "$ZIP_NAME")

echo "→ Signing with Sparkle's ed25519 key"
SIG_LINE=$("$SPARKLE_BIN/sign_update" "$RELEASE_DIR/$ZIP_NAME")

ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
ZIP_SIZE=$(stat -f %z "$ZIP_PATH")

# Stash the enclosure snippet for publish.sh.
cat > "$RELEASE_DIR/enclosure.txt" <<EOF
VERSION=$VERSION
BUILD_NUMBER=$BUILD_NUMBER
ZIP_NAME=$ZIP_NAME
ZIP_PATH=$ZIP_PATH
ZIP_SIZE=$ZIP_SIZE
SIG_LINE=$SIG_LINE
EOF

cat <<EOF

✅ Release artifact ready
   → $ZIP_PATH  ($ZIP_SIZE bytes)

Sparkle signature:
   $SIG_LINE

Next:
  • Quick-test locally:        open -a "$RELEASE_DIR/VibeBuddy.app"
  • Publish to GitHub:         ./scripts/publish.sh $VERSION
EOF
