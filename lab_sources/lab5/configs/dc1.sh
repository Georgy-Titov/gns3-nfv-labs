#!/usr/bin/env bash
set -euo pipefail

echo "=== Starting FRR services ==="

for svc in zebra mgmtd staticd bgpd; do
    if ! supervisorctl status "$svc" | grep -q RUNNING; then
        supervisorctl start "$svc"
    fi
done

echo "=== Configuring SONiC interfaces ==="

config interface startup Ethernet0
config interface startup Ethernet4

if ! ip -4 -o addr show dev Ethernet0 | grep -q '10.87.100.1/24'; then
    config interface ip add Ethernet0 10.87.100.1/24
fi

if ! ip -4 -o addr show dev Ethernet4 | grep -q '10.87.1.1/30'; then
    config interface ip add Ethernet4 10.87.1.1/30
fi

echo "=== Removing management default route ==="

if ip route show default | grep -q 'dev eth0'; then
    ip route del default dev eth0
fi

echo "=== Configuring BGP ==="

vtysh \
    -c 'configure terminal' \
    -c 'router bgp 65087' \
    -c 'bgp router-id 10.87.1.1' \
    -c 'no bgp ebgp-requires-policy' \
    -c 'neighbor 10.87.1.2 remote-as 65187' \
    -c 'address-family ipv4 unicast' \
    -c 'network 10.87.100.0/24' \
    -c 'end' \
    -c 'write memory'

echo "=== SONiC configuration applied ==="

ip -br addr show Ethernet0
ip -br addr show Ethernet4
ip route show default
