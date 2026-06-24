# flash_bootstrap

Installer that takes a bare droplet to a running FLASH in one command: install Docker, log in to GHCR, generate `.env`, **pull the baked images**, start the stack. Carries **no flash source** — the engine ships as private images on `ghcr.io/learn-trade-org` (`flash-app`, `flash-mongo`, `flash-strategy-runtime`).

Numbered run-order — `00_bootstrap.sh` **generates** a sibling `flash/` runtime dir from `assets/` (compose + launcher), then orchestrates `01_install_host` → `01b_registry_login` → `02_gen_env` → `03_compose_up`.

```
flash_bootstrap/   (this installer — cloned)     flash/   (generated at runtime)
  assets/docker-compose.customer.yml   ──cp──►     docker-compose.customer.yml
  assets/launch.sh                     ──cp──►     launch.sh
  flash.version  (image tag pin)                   .env        (random per-box creds)
  00..03 scripts                                   db/{mongo,tick,instrument,strategy}
```

**First-run (customer):**
1. `git clone <flash_bootstrap repo>` (only this repo — no source).
2. `cd flash_bootstrap`
3. `GHCR_USER=<github-user> GHCR_TOKEN=<read:packages PAT> ./00_bootstrap.sh`

→ FLASH live on `:7200` (admin / 123456). Data persists in `flash/db/*`; upgrades just `./launch.sh pull && ./launch.sh start` — data survives.

**Owner side:** build + push the images from the private flash repo with `container/publish.sh`, then bump `flash.version` here to the shipped tag.