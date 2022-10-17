#!/bin/bash

# version: 1.0.1

set -e

ENV_PATH=$1

export $(grep -v '^#' "${ENV_PATH}" | xargs)

get_obj_prop() {
  local DATA=$1
  local KEY=$2
  echo ${DATA} | jq -c -r "${KEY}"
}

replace_variable_tpl() {
  local DATA=$1
  local SEARCH=$2
  local REPLACE=$3
  export SEARCH="{${SEARCH}}"
  export REPLACE="${REPLACE}"
  echo "${DATA}" | perl -pe 's/$ENV{"SEARCH"}/$ENV{"REPLACE"}/g'
}

get_dhcp_dns_search() {
  local DATA=$1
  local RESULT=""
  for ROW in $(echo "${DATA}" | jq -c -r '.[]'); do
    RESULT="${RESULT}\"${ROW}\", "
  done
  echo ${RESULT%??}
}

get_dhcp_dns_server() {
  local DATA=$1
  local RESULT=""
  for ROW in $(echo "${DATA}" | jq -c -r '.[]'); do
    RESULT="${RESULT}${ROW}, "
  done
  echo ${RESULT%??}
}

WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "${WORK_DIR}"' EXIT

cd ${WORK_DIR}

# Template data variables
QEMU_NET_TPL_DATA="virtio={MAC},bridge={BRIDGE_NAME},firewall=1"
LXC_NET_TPL_DATA="name={ADAPTER_NAME},bridge={BRIDGE_NAME},firewall=1,gw={GATEWAY},hwaddr={MAC},ip={ADDRESS_SUBNET},type=veth"
DHCP_SERVER_TPL_DATA=$(cat ${DHCP_SERVER_TPL_PATH})
DHCP_SUBNET_TPL_DATA=$(cat ${DHCP_SUBNET_TPL_PATH})
DHCP_CFG_TPL_DATA=$(cat ${DHCP_CFG_TPL_PATH})
BRIDGE_TPL_DATA=$(cat ${BRIDGE_TPL_PATH})
VPN_HOST_TPL_DATA=$(cat ${VPN_HOST_TPL_PATH})
NETWORK_CFG_TPL_DATA=$(cat ${NETWORK_CFG_TPL_PATH})
VM_ADAPTER_TPL_DATA="{\"id\":\"{ID}\",\"vmid\":\"{VMID}\",\"type\":\"{TYPE}\",\"data\":\"{VM_NET_CFG}\"}"
VM_ITEM_TPL_DATA="{\"vmid\":\"{VMID}\",\"type\":\"{TYPE}\",\"name_field\":\"{NAME_FIELD}\",\"net_tpl\":\"{NET_TPL}\"}"

# Static data variables
NL=$'\n'
QEMU_LIST_DATA=$(pvesh get /nodes/${NODE_NAME}/qemu --output-format json)
LXC_LIST_DATA=$(pvesh get /nodes/${NODE_NAME}/lxc --output-format json)
NET_MAP_CONFIG_DATA=$(cat ${NET_MAP_CONFIG_PATH})
VPN_PUB_KEY=$(cat ${VPN_PUB_KEY_PATH})
NETWORK_CFG_ORIG=$(cat ${NETWORK_CFG_PATH})
DHCP_DNS_SEARCH=$(get_dhcp_dns_search "$(get_obj_prop "${NET_MAP_CONFIG_DATA}" '.network.dns.search')")
DHCP_DNS_SERVERS=$(get_dhcp_dns_server "$(get_obj_prop "${NET_MAP_CONFIG_DATA}" '.network.dns.servers')")
DHCP_CFG_ORIG=$(cat ${DHCP_CFG_PATH})
VPN_HOST_CFG_ORIG=$(cat ${VPN_HOST_CFG_PATH})

# Runtime variables
VM_BRIDGES=" "
DHCP_SUBNETS=""
VM_BRIDGE_CFG=""
VPN_SUBNETS=""
VM_ADAPTERS=""
VM_COLLECTION=""

if [ "${QEMU_LIST_DATA}" != "[]" ]; then
  for VM_DATA in $(echo "${QEMU_LIST_DATA}" | jq -c -r '.[]'); do
    VMID=$(get_obj_prop "${VM_DATA}" '.vmid')
    VM_ITEM=$(replace_variable_tpl "${VM_ITEM_TPL_DATA}" "VMID" "${VMID}")
    VM_ITEM=$(replace_variable_tpl "${VM_ITEM}" "TYPE" "qemu")
    VM_ITEM=$(replace_variable_tpl "${VM_ITEM}" "NAME_FIELD" "name")
    VM_ITEM=$(replace_variable_tpl "${VM_ITEM}" "NET_TPL" "${QEMU_NET_TPL_DATA}")
    VM_COLLECTION="${VM_COLLECTION}${VM_ITEM},"
  done
else
  echo "Qemu list is empty"
fi

if [ "${LXC_LIST_DATA}" != "[]" ]; then
  for VM_DATA in $(echo "${LXC_LIST_DATA}" | jq -c -r '.[]'); do
    VMID=$(get_obj_prop "${VM_DATA}" '.vmid')
    VM_ITEM=$(replace_variable_tpl "${VM_ITEM_TPL_DATA}" "VMID" "${VMID}")
    VM_ITEM=$(replace_variable_tpl "${VM_ITEM}" "TYPE" "lxc")
    VM_ITEM=$(replace_variable_tpl "${VM_ITEM}" "NAME_FIELD" "hostname")
    VM_ITEM=$(replace_variable_tpl "${VM_ITEM}" "NET_TPL" "${LXC_NET_TPL_DATA}")
    VM_COLLECTION="${VM_COLLECTION}${VM_ITEM},"
  done
else
  echo "LXC list is empty"
fi

VM_COLLECTION="[${VM_COLLECTION%?}]"

if [ "${VM_COLLECTION}" != "[]" ]; then
  for VM_ITEM in $(echo "${VM_COLLECTION}" | jq -c -s '.[] | sort_by(.vmid)' | jq -c -r '.[]'); do
    VMID=$(get_obj_prop "${VM_ITEM}" '.vmid')
    TYPE=$(get_obj_prop "${VM_ITEM}" '.type')
    NET_TPL=$(get_obj_prop "${VM_ITEM}" '.net_tpl')
    NAME_FIELD=$(get_obj_prop "${VM_ITEM}" '.name_field')
    echo "VMID '${VMID}' (${TYPE})"

    # Actual VM configuration
    VM_CONFIG_DATA=$(pvesh get /nodes/${NODE_NAME}/${TYPE}/${VMID}/config --output-format json)
    VM_NAME=$(get_obj_prop "${VM_CONFIG_DATA}" ".${NAME_FIELD}")

    ADAPTERS_DATA=$(get_obj_prop "${NET_MAP_CONFIG_DATA}" ".network.vms.vm${VMID}.adapters")

    if [ "${ADAPTERS_DATA}" != "null" ]; then
      for ADAPTER_DATA in $(echo "${ADAPTERS_DATA}" | jq -c -r '.[]'); do

        # Expected VM configuration
        ID=$(get_obj_prop "${ADAPTER_DATA}" '.id')
        ADAPTER_NAME=$(get_obj_prop "${ADAPTER_DATA}" '.name')
        BRIDGE_NAME=$(get_obj_prop "${ADAPTER_DATA}" '.bridge')
        SUBNET=$(get_obj_prop "${ADAPTER_DATA}" '.ipv4.subnet')
        NETMASK=$(get_obj_prop "${ADAPTER_DATA}" '.ipv4.netmask')
        GATEWAY=$(get_obj_prop "${ADAPTER_DATA}" '.ipv4.gateway')
        ADDRESS=$(get_obj_prop "${ADAPTER_DATA}" '.ipv4.address')
        MAC=$(get_obj_prop "${ADAPTER_DATA}" '.mac')
        ADDRESS_SUBNET="${ADDRESS}/${SUBNET#*/}"

        # Collect DHCP configuration
        DHCP_SUBNET="${DHCP_SUBNET_TPL_DATA}"
        DHCP_SUBNET=$(replace_variable_tpl "${DHCP_SUBNET}" "SUBNET" "${SUBNET%/*}")
        DHCP_SUBNET=$(replace_variable_tpl "${DHCP_SUBNET}" "NETMASK" "${NETMASK}")
        DHCP_SUBNET=$(replace_variable_tpl "${DHCP_SUBNET}" "GATEWAY" "${GATEWAY}")
        DHCP_SUBNET=$(replace_variable_tpl "${DHCP_SUBNET}" "DNS_SEARCH" "${DHCP_DNS_SEARCH}")
        DHCP_SUBNET=$(replace_variable_tpl "${DHCP_SUBNET}" "DNS_SERVERS" "${DHCP_DNS_SERVERS}")
        DHCP_SUBNET=$(replace_variable_tpl "${DHCP_SUBNET}" "VM_HOST" "${VM_NAME}")
        DHCP_SUBNET=$(replace_variable_tpl "${DHCP_SUBNET}" "MAC" "${MAC}")
        DHCP_SUBNET=$(replace_variable_tpl "${DHCP_SUBNET}" "ADDRESS" "${ADDRESS}")
        DHCP_SUBNETS="${DHCP_SUBNETS}${NL}${DHCP_SUBNET}"

        # Collect host network configuration
        VM_BRIDGES="${VM_BRIDGES}${BRIDGE_NAME} "
        VM_BRIDGE_DATA="${BRIDGE_TPL_DATA}"
        VM_BRIDGE_DATA=$(replace_variable_tpl "${VM_BRIDGE_DATA}" "BRIDGE_NAME" "${BRIDGE_NAME}")
        VM_BRIDGE_DATA=$(replace_variable_tpl "${VM_BRIDGE_DATA}" "GATEWAY" "${GATEWAY}")
        VM_BRIDGE_DATA=$(replace_variable_tpl "${VM_BRIDGE_DATA}" "NETMASK" "${NETMASK}")
        VM_BRIDGE_DATA=$(replace_variable_tpl "${VM_BRIDGE_DATA}" "COMMENTS" "${ADDRESS}")
        VM_BRIDGE_CFG="${VM_BRIDGE_CFG}${NL}${VM_BRIDGE_DATA}"

        # Collect vpn subnets
        VPN_SUBNETS="${VPN_SUBNETS}${NL}Subnet = ${SUBNET}"

        VM_NET_CFG_ORIG=$(get_obj_prop "${VM_CONFIG_DATA}" ".${ID}")
        VM_NET_CFG=$(replace_variable_tpl "${NET_TPL}" "MAC" "${MAC}")
        VM_NET_CFG=$(replace_variable_tpl "${VM_NET_CFG}" "BRIDGE_NAME" "${BRIDGE_NAME}")
        VM_NET_CFG=$(replace_variable_tpl "${VM_NET_CFG}" "ADAPTER_NAME" "${ADAPTER_NAME}")
        VM_NET_CFG=$(replace_variable_tpl "${VM_NET_CFG}" "GATEWAY" "${GATEWAY}")
        VM_NET_CFG=$(replace_variable_tpl "${VM_NET_CFG}" "ADDRESS_SUBNET" "${ADDRESS_SUBNET}")
        if [ "${VM_NET_CFG_ORIG}" != "${VM_NET_CFG}" ]; then
          VM_ADAPTER=$(replace_variable_tpl "${VM_ADAPTER_TPL_DATA}" "ID" "${ID}")
          VM_ADAPTER=$(replace_variable_tpl "${VM_ADAPTER}" "VMID" "${VMID}")
          VM_ADAPTER=$(replace_variable_tpl "${VM_ADAPTER}" "TYPE" "${TYPE}")
          VM_ADAPTER=$(replace_variable_tpl "${VM_ADAPTER}" "VM_NET_CFG" "${VM_NET_CFG}")
          VM_ADAPTERS="${VM_ADAPTERS}${VM_ADAPTER},"
        else
          echo "VM network adapter '${ID}' config was not changed"
        fi
      done
    fi
  done
else
  echo "Qemu list is empty"
fi

# Drop unused interfaces
for BRIDGE_NAME in $(ip -j addr show | jq -c -r .[].ifname | grep ^vmbr); do
  if [[ "${VM_BRIDGES}" != *"${BRIDGE_NAME}"* ]]; then
    echo "Drop insterface: ${BRIDGE_NAME}"
    sudo ifconfig ${BRIDGE_NAME} down
    sudo ip link delete ${BRIDGE_NAME}
  fi
done

# Build VPN host configuration
VPN_HOST_CFG=$(replace_variable_tpl "${VPN_HOST_TPL_DATA}" "VPN_WAN_IP" "${VPN_WAN_IP}")
VPN_HOST_CFG=$(replace_variable_tpl "${VPN_HOST_CFG}" "VPN_LAN_IP" "${VPN_LAN_IP}")
VPN_HOST_CFG=$(replace_variable_tpl "${VPN_HOST_CFG}" "VPN_PUB_KEY" "${VPN_PUB_KEY}")
VPN_HOST_CFG=$(replace_variable_tpl "${VPN_HOST_CFG}" "VPN_SUBNETS" "${VPN_SUBNETS}")

# Builder network configuration
NETWORK_CFG=$(replace_variable_tpl "${NETWORK_CFG_TPL_DATA}" "VM_BRIDGE_CFG" "${VM_BRIDGE_CFG}")

if [ "${NETWORK_CFG_ORIG}" != "${NETWORK_CFG}" ]; then
  echo "Change network configuration"
  echo "${NETWORK_CFG}" > ${NETWORK_CFG_PATH}
  sudo systemctl restart networking
else
  echo "Network configuration was not changed"
fi

# Build DHCP configuration
DHCP_CFG=$(replace_variable_tpl "${DHCP_CFG_TPL_DATA}" "SUBNETS" "${DHCP_SUBNETS}")
DHCP_CFG=$(replace_variable_tpl "${DHCP_CFG}" "DDNS_DOMAIN" "${DDNS_DOMAIN}")
DHCP_CFG=$(replace_variable_tpl "${DHCP_CFG}" "DDNS_ADDRESS" "${DDNS_ADDRESS}")
DHCP_CFG=$(replace_variable_tpl "${DHCP_CFG}" "DDNS_SECRET" "${DDNS_SECRET}")

if [ "${DHCP_CFG_ORIG}" != "${DHCP_CFG}" ]; then
  echo "Change DHCP configuration"
  echo "${DHCP_CFG}" > ${DHCP_CFG_PATH}
  DHCP_SERVER_CFG=$(replace_variable_tpl "${DHCP_SERVER_TPL_DATA}" "INTERFACES" "${VM_BRIDGES}")
  echo "${DHCP_SERVER_CFG}" > ${DHCP_SERVER_PATH}
  sudo systemctl restart isc-dhcp-server || true
else
  echo "DHCP configuration was not changed"
fi

if [ "${VPN_HOST_CFG_ORIG}" != "${VPN_HOST_CFG}" ]; then
  echo "Change VPN configuration"
  echo "${VPN_HOST_CFG}" > ${VPN_HOST_CFG_PATH}
  sudo systemctl restart cnet
else
  echo "VPN configuration was not changed"
fi

for VM_ADAPTER in $(echo "[${VM_ADAPTERS%?}]" | jq -c -r '.[]'); do
  ID=$(get_obj_prop "${VM_ADAPTER}" '.id')
  VMID=$(get_obj_prop "${VM_ADAPTER}" '.vmid')
  TYPE=$(get_obj_prop "${VM_ADAPTER}" '.type')
  DATA=$(get_obj_prop "${VM_ADAPTER}" '.data')
  echo "Change VM ${ID} (${TYPE}) network adapter configuration"
  sudo pvesh set /nodes/${NODE_NAME}/${TYPE}/${VMID}/config --${ID} "${DATA}"
done