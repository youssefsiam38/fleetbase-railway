#!/bin/sh
# Entrypoint for the Fleetbase API service of the Railway template.
#
# Order of operations:
#   1. validate the environment the upstream app needs to boot,
#   2. start the Caddy front door immediately (so Railway's /healthz check passes during the slow
#      first-boot migration),
#   3. run the upstream deploy script (migrations, seeds, permissions) and start Laravel Octane on
#      loopback,
#   4. create the owner account once, over loopback, from OWNER_EMAIL/OWNER_PASSWORD.
#
# Secrets are never echoed and never passed on argv: the onboarding payload is written to a
# mode-600 file and handed to curl with --data @file.
set -eu

log() { printf '[fleetbase-railway] %s\n' "$*"; }
die() { printf '[fleetbase-railway] ERROR: %s\n' "$*" >&2; exit 1; }

PORT="${PORT:-8080}"
INTERNAL_PORT="${INTERNAL_PORT:-8000}"
export PORT INTERNAL_PORT

[ -n "${DATABASE_URL:-}" ] || die "DATABASE_URL is not set (mysql://user:password@host:3306/fleetbase)."
[ -n "${APP_KEY:-}" ] || die "APP_KEY is not set (Laravel application key)."
[ -n "${OWNER_EMAIL:-}" ] || die "OWNER_EMAIL is not set; it is the first administrator's email address."
[ -n "${OWNER_PASSWORD:-}" ] || die "OWNER_PASSWORD is not set; it is the first administrator's password."
[ "${#OWNER_PASSWORD}" -ge 8 ] || die "OWNER_PASSWORD is too short; Fleetbase requires at least 8 characters."

OWNER_NAME="${OWNER_NAME:-Fleet Owner}"
OWNER_PHONE="${OWNER_PHONE:-+12025550123}"
ORGANIZATION_NAME="${ORGANIZATION_NAME:-Fleet Operations}"
PUBLIC_ONBOARDING="${PUBLIC_ONBOARDING:-false}"

# The front door blocks public self-signup unless the deployer opens it on purpose.
if [ "$PUBLIC_ONBOARDING" = "true" ]; then
	: >/etc/caddy/onboarding.conf
	log "public self-signup is ENABLED (PUBLIC_ONBOARDING=true)"
else
	cat >/etc/caddy/onboarding.conf <<-'GUARD'
		handle /int/v1/onboard/create-account {
			respond `{"errors":["Public sign-up is disabled on this deployment."]}` 403 {
				close
			}
		}
	GUARD
	log "public self-signup is disabled; only the owner account can invite users"
fi

# Storage for uploads lives on the Railway volume; keep it writable by the app user.
mkdir -p /fleetbase/api/storage/app /fleetbase/api/storage/framework/cache /fleetbase/api/storage/logs
chown -R www-data:www-data /fleetbase/api/storage 2>/dev/null || true

api_url() { printf 'http://127.0.0.1:%s%s' "$INTERNAL_PORT" "$1"; }

bootstrap_owner() {
	# Wait for Octane to answer on loopback (migrations + seeds run first and are slow).
	i=0
	until [ "$(curl -s -o /dev/null -w '%{http_code}' "$(api_url /int/v1/onboard/should-onboard)")" = "200" ]; do
		i=$((i + 1))
		[ "$i" -lt 240 ] || { log "WARNING: API did not answer on loopback; skipping owner bootstrap"; return 0; }
		sleep 5
	done

	if ! curl -s "$(api_url /int/v1/onboard/should-onboard)" | grep -q '"should_onboard":true'; then
		log "an organization already exists; leaving accounts untouched"
		return 0
	fi

	payload="$(mktemp)"
	chmod 600 "$payload"
	OWNER_NAME="$OWNER_NAME" OWNER_EMAIL="$OWNER_EMAIL" OWNER_PHONE="$OWNER_PHONE" \
		ORGANIZATION_NAME="$ORGANIZATION_NAME" OWNER_PASSWORD="$OWNER_PASSWORD" \
		php -r '
			$d = [
				"name" => getenv("OWNER_NAME"),
				"email" => getenv("OWNER_EMAIL"),
				"phone" => getenv("OWNER_PHONE"),
				"password" => getenv("OWNER_PASSWORD"),
				"password_confirmation" => getenv("OWNER_PASSWORD"),
				"organization_name" => getenv("ORGANIZATION_NAME"),
			];
			echo json_encode($d);
		' >"$payload"

	code="$(curl -s -o /tmp/fb-onboard-response -w '%{http_code}' \
		-X POST "$(api_url /int/v1/onboard/create-account)" \
		-H 'Content-Type: application/json' -H 'Accept: application/json' \
		--data @"$payload")"
	rm -f "$payload"

	if [ "$code" = "200" ]; then
		log "owner account created for ${OWNER_EMAIL} (organization: ${ORGANIZATION_NAME})"
	else
		log "WARNING: owner bootstrap returned HTTP ${code}"
		sed -e 's/"token":"[^"]*"/"token":"[redacted]"/' /tmp/fb-onboard-response >&2 || true
		printf '\n' >&2
	fi
	rm -f /tmp/fb-onboard-response
}

start_app() {
	cd /fleetbase/api

	log "running database migrations and seeds (first boot can take several minutes)"
	if ! ./deploy.sh; then
		log "ERROR: deploy.sh failed; the API will not start"
		exit 1
	fi

	log "starting Laravel Octane on 127.0.0.1:${INTERNAL_PORT}"
	php artisan octane:frankenphp --max-requests=1000 --port="$INTERNAL_PORT" --host=127.0.0.1 &
	OCTANE_PID=$!

	bootstrap_owner &

	wait "$OCTANE_PID"
	log "ERROR: Octane exited; stopping the container so Railway restarts it"
	kill 1 2>/dev/null || true
}

start_app &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true' TERM INT

log "front door listening on :${PORT} (healthcheck /healthz)"
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
