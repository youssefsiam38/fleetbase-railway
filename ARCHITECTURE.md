# Architecture

## Service graph

```
Railway HTTPS edge (three public domains)
  │
  ├──► console   nginx :$PORT
  │              static Ember SPA + /fleetbase.config.json (written at boot)
  │              the browser then calls API_HOST and SOCKETCLUSTER_HOST directly
  │
  ├──► api       Caddy front door :$PORT
  │              /healthz                            -> 200, answered by Caddy
  │              POST /int/v1/onboard/create-account  -> 403, unless PUBLIC_ONBOARDING=true
  │              everything else                     -> 127.0.0.1:8000
  │                 └─ Laravel Octane/FrankenPHP, loopback only
  │                    volume: /fleetbase/api/storage/app  (uploads)
  │
  └──► socket    socketcluster :8000
                 realtime bus; the API and worker publish, the browser subscribes

private network only (no domain)
  ├─── database  mysql:8.0-oracle   volume: /var/lib/mysql, datadir /var/lib/mysql/data
  ├─── cache     redis:7-alpine     Laravel cache + queue broker
  └─── worker    stock API image    php artisan queue:work + go-crond scheduler
                                   mounts the same /fleetbase/api/storage/app volume

api    ──► database, cache, socket
worker ──► database, cache, socket
```

Three services have public domains: `console` (the UI users open), `api` (the REST/internal API the
console calls from the browser) and `socket` (the websocket endpoint the console connects to for
live updates). `database`, `cache` and `worker` stay on the private network.

## The services

### `database` — `mysql:8.0-oracle`

- Volume mounted at `/var/lib/mysql`, with `--datadir=/var/lib/mysql/data`. A fresh Railway volume
  contains `lost+found`, and MySQL refuses to initialise into a non-empty data directory, so the
  data directory is a subdirectory of the mount.
- `--bind-address=*` so MySQL also listens on IPv6: Railway's private network is IPv6-only and the
  default IPv4-only bind would be unreachable from the other services.
- The API and worker receive a single `DATABASE_URL` (`mysql://user:password@host:3306/fleetbase`).

### `cache` — `redis:7-alpine`

- `--protected-mode no` so it accepts connections from the other services over the private network.
- Used for the Laravel cache and as the queue broker (`QUEUE_CONNECTION=redis`,
  `CACHE_DRIVER=redis`). **Nothing durable lives here** — it can be wiped and rebuilt.

### `socket` — `socketcluster/socketcluster`

- The realtime broadcast bus. The API publishes to it (`BROADCAST_DRIVER=socketcluster`); the
  console subscribes from the browser, which is why it has its own public domain
  (`SOCKETCLUSTER_SECURE=true`, port `443` on Railway).
- Stock upstream image, no wrapper. Published for `linux/amd64`.

### `api` — wrapper image (Caddy front door + upstream API)

- Built `FROM` the pinned upstream `fleetbase/fleetbase-api` image; the Fleetbase application code
  is unmodified.
- **Port.** Caddy binds Railway's `$PORT`; Laravel Octane/FrankenPHP runs on `127.0.0.1:8000`
  (`INTERNAL_PORT`) and is never exposed directly.
- **Health.** Caddy answers `/healthz` itself, so the deploy goes healthy while the slow first boot
  is still running.
- **Closed onboarding.** `POST /int/v1/onboard/create-account` is answered `403` by the front door
  unless `PUBLIC_ONBOARDING=true`. The guard is a Caddy snippet the entrypoint writes at start-up.
- **HTTPS URLs.** The front door sets `X-Forwarded-Proto` from `FORWARD_PROTO` (`https` on Railway,
  `http` in local tests) so Laravel builds `https://` links behind Railway's edge. Proxy read/write
  timeouts are raised to 300 s for long-running API calls.
- **First boot.** The entrypoint validates the environment, starts Caddy, runs the upstream
  `deploy.sh` (migrate, sandbox migrate, seed, permissions, extension-registry init — several
  minutes), then starts Octane.
- **Owner bootstrap.** Once Octane answers on loopback, the entrypoint checks
  `/int/v1/onboard/should-onboard`; if the instance has no organisation it posts the owner account
  to `/int/v1/onboard/create-account` **over loopback**. The payload is written to a mode-600
  temporary file and passed to `curl --data @file`, so no secret appears on argv or in the logs. If
  an organisation already exists, it leaves accounts untouched — a restart never re-creates or
  overwrites the owner.
- **Volume.** `/fleetbase/api/storage/app` holds uploaded files (documents, photos, avatars). The
  entrypoint creates the storage subtree and chowns it to `www-data`.
- If Octane exits, the entrypoint stops the container so Railway restarts the service instead of
  leaving a healthy front door in front of a dead app.

### `worker` — stock upstream API image

- The same pinned upstream image, **no wrapper**: it runs `go-crond` (the scheduler shipped in the
  image) alongside `php artisan queue:work`. It has no port, no domain and no health check.
- Shares the same `DATABASE_URL`, Redis and socket configuration as the API, and mounts the API
  storage volume so queued jobs can read and write the same uploads.
- It does not run migrations; the API owns schema changes.

### `console` — wrapper image (nginx + upstream Ember build)

- Built `FROM` the pinned upstream `fleetbase/fleetbase-console` image. The Ember application is
  untouched: no rebuild, no patched assets.
- Upstream's console fetches `/fleetbase.config.json` at runtime, so the wrapper's entrypoint writes
  that file at boot from `API_HOST`, `API_NAMESPACE`, `SOCKETCLUSTER_*` and `OSRM_HOST`. nginx
  serves it with no-cache headers, so a redeploy with new values takes effect immediately.
- An nginx template makes the server listen on `$PORT` on both IPv4 and IPv6 and adds a `/healthz`
  route for Railway's health check; everything else falls back to `index.html` for the SPA router.

## How auth and admin work

- Fleetbase's own login (email + password, per-organisation) is the only user-facing authentication;
  the console signs in against the API.
- The owner account comes from the deploy variables: `OWNER_EMAIL` (required input),
  `OWNER_PASSWORD` (generated by Railway's secret generator), plus `OWNER_NAME`, `OWNER_PHONE` and
  `ORGANIZATION_NAME`. Upstream enforces its own password policy on that account (mixed case,
  digits, symbols, and a Have I Been Pwned lookup), so any replacement value must satisfy it too.
- Additional users are created by the owner from inside the console. The public onboarding endpoint
  stays closed.

## Why this wrapper shape

- **Health before readiness.** Fleetbase's first boot (migrations, sandbox migrations, seeds,
  permission sync, registry init) takes minutes. Without a front door answering `/healthz`,
  Railway's health check would fail the deploy before the app ever came up. Caddy answers the check
  immediately and proxies everything else.
- **The onboarding endpoint must be closed at the edge**, yet stay reachable for the one-time owner
  bootstrap. Blocking it in the front door while the entrypoint calls it over loopback gives exactly
  that: closed to the internet, open to the container.
- **`X-Forwarded-Proto` has to come from somewhere.** Laravel otherwise generates `http://` URLs
  behind Railway's TLS edge, breaking console callbacks and asset links.
- **The console needs runtime config, not a rebuild.** Upstream already reads
  `/fleetbase.config.json` at boot, so writing that one file at start-up is enough to point the
  stock Ember bundle at this deployment's API and socket domains; the only other change is making
  nginx honour `$PORT`.
- **The worker needs no wrapper at all**, so it runs the stock image — less to maintain and nothing
  to diverge.
