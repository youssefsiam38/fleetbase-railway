#!/usr/bin/env bash
# Live end-to-end test against a real Railway deployment of this template, over HTTPS.
#
#   OWNER_PASSWORD_FILE=/path/to/mode-600-file \
#   tests/railway-smoke.sh https://<api-domain> https://<console-domain>
#
# The owner password is read from the file and never printed or passed on argv.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

API_URL="${1:-${API_URL:-}}"
CONSOLE_URL="${2:-${CONSOLE_URL:-}}"
[ -n "$API_URL" ] || { echo "usage: $0 <api-url> [console-url]" >&2; exit 2; }
export API_URL CONSOLE_URL
. "$REPO_ROOT/tests/lib.sh"

section "deployment reachable"
assert_eq "api /healthz" "200" "$(http_code "$API_URL/healthz")"
if [ -n "$CONSOLE_URL" ]; then
  assert_eq "console /healthz" "200" "$(http_code "$CONSOLE_URL/healthz")"
  CONSOLE_CONFIG="$(curl -s --max-time 30 "$CONSOLE_URL/fleetbase.config.json")"
  assert_contains "console is wired to the deployed API" "$API_URL" "$CONSOLE_CONFIG"
  assert_contains "console serves the app shell" "<title>" "$(curl -s --max-time 30 "$CONSOLE_URL/")"
fi

section "api ready"
wait_for_api || die "the API never became ready"
wait_for_owner || die "the owner account was never created"
assert_eq "organization exists" "false" "$(should_onboard)"

section "security gates over HTTPS"
assert_eq "public self-signup is blocked" "403" "$(signup_code "stranger$RANDOM@kwentra.com")"
assert_eq "wrong password is rejected" "401" "$(login_code "$OWNER_EMAIL" "definitely-not-the-password")"
assert_eq "protected endpoint needs a token" "401" "$(http_code "$API_URL/int/v1/fleets")"

section "owner login"
TOKEN="$(login)"; export TOKEN
if [ -n "$TOKEN" ]; then pass "owner login returns a bearer token"; else fail "owner login failed"; fi
assert_contains "session is bound to the owner" "$OWNER_EMAIL" "$(api_get /int/v1/users/me)"

section "fleet-ops round trip"
FLEET_NAME="${FLEET_NAME:-Live Fleet $RANDOM}"
CONTACT_NAME="Live Dispatcher $RANDOM"
assert_contains "fleet created" "$FLEET_NAME" "$(api_post /int/v1/fleets "{\"name\":\"$FLEET_NAME\"}")"
assert_contains "fleet listed back" "$FLEET_NAME" "$(api_get /int/v1/fleets)"
assert_contains "contact created" "$CONTACT_NAME" \
  "$(api_post /int/v1/contacts "{\"name\":\"$CONTACT_NAME\",\"email\":\"live$RANDOM@kwentra.com\",\"type\":\"customer\"}")"

section "uploads volume"
assert_eq "file storage endpoint reachable" "200" "$(api_code "$API_URL/int/v1/files")"

summary
