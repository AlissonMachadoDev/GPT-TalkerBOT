#!/bin/sh
# Configura o ambiente local para desenvolvimento — NÃO sobe a aplicação:
#   1. Abre um túnel ngrok em background (PID salvo em .ngrok.pid)
#   2. Aponta o webhook do Telegram para <ngrok>/webhook
#
# Depois disso, suba o app manualmente: iex -S mix phx.server
#
# Uso:
#   scripts/dev_up.sh        # sobe túnel + registra webhook
#   scripts/dev_up.sh stop   # encerra o ngrok
#
# ATENÇÃO: o setWebhook redireciona TODOS os updates do bot para a sua
# máquina. Se o token em dev.secret.exs for o mesmo do bot de produção,
# produção para de receber mensagens até o webhook ser restaurado.
set -eu

cd "$(dirname "$0")/.."

PORT=4000
PID_FILE=".ngrok.pid"

if [ "${1:-}" = "stop" ]; then
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "ngrok encerrado."
    echo "O webhook do Telegram ainda aponta para o túnel morto — restaure com:"
    echo "  curl \"https://api.telegram.org/bot<TOKEN>/setWebhook?url=<SERVER_HOST_PROD>&secret_token=<SECRET>\""
  else
    echo "Nenhum ngrok registrado em ${PID_FILE}."
  fi
  exit 0
fi

if ! command -v ngrok >/dev/null; then
  echo "ERRO: ngrok não está instalado (https://ngrok.com/download)"
  exit 1
fi

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "==> ngrok já está rodando (PID $(cat "$PID_FILE")), reaproveitando o túnel..."
else
  echo "==> Iniciando ngrok em background..."
  nohup ngrok http ${PORT} --log=stdout >/dev/null 2>&1 &
  echo $! > "$PID_FILE"
fi

echo "==> Esperando o túnel abrir..."
NGROK_URL=""
i=0
while [ $i -lt 30 ]; do
  NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | python3 -c "
import json, sys
try:
    tunnels = json.load(sys.stdin)['tunnels']
    print(next(t['public_url'] for t in tunnels if t['public_url'].startswith('https')))
except Exception:
    pass
" || true)
  [ -n "${NGROK_URL}" ] && break
  i=$((i + 1))
  sleep 1
done

if [ -z "${NGROK_URL}" ]; then
  echo "ERRO: ngrok não abriu o túnel em 30s"
  exit 1
fi

SERVER_HOST="${NGROK_URL}/webhook"

# Token do bot: env TELEGRAM_API_KEY ou o valor do dev.secret.exs
TOKEN="${TELEGRAM_API_KEY:-$(grep -oP ':telegram_api_key,\s*"\K[^"]+' config/dev.secret.exs || true)}"
if [ -z "${TOKEN}" ]; then
  echo "ERRO: telegram_api_key não encontrado (env TELEGRAM_API_KEY ou config/dev.secret.exs)"
  exit 1
fi

echo "==> Registrando webhook: ${SERVER_HOST}"
WEBHOOK_ARGS="url=${SERVER_HOST}&drop_pending_updates=true"
if [ -n "${TELEGRAM_WEBHOOK_SECRET:-}" ]; then
  WEBHOOK_ARGS="${WEBHOOK_ARGS}&secret_token=${TELEGRAM_WEBHOOK_SECRET}"
fi

RESPONSE=$(curl -s "https://api.telegram.org/bot${TOKEN}/setWebhook?${WEBHOOK_ARGS}")
case "$RESPONSE" in
  *'"ok":true'*) ;;
  *)
    echo "ERRO ao registrar webhook: ${RESPONSE}"
    exit 1
    ;;
esac

echo ""
echo "==> Pronto. Ambiente apontado para a sua máquina:"
echo "    webhook:  ${SERVER_HOST}"
echo "    ngrok:    PID $(cat "$PID_FILE") em background (scripts/dev_up.sh stop para encerrar)"
echo ""
echo "    Agora suba o app:  iex -S mix phx.server"
