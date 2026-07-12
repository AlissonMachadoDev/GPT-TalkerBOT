#!/bin/bash
set -e

# O start_application já reiniciou o serviço com a release nova — aqui NÃO
# reiniciamos de novo (o restart antigo era redundante e apontava para a porta
# errada). Só validamos que a release nova subiu e está respondendo em :4004.

echo "Waiting for service to become active..."
for _ in $(seq 1 15); do
  if systemctl is-active --quiet gpt_talkerbot.service; then
    break
  fi
  sleep 2
done
systemctl is-active gpt_talkerbot.service

echo "Probing /health on :4004 ..."
if ! timeout 30 bash -c 'until curl -fsS http://localhost:4004/health >/dev/null 2>&1; do sleep 1; done'; then
  echo "FATAL: /health did not return 200 within 30s"
  exit 1
fi

echo "validate_service OK"
exit 0
