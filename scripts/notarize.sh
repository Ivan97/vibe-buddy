#!/usr/bin/env bash
# Submits the .app to Apple's notary service, waits for a verdict, staples the
# ticket into the .app so Gatekeeper accepts it offline.
#
# Requires:
#   APPLE_ID, APP_SPECIFIC_PASSWORD, TEAM_ID  — notary credentials
#   A Developer ID Application certificate in the login keychain for signing.
#
# Usage:
#   ./scripts/notarize.sh .build/release/VibeBuddy.app
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "Usage: $0 <path/to/App.app>" >&2
    exit 1
fi

: "${APPLE_ID:?APPLE_ID env var required (your Apple Developer account email)}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD env var required (app-specific pw, NOT Apple ID password)}"
: "${TEAM_ID:?TEAM_ID env var required (10-char Apple Developer team id)}"

TMP_ZIP="$(mktemp -t notarize).zip"
trap 'rm -f "$TMP_ZIP"' EXIT

echo "→ Zipping for notary submission"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$TMP_ZIP"

echo "→ Submitting to Apple notary (blocking until verdict)"
xcrun notarytool submit "$TMP_ZIP" \
    --apple-id "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

echo "→ Stapling ticket into $APP_PATH"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "✓ Notarization complete."
