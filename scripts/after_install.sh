#!/bin/bash
set -e

# Nível 1: nada de mix/deps.get/release aqui — a release já vem compilada do CI.
# Só validamos que o binário prebuildado chegou no staging e ajustamos perms.
APP_DIR="/opt/gpt_talkerbot"
STAGED_BIN="$APP_DIR/staging/bin/gpt_talkerbot"

echo "Verifying staged release..."
if [ ! -x "$STAGED_BIN" ]; then
  echo "FATAL: staged release binary not found or not executable at $STAGED_BIN"
  exit 1
fi

chown -R ubuntu:ubuntu "$APP_DIR/staging" "$APP_DIR/scripts"
chmod +x "$APP_DIR/scripts"/*.sh 2>/dev/null || true

echo "after_install completed"
exit 0
