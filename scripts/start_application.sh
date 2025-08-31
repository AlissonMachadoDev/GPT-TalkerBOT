#!/bin/bash
set -e
source /opt/gpt_talkerbot/scripts/check_db.sh

echo "Fetching secrets from AWS Parameter Store..."
DB_URL=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/database_url" --with-decryption --query Parameter.Value --output text)
KEY_BASE=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/secret_key_base" --with-decryption --query Parameter.Value --output text)
ALLOWED_GROUPS=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/allowed_groups" --with-decryption --query Parameter.Value --output text)
OPENAI_API_KEY=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/openai_api_key" --with-decryption --query Parameter.Value --output text)
DEFAULT_PROMPT=$(aws ssm get-parameter --name "/gpt_talkerbot/prod/default_prompt" --with-decryption --query Parameter.Value --output text)

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
Environment=PORT=4004
Environment=MIX_ENV=prod
Environment=PHX_HOST=gpt-talkerbot.alissonmachado.dev
Environment=PHX_SERVER=true
Environment=POOL_SIZE=10
Environment=RELEASE_NAME=gpt_talkerbot
Environment=DATABASE_URL=${DB_URL}
Environment=SECRET_KEY_BASE=${KEY_BASE}
Environment=ALLOWED_GROUPS=${ALLOWED_GROUPS}
Environment=OPENAI_API_KEY=${OPENAI_API_KEY}
Environment=DEFAULT_PROMPT=${DEFAULT_PROMPT}

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
DATABASE_URL="${DB_URL}" SECRET_KEY_BASE="${KEY_BASE}" /opt/gpt_talkerbot/_build/prod/rel/gpt_talkerbot/bin/gpt_talkerbot eval "DigistabStore.Release.migrate"

echo "Enabling and starting gpt_talkerbot service..."
sudo systemctl enable gpt_talkerbot
sudo systemctl restart gpt_talkerbot

echo "Waiting for service to start..."
sleep 5

echo "Checking service status..."
sudo systemctl status gpt_talkerbot
