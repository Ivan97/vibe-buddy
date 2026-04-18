#!/usr/bin/env bash
# Downloads Sparkle's CLI tools (generate_keys / sign_update / generate_appcast)
# into .build/sparkle-<version>/ so the release scripts can find them. Idempotent.
set -euo pipefail

SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/.build/sparkle-$SPARKLE_VERSION"

if [[ -x "$DEST/bin/sign_update" ]]; then
    echo "→ Sparkle $SPARKLE_VERSION CLI tools already present at $DEST"
    exit 0
fi

echo "→ Fetching Sparkle $SPARKLE_VERSION CLI tools..."
mkdir -p "$DEST"
TAR_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
curl -fsSL "$TAR_URL" | tar -xJ -C "$DEST" --strip-components=1

if [[ ! -x "$DEST/bin/sign_update" ]]; then
    echo "✗ Expected $DEST/bin/sign_update but it's missing after extract." >&2
    exit 1
fi

echo "✓ Installed at $DEST/bin/"
ls "$DEST/bin/"
