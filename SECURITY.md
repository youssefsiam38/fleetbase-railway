# Security

## The front door closes public self-signup

Fleetbase's onboarding endpoint, `POST /int/v1/onboard/create-account`, has **no "already onboarded"
guard**: anyone who can reach the public API can create a user account and an organisation on your
instance — before your first login or long after it. On a public URL that is an open door.

This template closes it:

- The API's Caddy front door answers `POST /int/v1/onboard/create-account` with **`403`** unless the
  deployer sets `PUBLIC_ONBOARDING=true` on purpose.
- The owner account is created **once, at first boot, over loopback inside the container**
  (`127.0.0.1:8000`), from `OWNER_EMAIL` and `OWNER_PASSWORD`. That call never travels over the
  public domain, so there is no window in which a stranger could win the race.
- The bootstrap first asks `/int/v1/onboard/should-onboard`. If an organisation already exists it
  does nothing, so restarts and redeploys never re-create, reset or overwrite accounts.
- Additional users are invited by the owner from inside the console.

## What the template does

- **Required owner email, generated owner password.** `OWNER_EMAIL` is a required deploy input and
  `OWNER_PASSWORD` is generated per deployment by Railway's secret generator. Upstream applies its
  own password policy to that account (mixed case, digits, symbols, and a Have I Been Pwned lookup),
  so if you replace the generated value it must still satisfy that policy. The entrypoint refuses to
  start if either variable is missing, or if the password is shorter than 8 characters.
- **No secret on argv or in logs.** The onboarding payload is written to a mode-600 temporary file
  and handed to `curl --data @file`; the file is removed afterwards. Failure responses are printed
  with any token redacted.
- **Generated `APP_KEY`.** Laravel's encryption key is generated per deployment and stable across
  restarts.
- **HTTPS-aware.** The front door sets `X-Forwarded-Proto: https` (from `FORWARD_PROTO`), so Laravel
  issues `https://` URLs and secure cookies behind Railway's edge.
- **Upstream code unmodified, pinned by digest.** Both upstream images are pinned by digest; the
  wrappers only add a front door, a runtime config file and `$PORT` handling. The API runs its
  application storage as `www-data`.
- **Private data plane.** MySQL and Redis have no public domain and are reachable only over
  Railway's private network.
- **Secret hygiene in this repo.** No credential is committed; the local tests take the owner
  password from the environment, and `tests/static.sh` greps the tree for credential shapes.

## What you should do

- **Copy and guard `OWNER_PASSWORD`**, then change it from inside the console after your first
  login. Treat the variable as the break-glass copy, not the daily password.
- **Leave `PUBLIC_ONBOARDING` at `false`.** Setting it to `true` re-opens account and organisation
  creation to anyone who can reach the API URL. Only do it if you actually want public sign-up, and
  expect to police it yourself.
- **Configure your own SMTP** (`MAIL_*`) before relying on invitations, password resets or
  notifications — without it Fleetbase only logs them.
- **Point `OSRM_HOST` at your own routing server** for production. The default is the public OSRM
  demo instance: rate-limited, third-party, and every routing request sends coordinates to it.
- **Review what leaves your deployment.** The API contacts `https://registry.fleetbase.io` at boot
  for extension registry initialisation, and routing requests go to whatever `OSRM_HOST` points at.
- **Back up both volumes** with Railway's volume backups: the MySQL volume (all business data) and
  the API storage volume (uploaded files). Redis holds only cache and queue state and needs no
  backup.
- **Keep the API, worker and console on the same upstream version** when you upgrade; mixed versions
  are not tested by this template.

## Reporting

For vulnerabilities in Fleetbase itself, report them upstream to the Fleetbase project. For issues
specific to this template's packaging (the front door, the owner bootstrap, the service wiring),
open an issue on the template repository: https://github.com/youssefsiam38/fleetbase-railway
