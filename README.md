# c7s-scripts

Quick setup scripts for a Debian LXC [calagopus](https://github.com/calagopus/panel) panel dev environment.

`setup.sh` provisions a fresh Debian LXC from nothing to a running panel backend: installs all tooling, clones the panel, starts the database and cache in Docker, builds the frontend and backend, and registers the backend as a systemd service.

## Prerequisites

- A **Debian LXC** (run as `root`).
- Docker requires container **nesting** enabled. On Proxmox set the container to:
  ```
  features: nesting=1,keyctl=1
  ```
  Without this the Docker daemon will not start and `db`/`cache` containers fail.
- Outbound internet (pulls nvm, rustup, Docker, the panel repo, and images).

## Usage

A fresh Debian LXC has neither `git` nor `curl`. Install `curl` first, then fetch and run the script (it installs `git` and everything else itself):

```sh
apt update && apt install -y curl
curl -fsSL -O https://raw.githubusercontent.com/zephrynis/c7s-scripts/main/setup.sh
bash setup.sh
```

The script is idempotent-unfriendly — run it once on a clean container. It exits on first error (`set -euo pipefail`).

## What it does

| Step | Detail |
|------|--------|
| System packages | `curl`, `git-all`, `build-essential` |
| Node.js | nvm → Node 24, pnpm (latest) via corepack |
| Rust | rustup stable, sourced onto `PATH` |
| Docker | install + start daemon |
| Clone | `calagopus/panel` → `/root/panel` |
| Node deps | `pnpm i` in `frontend/` and `database/` |
| `.env` | from `.env.example`, with corrected DB creds + random encryption key |
| Database + cache | `db` (Postgres 5432) and `cache` (Valkey 6379) via Docker, ports exposed |
| Frontend | `pnpm build` |
| Migrate | `cargo run -p database-migrator -- migrate` |
| Backend | `cargo build` |
| systemd | `calagopus.service` running `target/debug/panel-rs` |

## Ports

| Service | Host port |
|---------|-----------|
| Panel backend | `8000` |
| Postgres (`db`) | `5432` |
| Valkey (`cache`) | `6379` |

`db` and `cache` are exposed to the host via `/root/panel/compose.override.yml` (auto-merged by Docker Compose) so the natively-running backend can reach them on `localhost`. The repo's `compose.yml` is left untouched.

## After setup

Backend runs under systemd:

```sh
systemctl status calagopus
journalctl -u calagopus -f
```

To iterate on the backend manually instead of via the service:

```sh
systemctl stop calagopus
cd /root/panel
cargo run                 # add SQLX_OFFLINE=true on first build
```

Frontend dev server:

```sh
cd /root/panel/frontend
pnpm dev
```

## Config notes

- DB credentials are `panel:panel` / database `panel` (set by the panel `compose.yml`). `.env`'s `DATABASE_URL` is rewritten to match.
- `APP_ENCRYPTION_KEY` is generated per-run with `openssl rand -hex 32`.
- `DATABASE_MIGRATE=true` in `.env` means the backend also auto-migrates on boot; the explicit migrate step just front-loads it.
