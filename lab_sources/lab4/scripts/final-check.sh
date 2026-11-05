#!/usr/bin/env bash
# Скриншот финальной проверки (запускать из корня проекта/любого каталога на сервере лаборатории)
set -euo pipefail
STUDENT=titov
N=87
ODL="http://10.104.${N}.100:8181"
echo '========================================'
echo "ЛР4 завершена: $(date '+%d.%m.%Y %H:%M:%S')"
echo "Студент: $(whoami)@$(hostname), STUDENT=$STUDENT, N=$N"
echo '========================================'
docker exec "clab-$STUDENT-l4-s2" ovs-vsctl show | grep -E 'Bridge|Controller|is_connected|fail_mode'
curl -sS -u admin:admin -H 'Accept: application/json' \
  "$ODL/rests/data/opendaylight-inventory:nodes?content=nonconfig&depth=3" \
  | jq -c '[."opendaylight-inventory:nodes".node[].id]'
docker exec "clab-$STUDENT-l4-s2" ovs-ofctl -O OpenFlow13 dump-flows br0
docker exec "clab-$STUDENT-l4-h1" ping -c 2 "10.$N.4.3"
