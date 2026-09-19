#!/bin/sh
# Entrypoint for the Fleetbase Console service of the Railway template.
# Writes the runtime configuration the Ember app fetches at boot, then hands over to the stock
# nginx entrypoint (which renders /etc/nginx/templates/*.template with the environment).
set -eu

log() { printf '[fleetbase-console-railway] %s\n' "$*"; }
die() { printf '[fleetbase-console-railway] ERROR: %s\n' "$*" >&2; exit 1; }

PORT="${PORT:-4200}"
export PORT

[ -n "${API_HOST:-}" ] || die "API_HOST is not set; it must be the public URL of the Fleetbase API service."

CONFIG_PATH=/usr/share/nginx/html/fleetbase.config.json
SOCKETCLUSTER_HOST="${SOCKETCLUSTER_HOST:-}"
SOCKETCLUSTER_PORT="${SOCKETCLUSTER_PORT:-443}"
SOCKETCLUSTER_SECURE="${SOCKETCLUSTER_SECURE:-true}"
SOCKETCLUSTER_PATH="${SOCKETCLUSTER_PATH:-/socketcluster/}"
OSRM_HOST="${OSRM_HOST:-https://router.project-osrm.org}"

json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

{
	printf '{\n'
	printf '  "API_HOST": "%s",\n' "$(json_escape "$API_HOST")"
	printf '  "API_NAMESPACE": "%s",\n' "$(json_escape "${API_NAMESPACE:-int/v1}")"
	if [ -n "$SOCKETCLUSTER_HOST" ]; then
		printf '  "SOCKETCLUSTER_HOST": "%s",\n' "$(json_escape "$SOCKETCLUSTER_HOST")"
		printf '  "SOCKETCLUSTER_PORT": "%s",\n' "$(json_escape "$SOCKETCLUSTER_PORT")"
		printf '  "SOCKETCLUSTER_SECURE": "%s",\n' "$(json_escape "$SOCKETCLUSTER_SECURE")"
		printf '  "SOCKETCLUSTER_PATH": "%s",\n' "$(json_escape "$SOCKETCLUSTER_PATH")"
	fi
	printf '  "OSRM_HOST": "%s"\n' "$(json_escape "$OSRM_HOST")"
	printf '}\n'
} >"$CONFIG_PATH"

log "runtime config written (API_HOST=${API_HOST}), serving console on :${PORT}"

exec /docker-entrypoint.sh "$@"
