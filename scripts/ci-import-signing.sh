#!/usr/bin/env bash
# Imports the Developer ID certificate and notary API key from GitHub Actions
# secrets into a temporary keychain and stores the notarytool profile there.
# With no secret set it reports configured=false and the release stays ad-hoc;
# with only some of them set it fails, so a half-configured repo never ships
# a release that silently skipped notarization.

set -euo pipefail

: "${GITHUB_OUTPUT:?must run inside GitHub Actions}"
: "${GITHUB_ENV:?must run inside GitHub Actions}"
: "${RUNNER_TEMP:?must run inside GitHub Actions}"

SECRET_VARS=(P12_BASE64 P12_PASSWORD NOTARY_KEY_P8_BASE64 NOTARY_KEY_ID NOTARY_ISSUER_ID)
NOTARY_PROFILE="${MORAX_NOTARY_PROFILE:-morax-notary}"

set_count=0
for var in "${SECRET_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then
        set_count=$((set_count + 1))
    fi
done

if [ "$set_count" -eq 0 ]; then
    echo "configured=false" >> "$GITHUB_OUTPUT"
    echo "No signing secrets configured: building an ad-hoc, unnotarized release."
    exit 0
fi

if [ "$set_count" -ne "${#SECRET_VARS[@]}" ]; then
    for var in "${SECRET_VARS[@]}"; do
        [ -n "${!var:-}" ] || echo "::error::Signing secret for $var is missing (see docs/DISTRIBUTION.md)"
    done
    exit 1
fi

WORK_DIR="$RUNNER_TEMP/morax-signing"
mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"
KEYCHAIN="$WORK_DIR/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
KEYCHAIN_LOCK_TIMEOUT_SECONDS=21600

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut "$KEYCHAIN_LOCK_TIMEOUT_SECONDS" "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

printf '%s' "$P12_BASE64" | base64 --decode > "$WORK_DIR/developer-id.p12"
security import "$WORK_DIR/developer-id.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
rm -f "$WORK_DIR/developer-id.p12"

# Put the temporary keychain first in the search list so codesign finds the identity.
SEARCH_LIST=("$KEYCHAIN")
while IFS= read -r entry; do
    SEARCH_LIST+=("$(printf '%s' "$entry" | sed -e 's/^[[:space:]]*"//' -e 's/"$//')")
done < <(security list-keychains -d user)
security list-keychains -d user -s "${SEARCH_LIST[@]}"

printf '%s' "$NOTARY_KEY_P8_BASE64" | base64 --decode > "$WORK_DIR/notary-key.p8"
xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --key "$WORK_DIR/notary-key.p8" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --keychain "$KEYCHAIN" >/dev/null
rm -f "$WORK_DIR/notary-key.p8"

echo "MORAX_NOTARY_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
echo "configured=true" >> "$GITHUB_OUTPUT"
echo "Developer ID certificate and notary profile imported into a temporary keychain."
