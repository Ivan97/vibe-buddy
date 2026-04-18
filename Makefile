# VibeBuddy — release tooling.
# Run `make help` to see targets.

SPARKLE_VERSION ?= 2.9.1
SPARKLE_BIN     := .build/sparkle-$(SPARKLE_VERSION)/bin

.DEFAULT_GOAL := help

.PHONY: help
help:  ## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: sparkle-tools
sparkle-tools:  ## Download Sparkle's CLI tools (sign_update / generate_keys / generate_appcast).
	./scripts/bootstrap-sparkle.sh

.PHONY: sparkle-keys
sparkle-keys: sparkle-tools  ## Generate ed25519 keypair (first-time only). Private key lives in Keychain.
	$(SPARKLE_BIN)/generate_keys

.PHONY: sparkle-public-key
sparkle-public-key: sparkle-tools  ## Print current ed25519 public key (paste into project.yml:SUPublicEDKey).
	$(SPARKLE_BIN)/generate_keys -p

.PHONY: gen
gen:  ## Regenerate VibeBuddy.xcodeproj via xcodegen.
	xcodegen

.PHONY: build
build: gen  ## Build Debug.
	xcodebuild -project VibeBuddy.xcodeproj -scheme VibeBuddy -destination 'platform=macOS' build

.PHONY: test
test: gen  ## Run unit tests.
	xcodebuild -project VibeBuddy.xcodeproj -scheme VibeBuddy -destination 'platform=macOS' test

.PHONY: release
release:  ## Cut a release build. Usage: make release VERSION=0.1.0 [NOTARIZE=1]
	@test -n "$(VERSION)" || (echo "Missing VERSION. e.g.  make release VERSION=0.1.0" && exit 1)
	./scripts/release.sh $(VERSION)

.PHONY: publish
publish:  ## Upload the built release to GitHub + commit appcast. Usage: make publish VERSION=0.1.0
	@test -n "$(VERSION)" || (echo "Missing VERSION. e.g.  make publish VERSION=0.1.0" && exit 1)
	./scripts/publish.sh $(VERSION)

.PHONY: clean
clean:  ## Clean release + sparkle tool caches.
	rm -rf .build
