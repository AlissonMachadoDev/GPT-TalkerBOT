#!/bin/bash
set -e
APP_DIR="/opt/gpt_talkerbot"
source "$APP_DIR/scripts/check_db.sh"

echo "Fetching secrets from AWS Parameter Store..."
DB_URL=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/database_url" --with-decryption --query Parameter.Value --output text)
KEY_BASE=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/secret_key_base" --with-decryption --query Parameter.Value --output text)
OPENAI_API_KEY=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/openai_api_key" --with-decryption --query Parameter.Value --output text)
GROK_API_KEY=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/grok_api_key" --with-decryption --query Parameter.Value --output text)

TELEGRAM_API_KEY=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/telegram_api_key" --with-decryption --query Parameter.Value --output text)
SERVER_HOST=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/server_host" --with-decryption --query Parameter.Value --output text)

# Tolerante: sem o parâmetro o serviço sobe com secret vazio e a validação
# do webhook fica desligada (o plug loga warning a cada update)
TELEGRAM_WEBHOOK_SECRET=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/telegram_webhook_secret" --with-decryption --query Parameter.Value --output text 2>/dev/null || echo "")
if [ -z "$TELEGRAM_WEBHOOK_SECRET" ]; then
  echo "WARNING: /gpt_talkerbot/prod/telegram_webhook_secret not found - webhook validation will be DISABLED"
fi

# --- Promove a release prebuildada do staging para um diretório versionado ---
# A versão no ar (current/) segue intocada até a troca do symlink lá embaixo.
RELEASE_ID="$(date +%Y%m%d%H%M%S)"
RELEASE_DIR="$APP_DIR/releases/$RELEASE_ID"
NEW_BIN="$RELEASE_DIR/bin/gpt_talkerbot"

echo "Promoting staged release to $RELEASE_DIR ..."
mkdir -p "$APP_DIR/releases"
mv "$APP_DIR/staging" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR/tmp"
chown -R ubuntu:ubuntu "$RELEASE_DIR"
chmod -R 755 "$RELEASE_DIR"

if [ ! -x "$NEW_BIN" ]; then
  echo "FATAL: promoted release binary not found at $NEW_BIN"
  exit 1
fi

# --- systemd aponta para o symlink estável current/ (não para releases/<id>) ---
echo "Writing systemd unit..."
sudo tee /etc/systemd/system/gpt_talkerbot.service >/dev/null <<EOL
[Unit]
Description=GPT TalkerBot Service
After=network.target postgresql.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/gpt_talkerbot

# Application environment variables
Environment="PORT=4004"
Environment="MIX_ENV=prod"
Environment="PHX_HOST=gpt-talkerbot.alissonmachado.dev"
Environment="PHX_SERVER=true"
Environment="POOL_SIZE=10"
Environment="RELEASE_NAME=gpt_talkerbot"
Environment="DATABASE_URL=${DB_URL}"
Environment="SECRET_KEY_BASE=${KEY_BASE}"
Environment="OPENAI_API_KEY=${OPENAI_API_KEY}"
Environment="GROK_API_KEY=${GROK_API_KEY}"
Environment="TELEGRAM_API_KEY=${TELEGRAM_API_KEY}"
Environment="SERVER_HOST=${SERVER_HOST}"
Environment="TELEGRAM_WEBHOOK_SECRET=${TELEGRAM_WEBHOOK_SECRET}"

ExecStart=/opt/gpt_talkerbot/current/bin/gpt_talkerbot start
ExecStop=/opt/gpt_talkerbot/current/bin/gpt_talkerbot stop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

sudo chmod 644 /etc/systemd/system/gpt_talkerbot.service
sudo systemctl daemon-reload

echo "Waiting for database to be ready..."
sleep 4
if ! check_database_connection "$DB_URL"; then
  echo "Cannot proceed - database is not accessible (a versão no ar segue intacta)"
  exit 1
fi

# --- Migra com a release NOVA, ANTES de girar o symlink ---
# Se a migração falhar, current/ ainda aponta para a versão antiga (que segue
# rodando) e o deploy é marcado como falho sem downtime.
echo "Running migrations with the new release..."
DATABASE_URL="${DB_URL}" SECRET_KEY_BASE="${KEY_BASE}" "$NEW_BIN" eval "GptTalkerbot.Release.migrate"

# --- Troca atômica: gira o symlink e faz um único restart ---
# A janela de indisponibilidade fica limitada ao restart do BEAM (~poucos seg).
echo "Switching current -> $RELEASE_DIR"
ln -sfn "$RELEASE_DIR" "$APP_DIR/current"
chown -h ubuntu:ubuntu "$APP_DIR/current"

sudo systemctl enable gpt_talkerbot
sudo systemctl restart gpt_talkerbot

echo "Waiting for service to start..."
sleep 5
sudo systemctl status gpt_talkerbot --no-pager || true

# --- Limpa releases antigas, mantendo as 3 mais recentes ---
echo "Pruning old releases (keeping the 3 newest)..."
cd "$APP_DIR/releases"
ls -1dt */ 2>/dev/null | tail -n +4 | xargs -r rm -rf

echo "start_application completed"
