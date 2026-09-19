#!/usr/bin/env bash
# Static checks for the fleetbase-railway template: no Docker build, no network.
# Verifies the compose topology, the digest pinning, the wrapper entrypoints' security wiring,
# and that no credential-shaped string is committed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
OWNER_PASSWORD="${OWNER_PASSWORD:-static-check-placeholder}" \
  . "$REPO_ROOT/tests/lib.sh"

cd "$REPO_ROOT" || exit 1

section "shell syntax"
for f in tests/*.sh images/api/entrypoint.sh images/console/entrypoint.sh; do
  if bash -n "$f" 2>/dev/null || sh -n "$f" 2>/dev/null; then pass "syntax $f"; else fail "syntax $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x -S warning tests/*.sh images/api/entrypoint.sh images/console/entrypoint.sh; then
    pass "shellcheck clean"
  else
    fail "shellcheck reported problems"
  fi
else
  pass "shellcheck not installed (skipped)"
fi

section "compose topology"
if OWNER_PASSWORD=placeholder docker compose -f compose.yaml config -q; then
  pass "compose.yaml is valid"
else
  fail "compose.yaml is invalid"
fi
CONFIG="$(OWNER_PASSWORD=placeholder docker compose -f compose.yaml config 2>/dev/null)"
for svc in database cache socket api worker console; do
  assert_contains "service $svc declared" "  $svc:" "$CONFIG"
done
assert_eq "every published port is bound to loopback" "0" \
  "$(grep -c 'host_ip: 0.0.0.0' <<<"$CONFIG")"
assert_contains "ports are published on 127.0.0.1" "host_ip: 127.0.0.1" "$CONFIG"
assert_contains "api published on 8080" 'published: "8080"' "$CONFIG"
assert_contains "console published on 4200" 'published: "4200"' "$CONFIG"
assert_contains "mysql data dir avoids the volume root" "--datadir=/var/lib/mysql/data" "$CONFIG"
assert_contains "mysql binds all interfaces (IPv6 private network)" "--bind-address=" "$CONFIG"
assert_contains "api storage volume mounted" "/fleetbase/api/storage/app" "$CONFIG"
assert_contains "mysql volume mounted" "/var/lib/mysql" "$CONFIG"

section "images pinned by digest"
PINS="$(grep -hoE '[a-z0-9._/-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}' \
  compose.yaml images/api/Dockerfile images/console/Dockerfile | sort -u)"
for want in fleetbase/fleetbase-api fleetbase/fleetbase-console mysql redis socketcluster/socketcluster; do
  if grep -q "^$want:" <<<"$PINS"; then pass "digest pinned: $want"; else fail "not digest pinned: $want"; fi
done
UNPINNED="$(grep -hoE '^\s*image: [^$][^ ]*' compose.yaml | grep -v '@sha256:' || true)"
if [ -z "$UNPINNED" ]; then pass "no unpinned image in compose.yaml"; else fail "unpinned images:$UNPINNED"; fi

section "api front door"
API_ENTRY="$(cat images/api/entrypoint.sh)"
API_CADDY="$(cat images/api/Caddyfile)"
assert_contains "public signup blocked by default" "PUBLIC_ONBOARDING:-false" "$API_ENTRY"
assert_contains "signup guard targets the onboarding endpoint" "/int/v1/onboard/create-account" "$API_ENTRY"
assert_contains "guard returns 403" "403" "$API_ENTRY"
assert_contains "owner bootstrap runs over loopback" "127.0.0.1" "$API_ENTRY"
assert_contains "owner payload passed to curl via --data @file" "--data @" "$API_ENTRY"
assert_contains "OWNER_PASSWORD is required" "OWNER_PASSWORD is not set" "$API_ENTRY"
assert_contains "healthcheck answered by the front door" "handle /healthz" "$API_CADDY"
assert_contains "forwarded proto defaults to https" "FORWARD_PROTO:https" "$API_CADDY"
assert_contains "octane proxied over loopback" "reverse_proxy 127.0.0.1" "$API_CADDY"

section "console wrapper"
CONSOLE_ENTRY="$(cat images/console/entrypoint.sh)"
CONSOLE_CONF="$(cat images/console/default.conf.template)"
assert_contains "API_HOST is required" "API_HOST is not set" "$CONSOLE_ENTRY"
assert_contains "runtime config written to the served path" "/usr/share/nginx/html/fleetbase.config.json" "$CONSOLE_ENTRY"
assert_contains_f "nginx listens on Railway's PORT" 'listen       ${PORT};' "$CONSOLE_CONF"
assert_contains_f "nginx listens on IPv6 too" 'listen       [::]:${PORT};' "$CONSOLE_CONF"
assert_contains "healthz route present" "location = /healthz" "$CONSOLE_CONF"

section "secret scan"
LEAKS=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in tests/static.sh) continue ;; esac
  if grep -aInE '(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "$f" >/dev/null; then
    LEAKS="$LEAKS $f"
  fi
done < <(git ls-files 2>/dev/null || find . -type f -not -path './.git/*')
if [ -z "$LEAKS" ]; then pass "no credential-shaped strings committed"; else fail "possible secrets in:$LEAKS"; fi

summary
