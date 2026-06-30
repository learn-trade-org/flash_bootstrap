# 2026-06-30

## Free auto-HTTPS per droplet — Caddy + nip.io (branch `yeswanth/caddy_https_00`)

Every droplet gets a real Let's Encrypt cert with **no domain to buy and nothing to maintain** (issue #595).

```
browser ─:443 TLS─► caddy ─:10600 HTTP─► app      (same flash_default net)
   https://64-227-176-211.nip.io        plain HTTP internally
```

- `assets/Caddyfile` — `{$FLASH_HOSTNAME} { reverse_proxy app:10600 }`. A **real hostname** is the whole trick: Caddy auto-enables HTTPS, runs ACME HTTP-01 on `:80`, binds `:443`, auto-renews. Certs persist in the `caddy_data` volume.
- `assets/docker-compose.customer.yml` — new `caddy` service (ports `80`/`443`, `caddy_data`/`caddy_config` volumes). **No `app→caddy` depends_on**: a broken hostname keeps caddy down but leaves mongo+app serving on `:7200` (HTTPS is additive, not load-bearing).
- `02_gen_env.sh` — detects the droplet's **public IPv4** (DO metadata → `ifconfig.me` fallback; never the private/anchor IP), writes `FLASH_HOSTNAME=<ip-dashed>.nip.io`. Reconciled each run like `DOCKER_GID`; skipped (warn) if detection fails.
- `00_bootstrap.sh` + `update/01_image_pull.sh` — copy `Caddyfile` into `flash/`. The updater path is **required**, not optional: it already ships the new compose that mounts `./Caddyfile`, so the file must ride along or existing boxes break.
- nip.io is the default (issue comment); sslip.io stays a manual fallback (separate LE rate-limit bucket). Plain `:7200` kept open — additive rollout.

Requires ports **80 + 443** open inbound. Bash syntax-checked; `docker compose config` validates; hostname transform verified.
