#!/usr/bin/env bash
# Smoke test: bring the whole stack up with docker compose and exercise Fleetbase end to end —
# health, the closed self-signup gate, owner login, and a real fleet-ops object round trip.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
. "$REPO_ROOT/tests/lib.sh"

KEEP_UP="${KEEP_UP:-0}"
cleanup() {
  local rc=$?
  if [ "$KEEP_UP" != "1" ]; then
    printf '\n-- container logs (api) --\n'
    compose logs --tail 60 api 2>&1 | grep -v '"level":' || true
    compose down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT

section "bring the stack up"
compose up -d --build >/dev/null 2>&1 || die "compose up failed"
pass "stack started"

section "front door health"
wait_for_code "$API_URL/healthz" 200 120 || fail "api /healthz never returned 200"
assert_eq "api /healthz" "200" "$(http_code "$API_URL/healthz")"
assert_eq "console /healthz" "200" "$(http_code "$CONSOLE_URL/healthz")"

section "console runtime configuration"
CONSOLE_CONFIG="$(curl -s --max-time 30 "$CONSOLE_URL/fleetbase.config.json")"
assert_contains "console points at the API" "API_HOST" "$CONSOLE_CONFIG"
assert_contains "console serves the Ember app" "<title>" "$(curl -s --max-time 30 "$CONSOLE_URL/")"

section "api boot (migrations, seeds, owner bootstrap)"
wait_for_api || die "the API never became ready"
pass "api answers /int/v1/onboard/should-onboard"
wait_for_owner || die "the owner account was never created"
assert_eq "organization exists after first boot" "false" "$(should_onboard)"

section "security gates"
assert_eq "public self-signup is blocked" "403" "$(signup_code "stranger@kwentra.com")"
assert_eq "wrong password is rejected" "401" "$(login_code "$OWNER_EMAIL" "definitely-not-the-password")"
assert_eq "unknown user is rejected" "401" "$(login_code "nobody@kwentra.com" "definitely-not-the-password")"
assert_eq "protected endpoint needs a token" "401" "$(http_code "$API_URL/int/v1/vehicles")"

section "owner login"
TOKEN="$(login)"
export TOKEN
if [ -n "$TOKEN" ]; then pass "owner login returns a bearer token"; else fail "owner login failed"; fi
assert_contains "session is bound to the owner" "$OWNER_EMAIL" "$(api_get /int/v1/users/me)"

section "fleet-ops round trip"
FLEET_NAME="Night Shift $RANDOM"
CONTACT_NAME="Dispatcher $RANDOM"
assert_contains "fleet created" "$FLEET_NAME" "$(api_post /int/v1/fleets "{\"name\":\"$FLEET_NAME\"}")"
assert_contains "fleet listed back" "$FLEET_NAME" "$(api_get "/int/v1/fleets?query=$(printf '%s' "$FLEET_NAME" | tr ' ' '+')")"
assert_contains "contact created" "$CONTACT_NAME" \
  "$(api_post /int/v1/contacts "{\"name\":\"$CONTACT_NAME\",\"email\":\"contact$RANDOM@kwentra.com\",\"type\":\"customer\"}")"
assert_contains "contact listed back" "$CONTACT_NAME" "$(api_get "/int/v1/contacts")"

section "queue worker"
WORKER_LOGS="$(compose logs --tail 40 worker 2>&1)"
assert_not_contains "worker is not crash-looping" "Fatal error" "$WORKER_LOGS"

summary
