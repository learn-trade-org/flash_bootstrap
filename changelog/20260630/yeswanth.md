# 2026-06-30

## Server maintenance layer — 4 GB swap, run at bootstrap + nightly (branch `yeswanth/server_maintenance`)

A host-level **convergence layer** so already-installed boxes pick up host fixes (not just image updates).

```
04_server_maintenance.sh → server_maintenance/00_main.sh → 01_add_swap.sh
called by:  00_bootstrap.sh (provision)   bin/00_main.sh (nightly, after git pull)
```

- `server_maintenance/00_main.sh` runs tasks with **explicit calls** (no loop, for readability), each wrapped `|| log` so one failure never blocks the rest.
- `01_add_swap.sh` — **4 GB** swapfile, idempotent (skips if swap already active), persisted in `/etc/fstab`, `vm.swappiness=10`. Fixes OOM on the 1 GB droplets during instrument refresh.
- `04_server_maintenance.sh` is the numbered bootstrap step that delegates to the folder's `00_main.sh`.
- Tasks + runner ship via `git pull`; the one-line hook in `bin/00_main` rides the self-refresh → one-time one-night lag on existing boxes, then every future task runs the next night. Add a fix = drop a `server_maintenance/0N_*.sh` + one explicit line.

Exec bits `100755`; syntax-checked. Real swap runs Linux-only (uses `swapon`/`mkswap`/`fallocate`).
