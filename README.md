# flash_bootstrap

Host-provisioning scripts that take a bare droplet to a running FLASH in one command: install Docker, generate `.env`, start the stack.
Numbered run-order — `00_bootstrap.sh` orchestrates `01_install_host` → `02_gen_env` → `03_compose_up`; the FLASH engine itself lives in the sibling private `flash/` repo (cloned manually).
First-run: `git clone` both repos onto the droplet, then `cd flash_bootstrap && ./00_bootstrap.sh` → FLASH live on `:7200` (admin / 123456).