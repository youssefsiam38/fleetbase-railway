# Fleetbase Console wrapper for Railway.
#
# The upstream console image is a static Ember build served by nginx on a fixed port, with its
# backend address read at runtime from /fleetbase.config.json. This wrapper only:
#   * makes nginx listen on Railway's $PORT (IPv4 + IPv6),
#   * writes /fleetbase.config.json from environment variables at boot (API host, realtime socket),
#   * adds a /healthz route for the Railway healthcheck.
# The Ember application itself is untouched — no rebuild, no patched assets.
ARG FLEETBASE_CONSOLE_IMAGE=fleetbase/fleetbase-console:v0.7.63@sha256:da565cbd45f7aae9909d706393936247004a4183ac879852848f1070bffcc354
FROM ${FLEETBASE_CONSOLE_IMAGE}

COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY entrypoint.sh /usr/local/bin/fleetbase-console-entrypoint.sh
RUN chmod +x /usr/local/bin/fleetbase-console-entrypoint.sh

LABEL org.opencontainers.image.source="https://github.com/youssefsiam38/fleetbase-railway" \
      org.opencontainers.image.description="Fleetbase Console for Railway" \
      org.opencontainers.image.licenses="AGPL-3.0-only"

ENV PORT=4200

ENTRYPOINT ["/usr/local/bin/fleetbase-console-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
