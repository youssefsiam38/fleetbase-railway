# Maintenance

## Updating to a new Fleetbase version

1. **Bump the upstream pins.** Get the new digests (see `UPSTREAM.md`) and update:
   - `ARG FLEETBASE_IMAGE` in `images/api/Dockerfile`,
   - `ARG FLEETBASE_CONSOLE_IMAGE` in `images/console/Dockerfile`,
   - the `worker` service image in `compose.yaml` (it must match the API image exactly).
2. **Run the tests locally.**
   ```bash
   tests/static.sh
   docker compose build
   OWNER_PASSWORD='Change-me-123!' tests/smoke.sh
   OWNER_PASSWORD='Change-me-123!' tests/persistence.sh
   ```
   Allow several minutes for the first boot (migrations, sandbox migrations, seeds, permissions,
   registry init).
3. **Cut a release tag** (`git tag v1.0.1 && git push --tags`). `publish-image.yml` re-runs the
   tests, then builds and pushes both wrapper images to
   `ghcr.io/youssefsiam38/fleetbase-railway-api` and
   `ghcr.io/youssefsiam38/fleetbase-railway-console`.
4. **Make the GHCR packages public** (once, on first publish) so Railway can pull them.
5. **Re-point the template** at the new wrapper digests (and the new stock API digest for `worker`),
   then re-run the clean-room deploy and `tests/railway-smoke.sh` before updating the published
   template.

Check upstream's release notes for new required environment variables or migrations that need extra
steps; the API's `deploy.sh` runs whatever migrations the image ships.

## Rebuilding the Railway template from scratch

The generator spec lives in `_audit/spec_fleetbase.py` (in the templates workspace, not in this
repo) alongside the toolkit (`tplkit.py`), which builds a skeleton, patches the template and runs a
clean-room deploy. Volumes, domains and health checks are only set when the skeleton is created, so
changing any of them means rebuilding from a skeleton; if `verify_template` reports an empty volume
right after create, delete the template and re-create it.

## Gotchas worth remembering

- **Public onboarding must stay closed.** Upstream's `POST /int/v1/onboard/create-account` has no
  "already onboarded" guard, so it is blocked (`403`) by the API front door unless
  `PUBLIC_ONBOARDING=true`. The owner account is created over loopback instead. Do not "simplify"
  this by calling the endpoint through the public domain.
- **Health check before readiness.** First boot takes minutes. Caddy answers `/healthz` itself so
  Railway's health check passes while `deploy.sh` is still migrating — the service is healthy well
  before it can serve a login.
- **MySQL needs `--datadir=/var/lib/mysql/data`.** A fresh Railway volume contains `lost+found`, and
  MySQL refuses to initialise into a non-empty directory. The data directory must be a subdirectory
  of the mount.
- **MySQL needs `--bind-address=*`.** Railway's private network is IPv6-only; the default IPv4-only
  bind makes the database unreachable from the API and worker.
- **Redis needs `--protected-mode no`** to accept private-network connections.
- **nginx must be told about `$PORT`** (and must listen on `[::]` too). The console wrapper ships a
  server template for that; the stock image's fixed port would not match Railway's assigned port.
- **The console is configured at runtime, not at build time.** Upstream's Ember bundle fetches
  `/fleetbase.config.json` at boot, so `API_HOST` and `SOCKETCLUSTER_*` changes take effect on
  redeploy with no rebuild. The file is served with no-cache headers so a stale copy never survives
  a redeploy.
- **`API_HOST` is a browser-facing value.** It must be the API's **public** domain, not
  `*.railway.internal` — the console runs in the user's browser. The same applies to
  `SOCKETCLUSTER_HOST`.
- **`X-Forwarded-Proto` is set by the front door** (`FORWARD_PROTO`, `https` on Railway, `http` in
  local tests), or Laravel builds `http://` URLs behind Railway's TLS edge.
- **`worker` runs the stock image**, with `go-crond` for the scheduler plus
  `php artisan queue:work`. It must share the API's storage volume and never runs migrations itself.
- **Keep API, worker and console versions identical.** The console talks to a specific API contract.
- **Email is off until configured.** Without `MAIL_*`, invitations and notifications are logged
  rather than sent, which looks like "invites don't work".
- **OSRM defaults to the public demo server**, which is rate-limited; production deployments should
  set `OSRM_HOST`.
