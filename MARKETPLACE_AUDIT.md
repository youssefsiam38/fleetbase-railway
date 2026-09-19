# Marketplace audit

A record of the diligence behind publishing this template.

## Identity

- Template: **Fleetbase** — an open-source logistics and supply-chain operating system: dispatch,
  fleet operations, live tracking, storefront/commerce, a REST API and an extension system.
- Upstream: [fleetbase/fleetbase](https://github.com/fleetbase/fleetbase), pinned at **v0.7.63**,
  distributed as official Docker Hub images (`fleetbase/fleetbase-api`,
  `fleetbase/fleetbase-console`).
- Stack: Laravel (Octane/FrankenPHP) API + queue worker/scheduler, an Ember console served by nginx,
  MySQL 8, Redis, and SocketCluster for realtime broadcasting.
- Category: **Other**. Card description: "Self-hosted Fleetbase logistics platform with MySQL, Redis
  and realtime" (71 characters).

## Licence and brand

- **AGPL-3.0** (`licenses/FLEETBASE-LICENSE`). Copyleft, but no non-commercial and no competing-use
  restriction, so publishing a deployment template is permitted. Fleetbase is used **unmodified**
  and pinned by digest; the wrapper images add only a front door, runtime config and `$PORT`/health
  wiring, and are reproducible from public sources (upstream's tag + this repository), so the
  corresponding-source obligation is satisfied. The template's own files are MIT.
- **Brand.** "Fleetbase" and its logo are the project's marks. This template is
  community-maintained, states only that it is based on Fleetbase, ships its own generic icon, and
  does not imply official status. See `THIRD_PARTY_NOTICES.md`.

## Security review

- **Unguarded public onboarding, closed by the template.** Upstream's onboarding endpoint,
  `POST /int/v1/onboard/create-account`, has no "already onboarded" check: any visitor to the public
  API could create an account and organisation, at any time. The front door answers it `403` unless
  the deployer sets `PUBLIC_ONBOARDING=true`, and the owner account is created once at first boot
  **over loopback** from `OWNER_EMAIL`/`OWNER_PASSWORD`. The bootstrap is idempotent — it checks
  `/int/v1/onboard/should-onboard` and leaves existing accounts alone — so restarts cannot reset or
  duplicate the owner.
- **Credential handling.** `OWNER_PASSWORD` is generated per deployment by Railway's secret
  generator and has to satisfy upstream's policy (mixed case, digits, symbols, Have I Been Pwned
  lookup); `APP_KEY` is generated too.
  The onboarding payload goes through a mode-600 temp file into `curl --data @file` (never argv),
  failure bodies are printed with tokens redacted, and no credential is committed to the repo.
- **Attack surface.** Public: the console (static SPA), the API behind the front door, and the
  SocketCluster endpoint the browser needs. Private-only: MySQL and Redis (no domains), and the
  worker (no port, no domain).
- **Transport.** The front door sets `X-Forwarded-Proto: https` so Laravel issues `https://` URLs
  and secure cookies behind Railway's edge.
- **Third-party egress disclosed:** the Fleetbase extension registry at boot, the public OSRM demo
  server by default (configurable), and the deployer's own SMTP if configured. Documented in
  `SECURITY.md` and `THIRD_PARTY_NOTICES.md`.

## Reproducibility & tests

The local harness mirrors the Railway service graph exactly (`compose.yaml`: database, cache,
socket, api, worker, console), so what CI exercises is the same topology the template deploys.

- `tests/static.sh` — shell syntax and shellcheck, compose shape (six services, volumes, commands),
  upstream and base-image digest pins, front-door/onboarding-guard wiring, console runtime-config
  and `$PORT` wiring, secret scan.
- `tests/smoke.sh` — the stack boots; `/healthz` answers on the API and the console; public
  onboarding is refused (`403`); the owner account is created at first boot and can authenticate;
  the console serves `/fleetbase.config.json` pointing at the configured API and socket.
- `tests/persistence.sh` — data written before a full restart is still there afterwards (MySQL
  volume and the API storage volume).
- `tests/railway-smoke.sh` — the same checks over HTTPS against a deployed template.
- CI runs static + smoke + persistence on every push; `publish-image.yml` re-runs them before
  pushing the wrapper images to GHCR on a release tag.

The exact check counts and the results of the clean-room deploy are recorded by the release run that
ships the template (see `MAINTENANCE.md` for the sequence); this document describes the coverage,
not a claim of results.

## Deploy-time inputs

| Variable | Kind | Notes |
|---|---|---|
| `OWNER_EMAIL` | **required input** | The first administrator's email; login for the console |
| `OWNER_PASSWORD` | generated | Railway secret generator; copy it, then change it in the console |
| `OWNER_NAME`, `OWNER_PHONE`, `ORGANIZATION_NAME` | editable | Owner profile, organisation name |
| `PUBLIC_ONBOARDING` | fixed `false` | `true` re-opens public account/organisation creation |
| `APP_KEY` | generated | Laravel encryption key, stable across restarts |
| `MAIL_*` | optional | Without SMTP, notifications and invitations are logged, not sent |
| `OSRM_HOST` | optional | Defaults to the public OSRM demo server; set your own for production |
| `REGISTRY_HOST` | optional | Fleetbase extension registry, used at boot |

Everything else — ports, health checks, volumes, database/Redis/socket wiring, `API_HOST`,
`CONSOLE_HOST` — is set by the template.

## Release gate

Before the template is published or updated, all of the following must be green:

- [ ] `tests/static.sh`, `tests/smoke.sh`, `tests/persistence.sh` locally and in CI.
- [ ] Both wrapper images published to GHCR, public, and referenced by digest.
- [ ] Clean-room deploy succeeds; `tests/railway-smoke.sh` green over HTTPS; data survives a
      redeploy.

## Verdict

Shippable, subject to the release gate above. The template deploys an unmodified, digest-pinned
Fleetbase stack whose one material exposure — an unguarded public onboarding endpoint — is closed at
the edge and replaced by a one-time loopback owner bootstrap, with persistent data on volumes and a
reproducible local harness mirroring the deployed topology.
