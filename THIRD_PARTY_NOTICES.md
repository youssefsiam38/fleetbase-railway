# Third-party notices

This template deploys the following third-party software. Each component keeps its own licence; the
template's own files (Dockerfiles, entrypoints, compose file, tests, docs) are MIT — see `LICENSE`.

## Fleetbase

- Source: https://github.com/fleetbase/fleetbase
- Licence: **AGPL-3.0** — full text in `licenses/FLEETBASE-LICENSE`.
- Used **unmodified** from the official images `fleetbase/fleetbase-api` and
  `fleetbase/fleetbase-console`, pinned by digest (see `UPSTREAM.md`). The wrapper images add only a
  Caddy front door, a runtime configuration file, an nginx `$PORT` template and entrypoint scripts;
  no Fleetbase code or asset is patched, and the `worker` service runs the stock upstream image as
  published.

> **AGPL-3.0 note.** Fleetbase is copyleft: anyone who runs a modified version and offers it to
> users over a network must offer those users the corresponding source. This template does not
> modify Fleetbase. The wrapper images are reproducible from public sources — upstream's source at
> the pinned tag plus the files in this repository
> (https://github.com/youssefsiam38/fleetbase-railway) — so the corresponding source for everything
> shipped remains available. If **you** modify Fleetbase in your own deployment, the AGPL
> obligations are yours to meet.

> **Trademark / brand.** "Fleetbase", its logo and other brand identifiers are the marks of the
> Fleetbase project and are not claimed by this template. This is a community-maintained deployment
> template that is based on Fleetbase; it is **not affiliated with, endorsed by, or an official
> offering of** the Fleetbase project, and it does not use the Fleetbase logo (it ships its own
> generic icon — see `assets/README.md`).

## MySQL

- Official `mysql` image (Oracle), used unmodified as the `database` service. MySQL Community Server
  is GPL-2.0 with the FOSS License Exception; the image bundles Oracle's own notices.

## Redis

- Official `redis` image, used unmodified as the `cache` service, for the Laravel cache and queue
  broker.

## SocketCluster

- `socketcluster/socketcluster` (https://github.com/SocketCluster/socketcluster), MIT, used
  unmodified as the realtime broadcasting service that Fleetbase's `socketcluster` broadcast driver
  publishes to.

## Caddy

- The API wrapper copies the Caddy web server binary (Apache-2.0,
  https://github.com/caddyserver/caddy) from the official `caddy` image and uses it unmodified as
  the public front door.

## nginx

- The upstream console image serves the Ember build with nginx (BSD-2-Clause). The wrapper only adds
  a server template and a runtime config file.

## External services (not bundled)

- **OSRM** — routing defaults to the public demo server `https://router.project-osrm.org`, operated
  by the OSRM project, and is configurable via `OSRM_HOST`. Map and routing data are subject to
  those providers' terms.
- **Fleetbase extension registry** — `https://registry.fleetbase.io`, contacted at boot for registry
  initialisation.
- **Your SMTP provider** — used only if you configure `MAIL_*`.

---

This template is community-maintained and is not affiliated with the Fleetbase project.
