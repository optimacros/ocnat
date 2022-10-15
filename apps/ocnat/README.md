# ocnat

Create json file with rules in directory (`/etc/pve/ocnat/xxx.json`)

Example:

```
{
  "routes": {
    "pre": [
      {
        "name": "custom-public-port-to-vm-local-http",
        "description": "Route input traffic from 1.1.1.1:3003 to 10.10.3.98:80",
        "from": {
          "interface": "eth0",
          "address": "1.1.1.1",
          "ports": "3003"
        },
        "to": {
          "address": "10.10.3.98/30",
          "ports": "80"
        }
      },
      {
        "name": "custom-public-port-to-vm-local-https",
        "description": "Route input traffic from 1.1.1.1:3004 to 10.10.3.98:433",
        "from": {
          "interface": "eth0",
          "address": "1.1.1.1",
          "ports": "3004"
        },
        "to": {
          "address": "10.10.3.98/30",
          "ports": "443"
        }
      },
      {
        "name": "all-public-ports-to-same-vm-local-ports",
        "description": "Route input traffic from 2.2.2.2:* to 10.10.3.102:*",
        "from": {
          "interface": "eth0",
          "address": "2.2.2.2"
        },
        "to": {
          "address": "10.10.3.102/30"
        }
      },
      {
        "name": "http-and-https-public-ports-to-same-vm-local-ports",
        "description": "Route input traffic from 3.3.3.3:80 to 10.10.3.104:80 and 3.3.3.3:443 to 10.10.3.104:443",
        "from": {
          "interface": "eth0",
          "address": "3.3.3.3",
          "ports": "80,443"
        },
        "to": {
          "address": "10.10.3.104/30"
        }
      }
    ],
    "post": [
      {
        "name": "cloud-world",
        "description": "Allow private cloud to public network",
        "from": {
          "address": "10.10.0.0/16"
        },
        "to": {
          "interface": "eth0"
        }
      }
    ]
  }
}
```

Download service and prepare env file (`/etc/systemd/system/.env`):

```
cd /opt
sudo apt-get install git jq
sudo git clone https://github.com/optimacros/ocnat
sudo cp -f ocnat/apps/ocnat/.env.example /etc/systemd/system/.env
```

Configure services:

```
sudo cp -f ocnat/apps/ocnat/ocnat.service /etc/systemd/system/ocnat.service
sudo systemctl start ocnat.service
sudo systemctl enable ocnat.service
```