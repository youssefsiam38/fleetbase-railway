# Railway template configuration

The template's exact configuration. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Fleetbase |
| Code | `fleetbase` |
| Template id | `1f21ebfc-f542-423f-977f-52635ced3b63` |
| Deploy URL | https://railway.com/deploy/fleetbase |
| Category | Other |
| Card description | Self-hosted Fleetbase logistics platform with MySQL, Redis and realtime |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

Generated values use Railway's `secret()` function: `hexN` is `${{secret(N, "abcdef0123456789")}}` and `alnumN` is
`${{secret(N, "a-zA-Z0-9")}}` spelled out. Alphanumeric passwords are used wherever a value is embedded in a
connection URL, so nothing needs percent-encoding. Images are referenced by tag, because the template generator
rejects digests; `UPSTREAM.md` records the digests.

## Services

### `database`

| Field | Value |
|---|---|
| Source | `mysql:8.0-oracle@sha256:7dcddc01f13bab2f15cde676d44d01f61fc9f99fe7785e86196dfc07d358ae2b` |
| Public domain | none |
| Volume | `/var/lib/mysql` |
| Start command | `docker-entrypoint.sh mysqld --datadir=/var/lib/mysql/data --bind-address='*'` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `MYSQL_ROOT_PASSWORD` | generated, alnum32 |
| `MYSQL_DATABASE` | `fleetbase` |

### `cache`

| Field | Value |
|---|---|
| Source | `redis:7-alpine@sha256:520775a41a63e77e06c73e35d2fd9cc15921a609516818796b4ecbb813078bc7` |
| Public domain | none |
| Volume | none |
| Start command | `redis-server --protected-mode no --appendonly no` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|

### `socket`

| Field | Value |
|---|---|
| Source | `socketcluster/socketcluster:v17.4.0@sha256:3cd5c2dde94eab1d4b4dde7d35a6eb8e5a109e7cb491c6f3964111144557b085` |
| Public domain | target port 8000 |
| Volume | none |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PORT` | `8000` |
| `SOCKETCLUSTER_PORT` | `8000` |
| `SOCKETCLUSTER_WORKERS` | `2` |
| `SOCKETCLUSTER_BROKERS` | `2` |

### `api`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/fleetbase-railway-api:1.0.1@sha256:b69dee37a09d7b9cd5f20d88de9303047801997c6208c996155722877ba321da` |
| Public domain | target port 8080 |
| Volume | `/fleetbase/api/storage/app` |
| Healthcheck | `/healthz`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `APP_ENV` | `production` |
| `APP_DEBUG` | `false` |
| `APP_NAME` | `Fleetbase` |
| `APP_KEY` | generated, alnum32 |
| `APP_URL` | `https://${{api.RAILWAY_PUBLIC_DOMAIN}}` |
| `CONSOLE_HOST` | `https://${{console.RAILWAY_PUBLIC_DOMAIN}}` |
| `DATABASE_URL` | `mysql://root:${{database.MYSQL_ROOT_PASSWORD}}@${{database.RAILWAY_PRIVATE_DOMAIN}}:3306/fleetbase` |
| `QUEUE_CONNECTION` | `redis` |
| `CACHE_DRIVER` | `redis` |
| `CACHE_PATH` | `/fleetbase/api/storage/framework/cache` |
| `CACHE_URL` | `tcp://${{cache.RAILWAY_PRIVATE_DOMAIN}}` |
| `REDIS_URL` | `tcp://${{cache.RAILWAY_PRIVATE_DOMAIN}}` |
| `BROADCAST_DRIVER` | `socketcluster` |
| `SOCKETCLUSTER_HOST` | `${{socket.RAILWAY_PUBLIC_DOMAIN}}` |
| `SOCKETCLUSTER_PORT` | `443` |
| `SOCKETCLUSTER_SECURE` | `true` |
| `LOG_CHANNEL` | `stdout` |
| `MAIL_MAILER` | `log` |
| `MAIL_FROM_NAME` | `Fleetbase` |
| `REGISTRY_HOST` | `https://registry.fleetbase.io` |
| `OSRM_HOST` | `https://router.project-osrm.org` |
| `PORT` | `8080` |
| `FORWARD_PROTO` | `https` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `300` |
| `PUBLIC_ONBOARDING` | `false` |
| `OWNER_EMAIL` | required input, no default |
| `OWNER_PASSWORD` | generated, alnum20 followed by `Aa1!` |
| `OWNER_NAME` | `Fleet Owner` |
| `OWNER_PHONE` | `+12025550123` |
| `ORGANIZATION_NAME` | `Fleet Operations` |
| `MAIL_HOST` | optional, unset |
| `MAIL_PORT` | optional, unset |
| `MAIL_USERNAME` | optional, unset |
| `MAIL_PASSWORD` | optional, unset |
| `MAIL_ENCRYPTION` | optional, unset |
| `MAIL_FROM_ADDRESS` | optional, unset |
| `IPINFO_API_KEY` | optional, unset |

### `worker`

| Field | Value |
|---|---|
| Source | `fleetbase/fleetbase-api:v0.7.63@sha256:b712ca37fda0a72d65beb3bbfef5fad9783e01a212f5f544f704af941af5a17d` |
| Public domain | none |
| Volume | none |
| Start command | `sh -c 'go-crond --verbose root:./crontab & exec php artisan queue:work --tries=3 --timeout=120'` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `APP_ENV` | `production` |
| `APP_DEBUG` | `false` |
| `APP_NAME` | `Fleetbase` |
| `APP_KEY` | `${{api.APP_KEY}}` |
| `APP_URL` | `https://${{api.RAILWAY_PUBLIC_DOMAIN}}` |
| `CONSOLE_HOST` | `https://${{console.RAILWAY_PUBLIC_DOMAIN}}` |
| `DATABASE_URL` | `mysql://root:${{database.MYSQL_ROOT_PASSWORD}}@${{database.RAILWAY_PRIVATE_DOMAIN}}:3306/fleetbase` |
| `QUEUE_CONNECTION` | `redis` |
| `CACHE_DRIVER` | `redis` |
| `CACHE_PATH` | `/fleetbase/api/storage/framework/cache` |
| `CACHE_URL` | `tcp://${{cache.RAILWAY_PRIVATE_DOMAIN}}` |
| `REDIS_URL` | `tcp://${{cache.RAILWAY_PRIVATE_DOMAIN}}` |
| `BROADCAST_DRIVER` | `socketcluster` |
| `SOCKETCLUSTER_HOST` | `${{socket.RAILWAY_PUBLIC_DOMAIN}}` |
| `SOCKETCLUSTER_PORT` | `443` |
| `SOCKETCLUSTER_SECURE` | `true` |
| `LOG_CHANNEL` | `stdout` |
| `MAIL_MAILER` | `log` |
| `MAIL_FROM_NAME` | `Fleetbase` |
| `REGISTRY_HOST` | `https://registry.fleetbase.io` |
| `OSRM_HOST` | `https://router.project-osrm.org` |

### `console`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/fleetbase-railway-console:1.0.1@sha256:46180b6f72eaadef2275c0c174433191bff78c4e4e4941d8c966bc1c63964c11` |
| Public domain | target port 4200 |
| Volume | none |
| Healthcheck | `/healthz`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PORT` | `4200` |
| `API_HOST` | `https://${{api.RAILWAY_PUBLIC_DOMAIN}}` |
| `SOCKETCLUSTER_HOST` | `${{socket.RAILWAY_PUBLIC_DOMAIN}}` |
| `SOCKETCLUSTER_PORT` | `443` |
| `SOCKETCLUSTER_SECURE` | `true` |
| `OSRM_HOST` | `https://router.project-osrm.org` |

## Notes

- The template deploys six services: `database` (MySQL 8), `cache` (Redis), `socket` (SocketCluster),
  `api` (Fleetbase API behind a Caddy front door), `worker` (queue worker + scheduler, stock upstream
  image) and `console` (the Ember UI).
- `OWNER_EMAIL` is the only value you must supply. `OWNER_PASSWORD` is generated by Railway; copy it
  before deploying — it is the password of the first administrator.
- Sign in at the **console** URL, not the API URL. The console reads the API address at runtime from
  `/fleetbase.config.json`, which the wrapper writes at boot.
- First boot runs migrations, seeds, permissions and registry initialisation and takes several
  minutes. The front door answers `/healthz` immediately, so the deploy goes healthy while that work
  finishes; the console shows a connection error until the API answers.
- Public self-signup (`POST /int/v1/onboard/create-account`) is blocked at the front door with 403.
  Set `PUBLIC_ONBOARDING=true` only if you want anyone with the URL to create organizations.
- The MySQL volume is mounted at `/var/lib/mysql` while the server's data directory is
  `/var/lib/mysql/data`, so the volume's `lost+found` does not block MySQL initialisation.
- Business data lives in the MySQL volume; uploaded files live in the API service's
  `/fleetbase/api/storage/app` volume. Back up both.
- Email is logged, not sent, until you set `MAIL_MAILER=smtp` and the `MAIL_*` variables.
- Route/distance estimates use the public OSRM demo server by default (`OSRM_HOST`); point it at your
  own OSRM instance for production use.
