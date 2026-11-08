# 2026-11-07 08:54:47 by RouterOS 7.23.8
# system id = C47rSGp0f1B
#
/interface ethernet set [ find default-name=ether1 ] disable-running-check=no
/interface ethernet set [ find default-name=ether2 ] disable-running-check=no
/interface ethernet set [ find default-name=ether3 ] disable-running-check=no
/interface wireguard add listen-port=13087 mtu=1420 name=wg-br
/routing bgp instance add as=65187 name=hq
/interface wireguard peers add allowed-address=10.87.254.2/32,10.87.200.0/24 endpoint-address=100.64.2.2 endpoint-port=13087 interface=wg-br name=peer2 persistent-keepalive=25s public-key="jUnOybDZt2w9iDr5dm4Vik4c/RIJDjzDvxUMcmi6kVA="
/ip address add address=10.87.1.2/30 comment="to DC" interface=ether2 network=10.87.1.0
/ip address add address=100.64.1.2/30 comment=WAN interface=ether3 network=100.64.1.0
/ip address add address=10.87.254.1/30 interface=wg-br network=10.87.254.0
/ip firewall address-list add address=10.87.200.0/24 list=to-dc
/ip firewall filter add action=accept chain=input comment="input: established" connection-state=established,related
/ip firewall filter add action=drop chain=input connection-state=invalid
/ip firewall filter add action=accept chain=input protocol=icmp
/ip firewall filter add action=accept chain=input comment="mgmt (containerlab)" in-interface=ether1
/ip firewall filter add action=accept chain=input comment="BGP from DC" dst-port=179 in-interface=ether2 protocol=tcp
/ip firewall filter add action=accept chain=input comment=WireGuard dst-port=13087 in-interface=ether3 protocol=udp
/ip firewall filter add action=drop chain=input comment="drop other from WAN" in-interface=ether3
/ip firewall filter add action=accept chain=forward comment="forward: established" connection-state=established,related
/ip firewall filter add action=drop chain=forward connection-state=invalid
/ip firewall filter add action=accept chain=forward comment="DC -> Internet" in-interface=ether2 out-interface=ether3
/ip firewall filter add action=accept chain=forward comment="branch -> DC" in-interface=wg-br out-interface=ether2
/ip firewall filter add action=accept chain=forward comment="DC -> branch" in-interface=ether2 out-interface=wg-br
/ip firewall filter add action=drop chain=forward comment="default deny"
/ip firewall nat add action=masquerade chain=srcnat comment="inside -> Internet" out-interface=ether3
/ip route add comment=ISP dst-address=0.0.0.0/0 gateway=100.64.1.1
/ip route add dst-address=10.87.200.0/24 gateway=wg-br
/routing bgp connection add instance=hq local.role=ebgp name=to-dc output.default-originate=if-installed .network=to-dc remote.address=10.87.1.1 .as=65087
/system identity set name=hq-titov
