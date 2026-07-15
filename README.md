# flash_bootstrap

Installer that takes a bare droplet to a running FLASH in one command: install Docker, log in to GHCR, generate `.env`, **pull the baked images**, start the stack. Carries **no flash source** — the engine ships as private images on `ghcr.io/learn-trade-org` (`flash-app`, `flash-mongo`, `flash-strategy-runtime`, `flash-strategy-runtime-bun`, `flash-updater`).

Provision-only, then walks away. `00_bootstrap.sh` **generates** a sibling `flash/` runtime dir from `assets/` (compose + launcher), then orchestrates `01_install_host` → `01b_registry_login` → `02_gen_env` → `03_compose_up` → `04_server_maintenance`. Nothing here handles updates — that's the `flash_updater` service in the generated compose stack, talking to `flashtrade.in`'s release registry.

```
flash_bootstrap/   (this installer — cloned)     flash/   (generated at runtime)
  assets/docker-compose.customer.yml   ──cp──►     docker-compose.customer.yml
  assets/launch.sh                     ──cp──►     launch.sh
  00..04 scripts                                   .env        (random creds + digest pins)
                                                     db/{mongo,tick,instrument,strategy}
```

**First-run (customer):**
1. `git clone <flash_bootstrap repo>` (only this repo — no source).
2. `cd flash_bootstrap`
3. `GHCR_USER=<github-user> GHCR_TOKEN=<read:packages PAT> ./00_bootstrap.sh`

→ FLASH live on `:7200` (login `admin` / the PIN in `flash/.env` `ADMIN_PIN` — set via the env var at bootstrap, default `123456` for local runs). Data persists in `flash/db/*`. `02_gen_env.sh` fetches the current `stable` manifest from `flashtrade.in` once to pin the initial images by digest; the `flash_updater` container takes over from there — checks for new releases on its own schedule, health-gates, and rolls back automatically.

**Owner side:** build + push the images from the private flash repo with `container/publish.sh` — it also registers the release in `flashtrade.in`'s `release_registry`, which is what every droplet's `flash_updater` reads from.