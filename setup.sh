# Update apt
apt update

# Install curl
apt install -y curl

# Install git
apt install -y git-all

# Install NodeJS

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
\. "$HOME/.nvm/nvm.sh"
nvm install 24
corepack enable pnpm

# Install Rust

apt install -y build-essential
yes "" | curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install Docker

curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Clone calagopus
git clone https://github.com/calagopus/panel.git /root/panel

# Install calagopus node deps
cd /root/panel/frontend && pnpm i
cd /root/panel/database && pnpm i

# Create env
cp /root/panel/.env.example /root/panel/.env

# Build frontend
cd /root/panel/frontend && pnpm build

# Expose database and cache

# Migrate database
cd /root/panel && SQLX_OFFLINE=true cargo run -p database-migrator -- migrate

# Build backend
SQLX_OFFLINE=true cargo build

# Create systemctl for backend
