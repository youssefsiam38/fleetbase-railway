# Deploy and Host Fleetbase on Railway

Fleetbase is an open-source logistics and supply-chain operating system: dispatch and order
management, fleet operations, live driver and vehicle tracking, a storefront/commerce module, a REST
API and an extension system. This template deploys the whole stack — MySQL, Redis, a realtime socket
server, the API, a queue/scheduler worker and the console UI — with your administrator account
created from the deploy variables at first boot and public self-signup closed. It is a
community-maintained template based on Fleetbase; it is not affiliated with, endorsed by, or an
official offering of the Fleetbase project, and it does not use the Fleetbase logo.

## About Hosting Fleetbase

Fleetbase is not a single container: the Laravel API, a queue worker with a scheduler, an Ember
console, MySQL, Redis and a SocketCluster realtime bus all have to be wired together, and the API's
first boot has to migrate, seed and initialise permissions and the extension registry before anyone
can log in. This template does that wiring for you and keeps your business data on a MySQL volume
and uploaded files on a storage volume, so redeploys and upgrades do not lose anything.

It also closes a real exposure. Fleetbase's onboarding endpoint has no "already onboarded" guard, so
on a public URL anyone who reaches the API could create an account and an organisation on your
instance. This template blocks that endpoint at the API's front door and instead creates the owner
account once, at first boot, over the container's loopback interface, from the email you supply and
a password Railway generates. Everyone else is invited by the owner from inside the console.

## Common Use Cases

- Running your own dispatch and delivery operation — orders, drivers, vehicles, routes and live
  tracking — on infrastructure you control, instead of a SaaS fleet platform.
- A self-hosted logistics backend behind your own apps: Fleetbase's REST API and realtime socket
  feed drive customer or driver front-ends.
- A private environment for building and testing Fleetbase extensions and storefront/commerce
  workflows against real data.

## Dependencies for Fleetbase Hosting

- MySQL, Redis and a SocketCluster realtime server are deployed as part of this template; nothing
  external is needed to log in and use it.
- Outbound email requires your own SMTP credentials (`MAIL_*`). Without them, invitations and
  notifications are written to the log instead of being sent.
- Routing uses an OSRM server. `OSRM_HOST` defaults to the public OSRM demo instance, which is
  rate-limited — point it at your own OSRM for production.
- The API contacts the Fleetbase extension registry (`https://registry.fleetbase.io`) at boot to
  initialise the registry.

### Deployment Dependencies

- Fleetbase: https://github.com/fleetbase/fleetbase (AGPL-3.0)
- Template repository and tests: https://github.com/youssefsiam38/fleetbase-railway

### Implementation Details

Six services. `database` runs `mysql:8.0-oracle` on a volume (with the data directory inside the
mount, so a fresh volume's `lost+found` does not block initialisation, and bound on IPv6 for
Railway's private network); `cache` runs `redis:7-alpine` for the Laravel cache and queue; `socket`
runs SocketCluster for realtime broadcasting; `api` runs the official `fleetbase/fleetbase-api`
image (pinned by digest, unmodified) behind a small Caddy front door; `worker` runs the same stock
image with `php artisan queue:work` and the `go-crond` scheduler; `console` serves the official
`fleetbase/fleetbase-console` Ember build (pinned by digest, unmodified) through nginx.

The API front door binds Railway's `PORT` and proxies Laravel Octane/FrankenPHP on loopback. It
answers `/healthz` itself, so the deploy goes healthy while the first boot migrates and seeds
(several minutes), sets `X-Forwarded-Proto: https` so Laravel builds correct URLs behind Railway's
edge, and returns `403` for `POST /int/v1/onboard/create-account` unless `PUBLIC_ONBOARDING=true`.
The owner account is created once over loopback from `OWNER_EMAIL` (required input) and a generated
`OWNER_PASSWORD`, with `OWNER_NAME`, `OWNER_PHONE` and `ORGANIZATION_NAME` editable; the bootstrap
is skipped if an organisation already exists, so restarts never touch accounts. The console wrapper
writes Fleetbase's runtime `fleetbase.config.json` at boot from the API and socket domains — the
Ember bundle is not rebuilt — and makes nginx listen on `PORT` with a `/healthz` route. `APP_KEY` is
generated; MySQL and Redis have no public domain.

Tested in CI and against a live deployment of this template, with the same six-service topology
reproduced locally in `compose.yaml`: static checks on the digest pins and the front-door wiring, a
smoke run (health endpoints, public onboarding refused with `403`, the bootstrapped owner
authenticating, the console serving its runtime config), and a persistence run (data survives a full
restart on the MySQL and storage volumes).

After deploying, wait for the API's first boot to finish (watch its logs), copy `OWNER_PASSWORD`
from the API service's variables, open the console's public domain, and sign in with `OWNER_EMAIL`
and that password. Change it from inside the console, then invite your team; public sign-up stays
closed. Add your `MAIL_*` SMTP settings if you want invitations and notifications delivered by
email.

## Why Deploy Fleetbase on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your
infrastructure so you don't have to deal with configuration, while allowing you to vertically and
horizontally scale it.

By deploying Fleetbase on Railway, you are one step closer to supporting a complete full-stack
application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
