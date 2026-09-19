#!/usr/bin/env bash
# Persistence test: create data, recreate the containers KEEPING the volumes, and prove the
# organization, the owner account and the business data all survived.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
. "$REPO_ROOT/tests/lib.sh"

cleanup() {
  local rc=$?
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  exit "$rc"
}
trap cleanup EXIT

FLEET_NAME="Persistent Fleet $RANDOM"

section "first boot"
compose up -d --build >/dev/null 2>&1 || die "compose up failed"
wait_for_api || die "the API never became ready"
wait_for_owner || die "the owner account was never created"
pass "stack healthy and owner created"

TOKEN="$(login)"; export TOKEN
[ -n "$TOKEN" ] || die "owner login failed on first boot"
assert_contains "fleet created before restart" "$FLEET_NAME" "$(api_post /int/v1/fleets "{\"name\":\"$FLEET_NAME\"}")"

section "restart keeping the volumes"
compose down --remove-orphans >/dev/null 2>&1 || die "compose down failed"
compose up -d >/dev/null 2>&1 || die "compose up (second boot) failed"
wait_for_api || die "the API never came back"
pass "stack came back up"

section "data survived"
assert_eq "organization still exists (no re-onboarding)" "false" "$(should_onboard)"
TOKEN="$(login)"; export TOKEN
if [ -n "$TOKEN" ]; then pass "owner can still log in"; else fail "owner login failed after restart"; fi
assert_contains "fleet survived the restart" "$FLEET_NAME" "$(api_get /int/v1/fleets)"
assert_eq "self-signup is still closed" "403" "$(signup_code "stranger$RANDOM@kwentra.com")"

summary
