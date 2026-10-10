#!/usr/bin/env bash
# Shared signature and environment helpers for Morax Garage release scripts.
# Sourced, never executed: it defines functions and sets no traps of its own.
#
# Nothing here prints the value of a signing identity, Team ID, or notary profile.
# Callers pass identifiers around by variable name; the scripts only ever report
# whether a check passed.

release_fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

release_ok() {
  printf 'OK   %s\n' "$1"
}

release_info() {
  printf '==>  %s\n' "$1"
}

# Prints the full `codesign -dvvv` block for a bundle or binary.
signature_details() {
  codesign -dvvv "$1" 2>&1 || true
}

# Extracts a single `Key=value` field from a signature block.
# Returns the first match (leaf certificate authority).
signature_field() {
  local details="$1"
  local key="$2"
  printf '%s\n' "$details" | awk -F'=' -v k="^${key}=" '$0 ~ k { sub(/^[^=]*=/, ""); print; exit }'
}

# Returns all nested bundles/frameworks/xpc that carry their own signature.
nested_signed_paths() {
  local app_path="$1"
  if [ -d "$app_path/Contents/Frameworks" ]; then
    find "$app_path/Contents/Frameworks" -type d \
      \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) \
      -print 2>/dev/null | sort
  fi
}

# Resolves the default Team ID from environment or Config/Signing.xcconfig
resolved_team_id() {
  if [ -n "${MORAX_TEAM_ID:-}" ]; then
    printf '%s\n' "$MORAX_TEAM_ID"
    return
  fi
  local root_dir="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local xcconfig="$root_dir/Config/Signing.xcconfig"
  if [ -f "$xcconfig" ]; then
    local team
    team="$(awk -F'=' '/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$xcconfig" 2>/dev/null || true)"
    if [ -n "$team" ]; then
      printf '%s\n' "$team"
      return
    fi
  fi
  printf '\n'
}

MORAX_TEAM_ID="${MORAX_TEAM_ID:-$(resolved_team_id)}"
export MORAX_TEAM_ID

# Prints the first "Developer ID Application" identity of the team found in the
# keychain search list, or nothing. Empty output is valid: preflight reports it.
resolved_sign_identity() {
  [ -n "$MORAX_TEAM_ID" ] || return 0
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' -v team="($MORAX_TEAM_ID)" \
        '$2 ~ /^Developer ID Application: / && index($2, team) { print $2; exit }'
}

# Distribution defaults, so a Mac set up with scripts/setup-notarization.sh
# releases with a plain `scripts/package_release.sh`.
MORAX_DEFAULT_NOTARY_PROFILE="morax-notary"
if [ "${ALLOW_UNNOTARIZED:-0}" != "1" ] && [ "${MORAX_ALLOW_AD_HOC:-0}" != "1" ]; then
  MORAX_SIGN_IDENTITY="${MORAX_SIGN_IDENTITY:-$(resolved_sign_identity)}"
  MORAX_NOTARY_PROFILE="${MORAX_NOTARY_PROFILE:-$MORAX_DEFAULT_NOTARY_PROFILE}"
  export MORAX_SIGN_IDENTITY MORAX_NOTARY_PROFILE
fi

# notarytool arguments selecting the stored credentials. MORAX_NOTARY_KEYCHAIN
# points at a non-default keychain (CI stores the profile in a temporary one).
notary_credential_args() {
  printf '%s\n' --keychain-profile "$MORAX_NOTARY_PROFILE"
  if [ -n "${MORAX_NOTARY_KEYCHAIN:-}" ]; then
    printf '%s\n' --keychain "$MORAX_NOTARY_KEYCHAIN"
  fi
}

# Remediation text for required environment variables.
env_var_remediation() {
  local var_name="$1"
  case "$var_name" in
    MORAX_TEAM_ID)
      printf 'Apple Developer Team ID (10 characters). See docs/DISTRIBUTION.md.'
      ;;
    MORAX_SIGN_IDENTITY)
      printf 'No "Developer ID Application" certificate of the team found in the keychain. Run scripts/setup-notarization.sh'
      ;;
    MORAX_NOTARY_PROFILE)
      printf 'notarytool keychain profile name. Create it with: xcrun notarytool store-credentials <profile-name> --apple-id <email> --team-id <team-id> --password <app-specific-password>'
      ;;
    *)
      printf 'See docs/DISTRIBUTION.md for prerequisites and configuration.'
      ;;
  esac
}

# Requires a list of environment variables to be present and non-empty.
# Reports all missing variables at once with remediation text.
# Never prints variable values.
require_env() {
  local missing=()
  local var_name
  for var_name in "$@"; do
    if [ -z "${!var_name:-}" ]; then
      missing+=("$var_name")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    printf 'FAIL missing required environment variables:\n' >&2
    for var_name in "${missing[@]}"; do
      printf '  %s — %s\n' "$var_name" "$(env_var_remediation "$var_name")" >&2
    done
    exit 64
  fi
}
