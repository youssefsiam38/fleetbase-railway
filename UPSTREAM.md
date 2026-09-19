# Upstream and pinned versions

This template runs **Fleetbase** from its official images, **unmodified**, underneath two thin
wrapper images built by this repository's CI.

## Fleetbase (upstream, unmodified)

- Project: https://github.com/fleetbase/fleetbase
- Licence: **AGPL-3.0** (`LICENSE.md` upstream; full text in `licenses/FLEETBASE-LICENSE`)
- Version pinned: **v0.7.63**
- Official images (Docker Hub):
  - `fleetbase/fleetbase-api:v0.7.63`
    - digest `sha256:b712ca37fda0a72d65beb3bbfef5fad9783e01a212f5f544f704af941af5a17d`
    - multi-arch (linux/amd64, linux/arm64)
  - `fleetbase/fleetbase-console:v0.7.63`
    - digest `sha256:da565cbd45f7aae9909d706393936247004a4183ac879852848f1070bffcc354`
    - linux/amd64

The pins live in `images/api/Dockerfile` (`ARG FLEETBASE_IMAGE`), in `images/console/Dockerfile`
(`ARG FLEETBASE_CONSOLE_IMAGE`) and, for the `worker` service, in `compose.yaml`. Fleetbase's own
code and assets are not changed.

## Other pinned images

- `mysql:8.0-oracle` — the `database` service.
- `redis:7-alpine` — the `cache` service.
- `socketcluster/socketcluster:v17.4.0` — the `socket` service (linux/amd64).
- `caddy:2.10.2-alpine` — the binary copied into the API wrapper as the front door.

The compose file pins all of them by digest; the digests recorded there are the ones the tests run
against.

## Wrapper images (built by this repo)

- `ghcr.io/youssefsiam38/fleetbase-railway-api` — built from `images/api/Dockerfile`: the upstream
  API image plus the Caddy front door, Caddyfile and entrypoint.
- `ghcr.io/youssefsiam38/fleetbase-railway-console` — built from `images/console/Dockerfile`: the
  upstream console image plus the runtime-config entrypoint and the `$PORT` nginx template.

Both are published by `.github/workflows/publish-image.yml` on a `vX.Y.Z` tag, after the test suite
passes, and are tagged `X.Y.Z`, `X.Y` and `latest`. The Railway template references them **pinned by
digest**; the `worker` service uses the stock upstream API image directly.

Because the wrappers derive from an AGPL-3.0 image, everything needed to reproduce them is public:
upstream's source at the tag above, and the Dockerfiles, Caddyfile and entrypoints in this
repository. See `THIRD_PARTY_NOTICES.md`.

## Refreshing a digest

```bash
for img in fleetbase/fleetbase-api fleetbase/fleetbase-console; do
  docker buildx imagetools inspect "$img:<version>" --format '{{json .Manifest}}' | jq -r .digest
done
```

Update the pins in `images/api/Dockerfile`, `images/console/Dockerfile` and `compose.yaml` (the
`worker` image), re-run the tests, cut a new `vX.Y.Z` tag to rebuild and push both wrapper images,
then re-point the template at the new wrapper digests. See `MAINTENANCE.md`.
