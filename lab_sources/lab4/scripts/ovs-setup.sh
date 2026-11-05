#!/bin/sh
# Применять: docker exec -i -e DPID=1 -e ODL_IP=10.104.87.100 clab-titov-l4-s1 sh < scripts/ovs-setup.sh
set -e
: "${DPID:?Укажите DPID=1 или DPID=2}"
: "${ODL_IP:?Укажите ODL_IP=10.104.87.100}"
ovs-vsctl --may-exist add-br br0 -- set bridge br0 datapath_type=netdev protocols=OpenFlow13 \
  fail-mode=secure other-config:datapath-id=$(printf '%016x' "$DPID") other-config:disable-in-band=true
for i in 1 2 3; do
  ip link show "eth$i" >/dev/null 2>&1 || continue
  ethtool -K "eth$i" tx off >/dev/null 2>&1 || true
  ovs-vsctl --may-exist add-port br0 "eth$i" -- set interface "eth$i" ofport_request="$i"
done
ovs-vsctl set-controller br0 "tcp:${ODL_IP}:6653"
ovs-vsctl show
