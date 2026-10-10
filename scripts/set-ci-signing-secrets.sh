#!/usr/bin/env bash
# Uploads the Developer ID certificate and an App Store Connect API key to the
# GitHub repository secrets read by .github/workflows/release.yml.
#
#   scripts/set-ci-signing-secrets.sh <developer-id.p12> <AuthKey_XXXX.p8> <key-id> <issuer-id>
#
# The .p12 password is read from a hidden prompt. Values go to `gh secret set`
# on stdin and are never printed.
#
# Environment:
#   MORAX_GITHUB_REPO   Target repository (default: Etienne-Morax/morax-garage)

set -euo pipefail

REPO="${MORAX_GITHUB_REPO:-Etienne-Morax/morax-garage}"

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

[ "$#" -eq 4 ] || fail "usage: $0 <developer-id.p12> <AuthKey_XXXX.p8> <key-id> <issuer-id>"
P12_PATH="$1"
P8_PATH="$2"
KEY_ID="$3"
ISSUER_ID="$4"

[ -f "$P12_PATH" ] || fail "certificate not found: $P12_PATH"
[ -f "$P8_PATH" ] || fail "API key not found: $P8_PATH"
command -v gh >/dev/null 2>&1 || fail "gh not found: brew install gh && gh auth login"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated: gh auth login"
[ -t 0 ] || fail "run in an interactive terminal (the .p12 password is prompted)"

printf 'Password of %s: ' "$(basename "$P12_PATH")"
read -r -s P12_PASSWORD
printf '\n'
[ -n "$P12_PASSWORD" ] || fail "empty password"
export P12_PASSWORD

# Check the password and that the file really holds a Developer ID Application identity.
P12_SUBJECTS="$(openssl pkcs12 -in "$P12_PATH" -nokeys -passin env:P12_PASSWORD 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null)" \
    || P12_SUBJECTS="$(openssl pkcs12 -legacy -in "$P12_PATH" -nokeys -passin env:P12_PASSWORD 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null)" \
    || fail "cannot read $P12_PATH with that password"
case "$P12_SUBJECTS" in
    *"Developer ID Application"*) ;;
    *) fail "$P12_PATH does not contain a Developer ID Application certificate" ;;
esac

base64 -i "$P12_PATH" | gh secret set MACOS_DEVELOPER_ID_P12_BASE64 -R "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set MACOS_DEVELOPER_ID_P12_PASSWORD -R "$REPO"
base64 -i "$P8_PATH" | gh secret set NOTARY_API_KEY_P8_BASE64 -R "$REPO"
printf '%s' "$KEY_ID" | gh secret set NOTARY_API_KEY_ID -R "$REPO"
printf '%s' "$ISSUER_ID" | gh secret set NOTARY_API_ISSUER_ID -R "$REPO"

printf 'OK  Signing secrets set on %s. The next v* tag publishes a notarized release.\n' "$REPO"
