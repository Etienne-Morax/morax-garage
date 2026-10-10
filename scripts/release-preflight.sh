#!/usr/bin/env bash
# Asserts that this machine can produce a distributable Developer ID build,
# before any expensive compilation runs.
# Exits with status 64 and per-variable remediation when the environment is incomplete.
#
# Never prints the value of a Team ID, identity name, or notary profile.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib-codesign.sh"

cd "$PROJECT_ROOT"

# Check VERSION file
if [ ! -f "$PROJECT_ROOT/VERSION" ]; then
  release_fail "VERSION file not found at $PROJECT_ROOT/VERSION"
fi
VERSION="$(cat "$PROJECT_ROOT/VERSION" | tr -d '[:space:]')"
if [ -z "$VERSION" ]; then
  release_fail "VERSION file is empty"
fi
release_ok "VERSION file present ($VERSION)"

# Check required tooling
for tool in swift lipo codesign hdiutil iconutil xcrun shasum stat; do
  command -v "$tool" >/dev/null 2>&1 || release_fail "required tool not on PATH: $tool"
done

if [ ! -x /usr/libexec/PlistBuddy ]; then
  release_fail "PlistBuddy not found at /usr/libexec/PlistBuddy"
fi
release_ok 'required CLI tooling present (swift, lipo, codesign, hdiutil, iconutil, PlistBuddy, ...)'

# If running in local unnotarized mode (explicitly permitted for dev / dry-run)
if [ "${ALLOW_UNNOTARIZED:-0}" = "1" ] || [ "${MORAX_ALLOW_AD_HOC:-0}" = "1" ]; then
  printf 'WARN ALLOW_UNNOTARIZED=1 is set: skipping Developer ID identity and notary profile checks.\n' >&2
  printf 'WARN The resulting build will be ad-hoc signed and unnotarized.\n' >&2
  release_ok 'preflight passed (unnotarized dev mode)'
  exit 0
fi

# Production release mode checks
require_env MORAX_SIGN_IDENTITY MORAX_NOTARY_PROFILE
release_ok 'required environment variables are set'

if [ -n "${MORAX_TEAM_ID:-}" ]; then
  if [[ ! "$MORAX_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    release_fail 'MORAX_TEAM_ID is not a valid 10-character Apple Team ID'
  fi
  release_ok 'MORAX_TEAM_ID has expected shape'
fi

# Check that the identity exists in keychain
if ! security find-identity -v -p codesigning | grep -Fq "$MORAX_SIGN_IDENTITY"; then
  release_fail 'MORAX_SIGN_IDENTITY not found in keychain (run scripts/setup-notarization.sh, or list with: security find-identity -v -p codesigning)'
fi
release_ok 'signing identity found in keychain'

# Check that it is a Developer ID Application certificate
if ! printf '%s' "$MORAX_SIGN_IDENTITY" | grep -Fq 'Developer ID Application'; then
  release_fail 'MORAX_SIGN_IDENTITY is not a "Developer ID Application" certificate; distribution builds require one'
fi
release_ok 'signing identity is a Developer ID Application certificate'

# Check that notarytool profile is configured and usable
NOTARY_ARGS=()
while IFS= read -r arg; do NOTARY_ARGS+=("$arg"); done < <(notary_credential_args)
if ! xcrun notarytool history "${NOTARY_ARGS[@]}" >/dev/null 2>&1; then
  release_fail 'notarytool cannot use MORAX_NOTARY_PROFILE (run scripts/setup-notarization.sh)'
fi
release_ok 'notarytool keychain profile is usable'

release_ok 'preflight passed'
