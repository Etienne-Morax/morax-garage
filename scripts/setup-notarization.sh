#!/usr/bin/env bash
# One-time setup of Developer ID signing and notarization on this Mac.
#
#   scripts/setup-notarization.sh
#
# Checks that a "Developer ID Application" certificate of the team is in the
# keychain, then stores notarytool credentials under the profile used by
# scripts/package_release.sh. Credentials are typed into notarytool's own
# prompts and never pass through this script.
#
# Environment:
#   MORAX_TEAM_ID         Team ID (default: Config/Signing.xcconfig)
#   MORAX_NOTARY_PROFILE  Profile name (default: morax-notary)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib-codesign.sh
source "$SCRIPT_DIR/lib-codesign.sh"

[ -n "$MORAX_TEAM_ID" ] || release_fail "No Team ID: set MORAX_TEAM_ID or DEVELOPMENT_TEAM in Config/Signing.xcconfig"

release_info "Step 1/2: Developer ID Application certificate (team $MORAX_TEAM_ID)"
if [ -z "$MORAX_SIGN_IDENTITY" ]; then
    cat >&2 <<HELP
FAIL No "Developer ID Application" certificate for team $MORAX_TEAM_ID in the keychain.

Create it once (requires the Account Holder role):
  1. Open Xcode > Settings > Accounts, select your Apple ID and team $MORAX_TEAM_ID.
  2. Click "Manage Certificates…", then "+" > "Developer ID Application".
  3. Re-run this script.

Alternative: developer.apple.com > Certificates > "+" > Developer ID Application,
upload a CSR from Keychain Access, then double-click the downloaded .cer.
HELP
    exit 1
fi
release_ok "Found: $MORAX_SIGN_IDENTITY"

release_info "Step 2/2: notarytool profile '$MORAX_NOTARY_PROFILE'"
if xcrun notarytool history --keychain-profile "$MORAX_NOTARY_PROFILE" >/dev/null 2>&1; then
    release_ok "Profile already stored and usable"
else
    [ -t 0 ] || release_fail "Run this step in an interactive terminal: notarytool prompts for your credentials."
    cat <<HELP
notarytool will prompt for your Apple ID and an app-specific password
(create one at https://account.apple.com > Sign-In and Security > App-Specific Passwords).
HELP
    xcrun notarytool store-credentials "$MORAX_NOTARY_PROFILE" --team-id "$MORAX_TEAM_ID"
    xcrun notarytool history --keychain-profile "$MORAX_NOTARY_PROFILE" >/dev/null \
        || release_fail "Stored profile is not usable; re-run and check the Apple ID and password."
    release_ok "Profile stored in the login keychain"
fi

printf '\nReady. Produce a notarized release with:\n  scripts/package_release.sh\n'
printf 'To notarize GitHub Releases too, see "Notarized releases in CI" in docs/DISTRIBUTION.md.\n'
