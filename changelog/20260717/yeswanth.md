# 2026-07-17

## Install-step progress pings (branch `yeswanth/progress_steps_00`)

The one-click deploy only ever pinged `CLONE` (from cloud-init) and `DONE`/`FAILED` — `DOCKER`/`PULL`/`UP` existed in the flashtrade.in enum but nothing sent them, so the deploy page had no real progress to show.

- `00_bootstrap.sh` — `reportProgressStep()` helper: pings `$FLASH_PROGRESS_URL?cloudId=$FLASH_CLOUD_ID&step=<step>`; both vars come from cloud-init on one-click deploys, manual runs skip silently.
- Pings: `DOCKER` before `01_install_host.sh`, `PULL` before `03_compose_up.sh`, `UP` after it — real step sequence becomes `CLONE → DOCKER → PULL → UP → DONE`.

Pairs with flashtrade.in `yeswanth/ui_refinement_01` (frontend progress bar mapped to `installStep`).

Verified: `bash -n` clean; each step value accepted by `/deploy/progress` (200) and persisted to the deployment doc in local dev.
