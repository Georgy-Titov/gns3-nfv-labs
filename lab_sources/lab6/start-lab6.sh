#!/usr/bin/env bash
# ЛР6: восстановление финального состояния после Heal (оба клиента через fw2).
# Запускать из WSL2: ./start-lab6.sh
# ВНИМАНИЕ: пересоздаёт только runtime-контейнеры clab-titov-l6-*.
set -Eeuo pipefail
trap 'echo "[ОШИБКА] Скрипт остановился на строке $LINENO" >&2' ERR

export STUDENT=titov N=87
cd "$(dirname "${BASH_SOURCE[0]}")"
LAB="clab-${STUDENT}-l6"
SERVER="${LAB}-server"
SW="${LAB}-sw"
ODL="${LAB}-odl"
FW2="${LAB}-fw2"
SHAPER="${LAB}-shaper1"

log() { printf '\n[ЛР6] %s\n' "$*"; }
fail() { echo "[ОШИБКА] $*" >&2; exit 1; }

log "Проверка инструментов и сохранённой конфигурации"
for cmd in docker containerlab python3 envsubst timeout; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Не найдена команда: $cmd"
done
docker info >/dev/null 2>&1 || fail "Docker недоступен. Запустите Docker Desktop (или службу Docker) и повторите."
python3 -c 'import requests, yaml' || fail "Нужны python3-requests и python3-yaml"
for file in lab6.clab.yml vnfm.sh nfvo.py vnffg.yaml vnf/fw-rules.nft scripts/sw-setup.sh; do
  [[ -f "$file" ]] || fail "Отсутствует файл $file"
done
grep -Fq 'table ip vnf_fw' vnf/fw-rules.nft || fail "В vnf/fw-rules.nft нет адаптации table ip vnf_fw для WSL2"
grep -Fq 'burst 256kbit' vnfm.sh || fail "В vnfm.sh не сохранено исправление burst 256kbit"
python3 - <<'PY'
import os, yaml
with open('vnffg.yaml', encoding='utf-8') as f:
    cfg = yaml.safe_load(os.path.expandvars(f.read()))
chains = cfg.get('chains', [])
if len(chains) != 2 or any(c.get('path') != ['fw2', 'shaper1'] for c in chains):
    raise SystemExit('ОШИБКА: vnffg.yaml должен содержать обе цепочки через [fw2, shaper1]')
PY

log "Удаление прежних runtime-контейнеров только этой лабораторной"
# fw2 создан через docker run, поэтому Containerlab сам его не удаляет.
if docker container inspect "$FW2" >/dev/null 2>&1; then
  docker rm -f "$FW2" >/dev/null
fi
if docker ps -a --format '{{.Names}}' | grep -q "^${LAB}-"; then
  containerlab destroy -t lab6.clab.yml --cleanup
fi

log "Развёртывание NFVI"
containerlab deploy -t lab6.clab.yml

log "Запуск сервисов сервера (HTTP 80/8087 и iperf3 5201)"
docker exec -d "$SERVER" iperf3 -s
docker exec -d "$SERVER" python3 -u -m http.server "$((8000 + N))"
for port in 80 8087 5201; do
  listening=0
  for attempt in $(seq 1 10); do
    if docker exec "$SERVER" ss -lnt | grep -Eq ":${port}[[:space:]]"; then
      listening=1
      break
    fi
    sleep 1
  done
  [[ "$listening" == 1 ]] || fail "Сервер не слушает TCP/$port"
done

log "Ожидание OpenDaylight и установка OpenFlow-функций"
ODL_LOG="/tmp/lab6-odl-install-${STUDENT}.log"
odl_ready=0
for attempt in $(seq 1 18); do
  if timeout 90s docker exec -t "$ODL" /opt/odl/bin/client \
      'feature:install odl-openflowplugin-flow-services-rest odl-openflowplugin-app-table-miss-enforcer' \
      >"$ODL_LOG" 2>&1; then
    odl_ready=1
    break
  fi
  echo "  OpenDaylight ещё не готов (попытка ${attempt}/18), ждём 8 секунд..."
  sleep 8
done
if [[ "$odl_ready" != 1 ]]; then
  tail -30 "$ODL_LOG" >&2 || true
  fail "Не удалось установить функции OpenDaylight"
fi

log "Настройка OVS и подключения к SDN-контроллеру"
docker exec -i -e "ODL_IP=10.106.${N}.100" "$SW" sh < scripts/sw-setup.sh
connected=0
for attempt in $(seq 1 30); do
  if docker exec "$SW" ovs-vsctl --columns=is_connected list Controller 2>/dev/null \
      | grep -Eq 'is_connected[[:space:]]*:[[:space:]]*true'; then
    connected=1
    break
  fi
  sleep 3
done
[[ "$connected" == 1 ]] || fail "OVS не подключился к OpenDaylight"

log "Настройка Shaper (17 Mbit/s, burst 256 kbit)"
./vnfm.sh configure shaper1 shaper

log "Создание FW2 и включение фильтрации bridge-трафика через nft ip"
./vnfm.sh instantiate fw2 fw 5 6
docker exec "$FW2" sysctl -w net.bridge.bridge-nf-call-iptables=1

log "Удаление FW1 — восстановление финального состояния после Heal"
./vnfm.sh terminate fw1 3 4

log "Применение VNFFG (Client 1 и Client 2 через FW2 -> Shaper1)"
flows_applied=0
for attempt in $(seq 1 12); do
  if python3 nfvo.py apply vnffg.yaml; then
    flows_applied=1
    break
  fi
  echo "  RESTCONF/ODL ещё не готов, повтор через 5 секунд (${attempt}/12)..."
  sleep 5
done
[[ "$flows_applied" == 1 ]] || fail "Не удалось применить VNFFG"

log "Ожидание установки 24 правил OpenFlow"
count=0
for attempt in $(seq 1 20); do
  count=$(docker exec "$SW" ovs-ofctl -O OpenFlow13 dump-flows br0 \
      | grep -c 'priority=300' || true)
  [[ "$count" == 24 ]] && break
  sleep 2
done
[[ "$count" == 24 ]] || fail "Ожидалось 24 правила, найдено: $count"

log "Проверка связности обоих клиентов"
docker exec "${LAB}-client1" ping -c 2 -W 2 "10.${N}.6.100"
docker exec "${LAB}-client2" ping -c 2 -W 2 "10.${N}.6.100"

log "Проверка HTTP, Firewall и Shaper"
http_code=$(docker exec "${LAB}-client1" curl -sS -m 5 -o /dev/null \
    -w '%{http_code}' "http://10.${N}.6.100/")
[[ "$http_code" == 200 ]] || fail "HTTP вернул $http_code вместо 200"
docker exec "$FW2" nft list ruleset | grep 'block tcp'
docker exec "$SHAPER" tc qdisc show dev eth2
./vnfm.sh list
printf '\n[ГОТОВО] ЛР6 восстановлена: 24 правила, HTTP %s, оба клиента доступны.\n' "$http_code"
