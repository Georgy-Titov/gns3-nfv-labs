#!/usr/bin/env bash
set -euo pipefail

# Переходим в корень lab5 независимо от места запуска
cd "$(dirname "$0")/.."

DC="clab-titov-l5-dc1"
HQ="clab-titov-l5-hq"
BR="clab-titov-l5-br"

echo "========================================"
echo "  LAB 5 - RESTORE CONFIGURATION"
echo "========================================"

# 1. Восстановление SONiC
echo
echo "[1/5] Restoring SONiC interfaces and BGP"

docker cp configs/dc1.sh "$DC":/tmp/lab5-dc1.sh
docker exec "$DC" bash /tmp/lab5-dc1.sh

# 2. Получение текущих публичных ключей
echo
echo "[2/5] Reading WireGuard public keys"

echo "Reading HQ public key (SSH password may be required)"
HQ_PUB=$(ssh admin@"$HQ" \
    ':put [/interface wireguard get wg-br public-key]' \
    | tr -d '\r\n')

echo "Reading BR public key (SSH password may be required)"
BR_PUB=$(ssh admin@"$BR" \
    ':put [/interface wireguard get wg-hq public-key]' \
    | tr -d '\r\n')

# Проверяем формат ключей
for key in "$HQ_PUB" "$BR_PUB"; do
    if [[ ! "$key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
        echo "ERROR: Invalid WireGuard public key"
        echo "Check RouterOS startup configuration"
        exit 1
    fi
done

echo "Both WireGuard public keys received"

# 3. Обновление ключей пиров
echo
echo "[3/5] Updating WireGuard peers"

ssh admin@"$HQ" \
    "/interface wireguard peers set [find where interface=wg-br] public-key=\"$BR_PUB\""

ssh admin@"$BR" \
    "/interface wireguard peers set [find where interface=wg-hq] public-key=\"$HQ_PUB\""

echo "WireGuard peer keys updated"

# 4. Проверка BGP
echo
echo "[4/5] Checking BGP"

docker exec "$DC" vtysh -c "show bgp summary"
docker exec "$DC" vtysh -c "show ip route 10.87.200.0/24"

# 5. Проверка связи филиала с ЦОД
echo
echo "[5/5] Testing branch -> DC connectivity"

for attempt in 1 2 3 4 5; do
    if docker exec clab-titov-l5-pcb \
        ping -c 3 -W 2 10.87.100.10; then
        echo
        echo "RESTORE SUCCESSFUL"
        exit 0
    fi

    echo "Waiting for BGP/WireGuard convergence..."
    sleep 3
done

echo "ERROR: Connectivity test failed"
exit 1
