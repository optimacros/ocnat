# cnet

Download service and prepare env file (`/opt/ocnat/apps/cnet/.env`):

```
sudo apt-get install tinc git jq

cd /opt
sudo git clone https://github.com/optimacros/ocnat
sudo cp -f /opt/ocnat/apps/cnet/.env.example /opt/ocnat/apps/cnet/.env
```

Prepare host template (`/opt/ocnat/apps/cnet/host.tpl`):

```
sudo cp -f /opt/ocnat/apps/cnet/host.tpl.example /opt/ocnat/apps/cnet/host.tpl
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
ip addr add $LAN_IP dev \$INTERFACE
ip route add $LAN_SUBNET dev \$INTERFACE
ip route add $VM_SUBNET dev \$INTERFACE
EOT

cat <<EOT > /etc/tinc/cnet/tinc-down
#!/bin/sh
ip route del $VM_SUBNET dev \$INTERFACE
ip route del $LAN_SUBNET dev \$INTERFACE
ip addr del $LAN_IP dev \$INTERFACE
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