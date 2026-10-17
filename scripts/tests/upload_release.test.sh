#!/usr/bin/env bash
# Exercises scripts/upload_release.sh against a fake wrangler (MORAX_WRANGLER):
# no network, no Cloudflare account. Proves the R2 object key, the refusal of
# a DMG that does not match its manifest, and the read-back sha256 check.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../upload_release.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/upload-release-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
pass() { PASS=$((PASS + 1)); printf 'OK   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

# A fake project: VERSION, a DMG and the manifest package_release.sh writes.
make_project() {
    local root="$1" dmg_content="$2" manifest_sha="$3"
    mkdir -p "$root/dist/release"
    printf '9.9.9\n' > "$root/VERSION"
    printf '%s' "$dmg_content" > "$root/dist/release/MoraxGarage-9.9.9.dmg"
    printf '{ "file": "MoraxGarage-9.9.9.dmg", "sha256": "%s" }\n' "$manifest_sha" > "$root/dist/release/release.json"
}

# Fake wrangler: logs its arguments; `r2 object put` stores the file in a
# directory standing in for the bucket, `r2 object get` copies it back
# (optionally corrupted, to simulate a bad upload).
cat > "$WORK/wrangler" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
[ "$1" = whoami ] && exit 0
# r2 object put|get <bucket/key> --file <path> [...]
action="$3"; key="$4"; file=""
shift 4
while [ $# -gt 0 ]; do
    case "$1" in --file) file="$2"; shift 2 ;; *) shift ;; esac
done
case "$action" in
    put) mkdir -p "$FAKE_BUCKET/$(dirname "$key")"; cp "$file" "$FAKE_BUCKET/$key" ;;
    get) cp "$FAKE_BUCKET/$key" "$file"; if [ -n "${FAKE_CORRUPT:-}" ]; then printf 'x' >> "$file"; fi ;;
    *) exit 2 ;;
esac
FAKE
chmod +x "$WORK/wrangler"

run_upload() {
    local root="$1"
    FAKE_LOG="$WORK/log" FAKE_BUCKET="$WORK/bucket" MORAX_WRANGLER="$WORK/wrangler" \
        MORAX_PROJECT_ROOT="$root" bash "$SCRIPT"
}

dmg_sha() { shasum -a 256 "$1/dist/release/MoraxGarage-9.9.9.dmg" | awk '{print $1}'; }

# 1. Happy path: uploads to morax-downloads/garage/<file> and verifies it.
ROOT="$WORK/ok"
make_project "$ROOT" "dmg-bytes" "$(printf 'dmg-bytes' | shasum -a 256 | awk '{print $1}')"
: > "$WORK/log"
run_upload "$ROOT" > "$WORK/out" 2>&1 || { cat "$WORK/out"; fail "upload should succeed"; }
grep -q "r2 object put morax-downloads/garage/MoraxGarage-9.9.9.dmg --file $ROOT/dist/release/MoraxGarage-9.9.9.dmg --content-type application/x-apple-diskimage --remote" "$WORK/log" \
    || { cat "$WORK/log"; fail "put did not target morax-downloads/garage/MoraxGarage-9.9.9.dmg"; }
[ "$(shasum -a 256 "$WORK/bucket/morax-downloads/garage/MoraxGarage-9.9.9.dmg" | awk '{print $1}')" = "$(dmg_sha "$ROOT")" ] \
    || fail "stored object differs from the DMG"
pass "uploads the DMG to morax-downloads/garage/ and verifies it"

# 2. A DMG that does not match its manifest is never uploaded.
ROOT="$WORK/mismatch"
make_project "$ROOT" "dmg-bytes" "0000000000000000000000000000000000000000000000000000000000000000"
: > "$WORK/log"
if run_upload "$ROOT" > "$WORK/out" 2>&1; then fail "a manifest mismatch must fail"; fi
grep -q "object put" "$WORK/log" && fail "nothing may be uploaded on a manifest mismatch"
grep -q "does not match" "$WORK/out" || { cat "$WORK/out"; fail "mismatch message missing"; }
pass "refuses a DMG whose sha256 differs from release.json"

# 3. A read-back that differs from the local file fails.
ROOT="$WORK/corrupt"
make_project "$ROOT" "dmg-bytes" "$(printf 'dmg-bytes' | shasum -a 256 | awk '{print $1}')"
: > "$WORK/log"
if FAKE_CORRUPT=1 run_upload "$ROOT" > "$WORK/out" 2>&1; then fail "a corrupt read-back must fail"; fi
grep -q "read back" "$WORK/out" || { cat "$WORK/out"; fail "read-back message missing"; }
pass "fails when the object read back from R2 differs"

# 4. The retired Supabase variables are refused with a pointer to R2.
ROOT="$WORK/legacy"
make_project "$ROOT" "dmg-bytes" "$(printf 'dmg-bytes' | shasum -a 256 | awk '{print $1}')"
if MORAX_SUPABASE_URL=https://example.supabase.co run_upload "$ROOT" > "$WORK/out" 2>&1; then fail "Supabase settings must be refused"; fi
grep -q "R2" "$WORK/out" || { cat "$WORK/out"; fail "legacy message must point to R2"; }
pass "refuses the retired Supabase Storage settings"

printf '%s checks passed\n' "$PASS"
