#!/usr/bin/env bash
set -euo pipefail

PANEL_DIR=/root/panel

# Cap parallel rustc jobs. The panel workspace is large; full parallelism
# spikes RAM and OOM-kills the build (and sshd) on small LXCs. Override with
# JOBS=N if the container has plenty of memory.
JOBS=${JOBS:-2}
export CARGO_BUILD_JOBS="$JOBS"

# --- System packages -------------------------------------------------------
apt update
apt install -y curl git-all build-essential

# --- Node.js (via nvm) -----------------------------------------------------
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
\. "$HOME/.nvm/nvm.sh"
nvm install 24
corepack enable
corepack prepare pnpm@latest --activate

# --- Rust ------------------------------------------------------------------
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# Put cargo/rustc on PATH for the rest of this script
\. "$HOME/.cargo/env"

# --- Docker ----------------------------------------------------------------
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
# In an LXC, the daemon does not always start on install
systemctl enable --now docker || true

# --- Clone calagopus -------------------------------------------------------
git clone https://github.com/calagopus/panel.git "$PANEL_DIR"

# --- Node deps -------------------------------------------------------------
( cd "$PANEL_DIR/frontend" && pnpm i )
( cd "$PANEL_DIR/database" && pnpm i )

# --- Env file --------------------------------------------------------------
cp "$PANEL_DIR/.env.example" "$PANEL_DIR/.env"
# compose.yml db creds are panel/panel/panel, not the .env.example defaults
sed -i "s#^DATABASE_URL=.*#DATABASE_URL=postgresql://panel:panel@localhost:5432/panel#" "$PANEL_DIR/.env"
sed -i "s#^REDIS_URL=.*#REDIS_URL=redis://localhost#" "$PANEL_DIR/.env"
sed -i "s#^APP_ENCRYPTION_KEY=.*#APP_ENCRYPTION_KEY=$(openssl rand -hex 32)#" "$PANEL_DIR/.env"

# --- Expose db + cache to the host -----------------------------------------
# Native (host) backend needs db:5432 and cache:6379 reachable on localhost.
# Override file is auto-merged by docker compose; repo compose.yml untouched.
cat > "$PANEL_DIR/compose.override.yml" <<'EOF'
services:
  db:
    ports:
      - "5432:5432"
  cache:
    ports:
      - "6379:6379"
EOF

# Bring up only db + cache (web/backend runs natively for dev)
( cd "$PANEL_DIR" && docker compose up -d db cache )

# Wait for postgres to accept connections (no healthcheck in compose.yml)
echo "Waiting for postgres..."
until docker compose -f "$PANEL_DIR/compose.yml" -f "$PANEL_DIR/compose.override.yml" exec -T db pg_isready -U panel >/dev/null 2>&1; do
  sleep 1
done

# --- Build frontend (must exist before backend compile) --------------------
( cd "$PANEL_DIR/frontend" && pnpm build )

# --- Migrate database ------------------------------------------------------
( cd "$PANEL_DIR" && SQLX_OFFLINE=true cargo run -p database-migrator -- migrate )

# --- Build backend ---------------------------------------------------------
( cd "$PANEL_DIR" && SQLX_OFFLINE=true cargo build )

# --- systemd unit for backend ----------------------------------------------
cat > /etc/systemd/system/calagopus.service <<EOF
[Unit]
Description=Calagopus Panel backend
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$PANEL_DIR
EnvironmentFile=$PANEL_DIR/.env
ExecStart=$PANEL_DIR/target/debug/panel-rs
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now calagopus.service

echo "Done. Backend on :8000 (systemd: calagopus.service). DB :5432, cache :6379."
