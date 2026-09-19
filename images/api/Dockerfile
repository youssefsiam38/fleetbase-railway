# Fleetbase API wrapper for Railway.
#
# Runs the upstream Fleetbase API image unmodified (FrankenPHP/Laravel Octane) on loopback and puts
# a small Caddy front door on the public port. The front door:
#   * answers /healthz itself so Railway's healthcheck passes while first-boot migrations run,
#   * blocks the public self-signup endpoint (int/v1/onboard/create-account) unless the deployer
#     explicitly opens it,
#   * forwards X-Forwarded-Proto so Laravel builds https URLs behind Railway's edge.
#
# The owner account is created once, at first boot, over loopback (so it is never a race with a
# stranger on the public URL).
ARG FLEETBASE_IMAGE=fleetbase/fleetbase-api:v0.7.63@sha256:b712ca37fda0a72d65beb3bbfef5fad9783e01a212f5f544f704af941af5a17d
FROM caddy:2.10.2-alpine AS caddy
FROM ${FLEETBASE_IMAGE}

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /usr/local/bin/fleetbase-railway-entrypoint.sh
RUN chmod +x /usr/local/bin/fleetbase-railway-entrypoint.sh

ENV PORT=8080 \
    INTERNAL_PORT=8000

ENTRYPOINT ["/usr/local/bin/fleetbase-railway-entrypoint.sh"]
