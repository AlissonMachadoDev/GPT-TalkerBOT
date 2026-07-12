#!/bin/bash
# Nível 1: a troca é atômica no start_application (migra a release nova, gira o
# symlink current/ e faz um único systemctl restart). Parar o app neste hook só
# abriria uma janela de downtime desnecessária — então é um no-op intencional.
echo "ApplicationStop: no-op (troca atômica acontece no start_application)"
exit 0
