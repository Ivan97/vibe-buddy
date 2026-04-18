# Releasing VibeBuddy

End-to-end pipeline for cutting an auto-update-capable release. Sparkle
handles the in-app "Check for Updates…" flow; GitHub hosts the artifacts.

## Flow

```
  make sparkle-keys            one-time, local machine
  (paste public key into project.yml, commit)
      ↓
  make release VERSION=0.1.0   builds .app, zips, signs with Sparkle key
      ↓
  make publish VERSION=0.1.0   uploads to GitHub Release, updates appcast.xml,
                               commits + pushes main + tag v0.1.0
      ↓
  Sparkle clients poll SUFeedURL (GitHub Pages) every 24h → pull the new zip →
  verify signature against SUPublicEDKey → install.
```

## One-time setup

### 1. Generate the ed25519 keypair

```sh
make sparkle-keys
```

This stores the **private** key in your login Keychain (never committed).
Then:

```sh
make sparkle-public-key
```

Copy the output and paste it into `project.yml`:

```yaml
SUPublicEDKey: "<paste here>"
```

Commit this change. **The public key must match the private key in the
signer's Keychain** — if you lose the private key, existing clients can
never accept another update signed with a new key.

### 2. Enable GitHub Pages

In repo Settings → Pages:
- Source: **Deploy from a branch**
- Branch: `main`
- Folder: `/ (root)`

Pages serves `https://ivan97.github.io/vibe-buddy/appcast.xml` within a
minute or two of a push. That URL matches `SUFeedURL` in `project.yml`.

> Alternative: if Pages isn't desired, swap `SUFeedURL` to
> `https://raw.githubusercontent.com/Ivan97/vibe-buddy/main/appcast.xml`
> — same content, ~5 min cache instead of Pages' ~10 min.

### 3. Install tooling

```sh
brew install xcodegen gh
gh auth login             # pick the repo's account
```

(Sparkle CLI tools are auto-downloaded into `.build/` by the scripts.)

## Each release

```sh
# 1. Sanity: tests green on main.
make test

# 2. Build + sign.
make release VERSION=0.1.0

# This does:
#   • bumps MARKETING_VERSION in project.yml + CURRENT_PROJECT_VERSION = commit count
#   • xcodegen
#   • xcodebuild archive (Release config)
#   • copies the .app out, zips it, signs with Sparkle's sign_update
#   • stashes the enclosure snippet in .build/release/enclosure.txt

# 3. Local sanity check (optional):
open -a .build/release/VibeBuddy.app

# 4. Push to GitHub + commit appcast.
make publish VERSION=0.1.0

# This does:
#   • gh release create v0.1.0 (uploads VibeBuddy-0.1.0.zip as an asset)
#   • appends an <item> to appcast.xml
#   • commits + pushes main + tag v0.1.0
```

## Notarization (recommended for public releases)

Without notarization, Gatekeeper blocks the first launch on any machine
that isn't the build machine. For wider distribution:

1. Apple Developer account ($99/yr).
2. Create a Developer ID Application certificate in Xcode → Settings →
   Accounts. This populates your login keychain.
3. Generate an app-specific password at <https://appleid.apple.com>.
4. Export credentials:

   ```sh
   export APPLE_ID="you@example.com"
   export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
   export TEAM_ID="ABCDE12345"
   ```

5. Set `DEVELOPMENT_TEAM` in `project.yml` to your team id and change
   `CODE_SIGN_IDENTITY` from `"-"` to `"Developer ID Application"`.
6. Run `NOTARIZE=1 make release VERSION=0.1.0` — the script submits the
   zip to Apple's notary, waits for the verdict, and staples the ticket
   into the .app.

## What's where

| Thing                          | Location                                         |
| ------------------------------ | ------------------------------------------------ |
| Feed URL                       | `SUFeedURL` in `project.yml` (baked into Info.plist) |
| Signing public key             | `SUPublicEDKey` in `project.yml`                 |
| Signing private key            | Login Keychain (item name: `ed25519 key for VibeBuddy`) |
| Appcast feed                   | `appcast.xml` at repo root, served via GitHub Pages |
| Release zips                   | GitHub Releases, one asset per tag `v<version>`  |
| Release scripts                | `scripts/release.sh`, `scripts/publish.sh`, `scripts/notarize.sh` |
| Sparkle CLI tools cache        | `.build/sparkle-<version>/bin/` (git-ignored)    |

## Rollback

If a release is broken:

```sh
# Remove the bad entry from appcast.xml (it's committed XML, edit by hand).
# Delete the GitHub release:
gh release delete v0.1.0 --repo Ivan97/vibe-buddy
# Drop the tag:
git tag -d v0.1.0 && git push origin :refs/tags/v0.1.0
```

Existing clients who already accepted the update have no automatic
downgrade path — cut a fresh release with a higher version that
overrides the buggy one.
