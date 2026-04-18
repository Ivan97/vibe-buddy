#!/usr/bin/env bash
# Publishes a built release:
#   1. Uploads the .zip to a GitHub Release (tag v<version>).
#   2. Appends an <item> entry to appcast.xml.
#   3. Commits appcast.xml + the bumped project.yml and pushes.
#
# Prerequisite: ./scripts/release.sh <version> must have run first (writes
# .build/release/enclosure.txt). Needs `gh` CLI authenticated to the repo.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>    e.g.  $0 0.1.0" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENCLOSURE_FILE=".build/release/enclosure.txt"
if [[ ! -f "$ENCLOSURE_FILE" ]]; then
    echo "✗ $ENCLOSURE_FILE not found. Run ./scripts/release.sh $VERSION first." >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$ENCLOSURE_FILE"

if [[ "$VERSION" != "${VERSION_FROM_FILE:-$VERSION}" ]]; then : ; fi

if ! command -v gh >/dev/null; then
    echo "✗ gh CLI not found. Install with: brew install gh && gh auth login" >&2
    exit 1
fi

REPO="${GITHUB_REPO:-Ivan97/vibe-buddy}"
TAG="v$VERSION"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$ZIP_NAME"

# --- 1. GitHub Release ------------------------------------------------------

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "→ Release $TAG already exists, uploading zip (--clobber)"
    gh release upload "$TAG" "$ZIP_PATH" --repo "$REPO" --clobber
else
    echo "→ Creating release $TAG"
    gh release create "$TAG" "$ZIP_PATH" \
        --repo "$REPO" \
        --title "VibeBuddy $VERSION" \
        --generate-notes
fi

# --- 2. appcast.xml ---------------------------------------------------------

# sign_update prints: sparkle:edSignature="..." length="..."
# We already captured it in $SIG_LINE. Extract both fields cleanly.
ED_SIG=$(echo "$SIG_LINE"   | /usr/bin/sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')
LENGTH=$(echo "$SIG_LINE"   | /usr/bin/sed -nE 's/.*length="([^"]+)".*/\1/p')
if [[ -z "$ED_SIG" || -z "$LENGTH" ]]; then
    echo "✗ Couldn't parse sign_update output: $SIG_LINE" >&2
    exit 1
fi

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
MIN_MACOS="14.0"

NEW_ITEM=$(cat <<EOF
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
      <enclosure
        url="$DOWNLOAD_URL"
        sparkle:edSignature="$ED_SIG"
        length="$LENGTH"
        type="application/octet-stream" />
    </item>
EOF
)

# Insert the new <item> directly after <language>...</language>.
# Use python for reliable XML-ish editing — portable across macOS / Linux.
python3 - "$ROOT/appcast.xml" "$NEW_ITEM" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
new_item = sys.argv[2]
text = path.read_text(encoding="utf-8")
marker = "</language>"
idx = text.find(marker)
if idx < 0:
    sys.exit(f"✗ Couldn't find {marker!r} in {path}")
insert_at = idx + len(marker)
updated = text[:insert_at] + "\n" + new_item + text[insert_at:]
path.write_text(updated, encoding="utf-8")
PY

echo "→ appcast.xml updated"

# --- 3. commit + push + tag -------------------------------------------------

if ! git diff --quiet project.yml appcast.xml; then
    echo "→ Committing version bump + appcast entry"
    git add project.yml appcast.xml
    git commit -m "chore(release): $VERSION"
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    git tag -a "$TAG" -m "VibeBuddy $VERSION"
fi

echo "→ Pushing to origin"
git push origin HEAD
git push origin "$TAG"

cat <<EOF

✅ Published $VERSION
   Release:   https://github.com/$REPO/releases/tag/$TAG
   Download:  $DOWNLOAD_URL
   Feed:      check project.yml's SUFeedURL — Sparkle will pick this up on next scheduled check.
EOF
