#!/usr/bin/env bash
# Builds and installs Morax Garage from source.
#
#   curl -fsSL https://raw.githubusercontent.com/Etienne-Morax/morax-garage/main/scripts/install-from-source.sh | bash
#
# Environment:
#   MORAX_REF         Branch or tag to install (default: repository default branch)
#   MORAX_REPO_URL    Override the git remote (default: public GitHub repository)
#   MORAX_SRC_DIR     Checkout location (default: ~/Library/Caches/morax-garage-src)
#   MORAX_RUN_TESTS   Set to 1 to also run the test suite before installing

set -euo pipefail

REPO_URL="${MORAX_REPO_URL:-https://github.com/Etienne-Morax/morax-garage.git}"
SRC_DIR="${MORAX_SRC_DIR:-$HOME/Library/Caches/morax-garage-src}"
MIN_MACOS_MAJOR=14

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

info() {
    printf '==> %s\n' "$1"
}

[ "$(uname -s)" = "Darwin" ] || fail "Morax Garage only runs on macOS."

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MACOS_MAJOR" -lt "$MIN_MACOS_MAJOR" ]; then
    fail "macOS $MIN_MACOS_MAJOR or later is required (found $(sw_vers -productVersion)). Update macOS and retry."
fi

command -v git >/dev/null 2>&1 || fail "git not found. Install the Xcode Command Line Tools: xcode-select --install"

if ! command -v swift >/dev/null 2>&1 || ! swift --version >/dev/null 2>&1; then
    fail "swift not found. Install Xcode or the Command Line Tools (xcode-select --install), then retry."
fi
SWIFT_VERSION_LINE="$(swift --version 2>&1 | head -n 1)"
SWIFT_MAJOR="$(printf '%s\n' "$SWIFT_VERSION_LINE" | sed -n 's/.*Swift version \([0-9][0-9]*\).*/\1/p')"
if [ -z "$SWIFT_MAJOR" ] || [ "$SWIFT_MAJOR" -lt 6 ]; then
    fail "Swift 6 or later is required (found: $SWIFT_VERSION_LINE). Update Xcode or the Command Line Tools."
fi

info "Fetching sources into $SRC_DIR"
if [ -d "$SRC_DIR/.git" ]; then
    git -C "$SRC_DIR" remote set-url origin "$REPO_URL"
    git -C "$SRC_DIR" fetch --tags --prune origin
else
    [ ! -e "$SRC_DIR" ] || fail "$SRC_DIR exists and is not a git checkout. Remove it or set MORAX_SRC_DIR."
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone "$REPO_URL" "$SRC_DIR"
fi

if [ -n "${MORAX_REF:-}" ]; then
    git -C "$SRC_DIR" checkout --force --detach "$MORAX_REF" 2>/dev/null \
        || git -C "$SRC_DIR" checkout --force --detach "origin/$MORAX_REF" \
        || fail "ref '$MORAX_REF' not found in $REPO_URL"
else
    DEFAULT_BRANCH="$(git -C "$SRC_DIR" remote show origin | sed -n 's/.*HEAD branch: //p')"
    [ -n "$DEFAULT_BRANCH" ] || fail "could not determine the default branch of $REPO_URL"
    git -C "$SRC_DIR" checkout --force --detach "origin/$DEFAULT_BRANCH"
fi
info "Building revision $(git -C "$SRC_DIR" rev-parse --short HEAD)"

cd "$SRC_DIR"
MORAX_SKIP_TESTS=$([ "${MORAX_RUN_TESTS:-0}" = "1" ] && echo 0 || echo 1) \
    bash scripts/install.sh

printf '\nInstalled: /Applications/Morax Garage.app and /Applications/Morax Garage Menu.app\n'
printf 'Built from source with an ad-hoc signature: if macOS blocks the first launch, right-click the app and choose Open.\n'
