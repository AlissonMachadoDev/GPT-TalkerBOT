#!/bin/bash
set -e

# Nível 1: NÃO paramos nem apagamos a release que está no ar. A nova release
# chega prebuildada do CI e só é ativada no final (start_application). Aqui só
# preparamos o diretório de staging que vai receber os arquivos.
APP_DIR="/opt/gpt_talkerbot"

echo "Preparing directories..."
mkdir -p "$APP_DIR/staging" "$APP_DIR/releases"

# Limpa apenas o staging (restos de um deploy anterior que tenha falhado).
# releases/ e o symlink current/ — a versão no ar — ficam intactos.
echo "Cleaning staging (leaving live release untouched)..."
rm -rf "$APP_DIR/staging"/* "$APP_DIR/staging"/.[!.]* 2>/dev/null || true

chown -R ubuntu:ubuntu "$APP_DIR/staging" "$APP_DIR/releases"

echo "before_install completed"
exit 0
