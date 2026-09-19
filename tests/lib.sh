#!/usr/bin/env bash
# Shared helpers for the fleetbase-railway tests. Source this file; do not execute it.
#
# Fleetbase's console talks to the API over its internal JSON API:
#   POST /int/v1/auth/login {identity, password}  -> 200 {"token": "..."}
#   Authorization: Bearer <token>                 -> the rest of /int/v1/*
# The owner password is never printed and never passed on argv: tests read it from a file
# (OWNER_PASSWORD_FILE) or from the environment set by the caller.

: "${API_URL:=http://127.0.0.1:8080}"
: "${CONSOLE_URL:=http://127.0.0.1:4200}"
: "${TEST_TIMEOUT:=900}"
: "${OWNER_EMAIL:=owner@kwentra.com}"

if [ -n "${OWNER_PASSWORD_FILE:-}" ] && [ -r "${OWNER_PASSWORD_FILE}" ]; then
  OWNER_PASSWORD="$(cat "$OWNER_PASSWORD_FILE")"
fi
: "${OWNER_PASSWORD:?OWNER_PASSWORD or OWNER_PASSWORD_FILE must be set}"
export OWNER_PASSWORD

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
chmod 700 "$TEST_TMP"
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: unexpectedly contains [$2]"; else pass "$1"; fi; }
# Fixed-string variant, for patterns containing regex metacharacters (e.g. "[::]").
assert_contains_f() { if grep -qF -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 60 "$@" || true; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url")
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1
    fi
    sleep 5
  done
}

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }

# ---------------------------------------------------------------- Fleetbase API helpers

# should_onboard -> "true" | "false" (the API reports whether any organization exists yet)
should_onboard() {
  curl -s --max-time 60 "$API_URL/int/v1/onboard/should-onboard" \
    | sed -n 's/.*"should_onboard":\([a-z]*\).*/\1/p'
}

# wait_for_api -> waits until the API answers should-onboard (Octane up, migrations finished)
wait_for_api() { wait_for_code "$API_URL/int/v1/onboard/should-onboard" 200 "$TEST_TIMEOUT"; }

# wait_for_owner -> waits until the first-boot owner bootstrap has created the organization
wait_for_owner() {
  local timeout=${1:-$TEST_TIMEOUT} start
  start=$(date +%s)
  while :; do
    [ "$(should_onboard)" = "false" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      echo "timed out waiting for the owner account to be created" >&2; return 1
    fi
    sleep 5
  done
}

# login_body EMAIL PASSWORD FILE -> writes a login payload to FILE with mode 600
login_body() {
  local file=$3
  : >"$file"; chmod 600 "$file"
  OWNER_TEST_IDENTITY="$1" OWNER_TEST_SECRET="$2" python3 -c '
import json, os
print(json.dumps({"identity": os.environ["OWNER_TEST_IDENTITY"], "password": os.environ["OWNER_TEST_SECRET"]}))
' >"$file"
}

# login_code EMAIL PASSWORD -> prints the HTTP status of a login attempt (negative tests)
login_code() {
  local body="$TEST_TMP/login-$RANDOM.json" code
  login_body "$1" "$2" "$body"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 -X POST "$API_URL/int/v1/auth/login" \
    -H 'Content-Type: application/json' -H 'Accept: application/json' --data @"$body")
  rm -f "$body"
  printf '%s' "$code"
}

# login_once -> prints the owner's bearer token (empty on failure)
login_once() {
  local body="$TEST_TMP/login.json" out="$TEST_TMP/login-out.json"
  login_body "$OWNER_EMAIL" "$OWNER_PASSWORD" "$body"
  curl -s -o "$out" --max-time 60 -X POST "$API_URL/int/v1/auth/login" \
    -H 'Content-Type: application/json' -H 'Accept: application/json' --data @"$body"
  rm -f "$body"
  python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("token", ""))
except Exception:
    print("")
' "$out"
}

# login -> prints the owner's bearer token, retrying briefly.
# The onboarding endpoint creates the organization BEFORE the user row, so should-onboard can flip
# to false a moment before the owner's credentials are usable; retry instead of failing that race.
login() {
  local timeout=${1:-120} start token
  start=$(date +%s)
  while :; do
    token="$(login_once)"
    [ -n "$token" ] && { printf '%s' "$token"; return 0; }
    [ $(( $(date +%s) - start )) -ge "$timeout" ] && { printf ''; return 1; }
    sleep 5
  done
}

api_get()  { curl -s --max-time 60 -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json' "$API_URL$1"; }
api_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 60 -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json' "$@"; }

# api_post PATH JSON -> prints the response body
api_post() {
  local path=$1 json=$2 body="$TEST_TMP/post-$RANDOM.json"
  printf '%s' "$json" >"$body"
  curl -s --max-time 120 -X POST "$API_URL$path" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -H 'Accept: application/json' \
    --data @"$body"
  rm -f "$body"
}

# signup_code EMAIL -> HTTP status of a public self-signup attempt (must be 403 when closed)
signup_code() {
  local email=$1 body="$TEST_TMP/signup.json" code
  : >"$body"; chmod 600 "$body"
  SIGNUP_EMAIL="$email" python3 -c '
import json, os
print(json.dumps({
  "name": "Walk In User",
  "email": os.environ["SIGNUP_EMAIL"],
  "phone": "+12025550144",
  "password": "Vb7#qLt2Kz9!wR",
  "password_confirmation": "Vb7#qLt2Kz9!wR",
  "organization_name": "Walk In Logistics",
}))
' >"$body"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 -X POST "$API_URL/int/v1/onboard/create-account" \
    -H 'Content-Type: application/json' -H 'Accept: application/json' --data @"$body")
  rm -f "$body"
  printf '%s' "$code"
}

# json_field FILE_OR_STDIN PATH -> tiny jq-free extractor for the fields the tests need
json_get() { python3 -c '
import json, sys
data = json.load(sys.stdin)
for key in sys.argv[1].split("."):
    if isinstance(data, list):
        data = data[int(key)]
    else:
        data = data.get(key) if isinstance(data, dict) else None
    if data is None:
        break
print("" if data is None else data)
' "$1"; }
