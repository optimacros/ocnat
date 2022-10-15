# cnet

Download service and prepare env file (`/opt/ocnat/apps/cnet/.env`):

```
sudo apt-get install isc-dhcp-server tinc git jq

cd /opt
sudo git clone https://github.com/optimacros/ocnat
sudo cp -f /opt/ocnat/apps/cnet/.env.example /opt/ocnat/apps/cnet/.env
```

Prepare templates:

```
sudo cp -f /opt/ocnat/apps/cnet/vpn-host.tpl.example /opt/ocnat/apps/cnet/vpn-host.tpl
sudo cp -f /opt/ocnat/apps/cnet/isc-dhcp-server.tpl.example /opt/ocnat/apps/cnet/isc-dhcp-server.tpl
sudo cp -f /opt/ocnat/apps/cnet/isc-dhcp-block.tpl.example /opt/ocnat/apps/cnet/isc-dhcp-block.tpl
sudo cp -f /opt/ocnat/apps/cnet/bridge.tpl.example /opt/ocnat/apps/cnet/bridge.tpl
sudo cp -f /etc/network/interfaces /etc/network/interfaces.tpl
echo >> "{VM_BRIDGE_CFG}" > /etc/network/interfaces.tpl
```

Configure services:

```
sudo mkdir /etc/tinc/cnet/

cat <<EOT > /etc/tinc/cnet/tinc.conf
Name = $HOST_NAME
Device = /dev/net/tun
AddressFamily = ipv4
ConnectTo = yyy
ConnectTo = zzz
EOT

cat <<EOT > /etc/tinc/cnet/tinc-up
#!/bin/sh
ip link set \$INTERFACE up
ip addr add $VPN_LAN_IP dev \$INTERFACE
ip route add $VPN_LAN_SUBNET dev \$INTERFACE
ip route add $VM_SUBNET dev \$INTERFACE
EOT

cat <<EOT > /etc/tinc/cnet/tinc-down
#!/bin/sh
ip route del $VM_SUBNET dev \$INTERFACE
ip route del $VPN_LAN_SUBNET dev \$INTERFACE
ip addr del $VPN_LAN_IP dev \$INTERFACE
ip link set \$INTERFACE down
EOT

sudo ln -s /etc/pve/cnet /etc/tinc/cnet/hosts

# Create key files in default paths with command
sudo tincd -n cnet -K

sudo cp -f /opt/ocnat/apps/cnet/cnet.service /etc/systemd/system/cnet.service
sudo cp -f /opt/ocnat/apps/cnet/cnet-reload.service /etc/systemd/system/cnet-reload.service
sudo systemctl start cnet-reload
sudo systemctl enable cnet-reload
```