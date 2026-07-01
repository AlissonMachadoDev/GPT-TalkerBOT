#!/bin/bash
set -e
source /opt/gpt_talkerbot/scripts/check_db.sh

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

echo "Setting up directory permissions..."
sudo mkdir -p /opt/gpt_talkerbot/_build/prod/rel/gpt_talkerbot/tmp
sudo chown -R ubuntu:ubuntu /opt/gpt_talkerbot/_build/prod/rel/gpt_talkerbot/tmp
sudo chmod -R 755 /opt/gpt_talkerbot/_build/prod/rel/gpt_talkerbot/tmp

echo "Creating systemd service file..."
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

ExecStart=/opt/gpt_talkerbot/_build/prod/rel/gpt_talkerbot/bin/gpt_talkerbot start
ExecStop=/opt/gpt_talkerbot/_build/prod/rel/gpt_talkerbot/bin/gpt_talkerbot stop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

echo "Setting proper permissions..."
sudo chmod 644 /etc/systemd/system/gpt_talkerbot.service

# echo "Downloading RDS certificate if needed..."
# if [ ! -f "/etc/ssl/certs/rds-ca-global.pem" ]; then
#     sudo curl -o /etc/ssl/certs/rds-ca-global.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
#     sudo chmod 644 /etc/ssl/certs/rds-ca-global.pem
# fi

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Give some time for RDS to be fully available
echo "Waiting for RDS to be ready..."
sleep 4

if ! check_database_connection "$DB_URL"; then
  echo "Cannot proceed with deployment - database is not accessible"
  exit 1
fi

echo "Creating database if needed and running migrations..."
DATABASE_URL="${DB_URL}" SECRET_KEY_BASE="${KEY_BASE}" /opt/gpt_talkerbot/_build/prod/rel/gpt_talkerbot/bin/gpt_talkerbot eval "GptTalkerbot.Release.migrate"

echo "Enabling and starting gpt_talkerbot service..."
sudo systemctl enable gpt_talkerbot
sudo systemctl restart gpt_talkerbot

echo "Waiting for service to start..."
sleep 5

echo "Checking service status..."
sudo systemctl status gpt_talkerbot
