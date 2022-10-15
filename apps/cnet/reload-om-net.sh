#!/bin/bash

# version: 1.0.1

set -e

ENV_PATH=$1

export $(grep -v '^#' "${ENV_PATH}" | xargs)

get_obj_prop() {
  local DATA=$1
  local KEY=$2
  echo ${DATA} | base64 --decode | jq -r "${KEY}"
}

replace_variable_tpl() {
  local DATA=$1
  local SEARCH=$2
  local REPLACE=$3
  echo "${DATA}" | sed "s/{${SEARCH}}/${REPLACE}/"
}

get_dhcp_dns_search() {
  local DATA=$1
  local RESULT=""
  for ROW in $(echo "${DATA}" | jq -r '.[] | @base64'); do
    RESULT="${RESULT}\"${ROW}\", "
  done
  echo ${RESULT%??}
}

get_dhcp_dns_server() {
  local DATA=$1
  local RESULT=""
  for ROW in $(echo "${DATA}" | jq -r '.[] | @base64'); do
    RESULT="${RESULT}${ROW}, "
  done
  echo ${RESULT%??}
}

WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "${WORK_DIR}"' EXIT

cd ${WORK_DIR}

# CURRENT_INTERFACES=$(ip -j addr show | jq -r .[].ifname | grep ^vmbr)

# Template data variables
VM_NET_TPL_DATA="virtio={MAC},bridge={BRIDGE_NAME},firewall=1"
DHCP_BLOCK_TPL_DATA=$(cat ${DHCP_BLOCK_TPL_PATH})
BRIDGE_TPL_DATA=$(cat ${BRIDGE_TPL_PATH})
VPN_HOST_TPL_DATA=$(cat ${VPN_HOST_TPL_PATH})
NETWORK_CFG_TPL_DATA=$(cat ${NETWORK_CFG_TPL_PATH})

# Static data variables
DHCP_DNS_SEARCH=$(get_dhcp_dns_search "$(get_obj_prop "${NET_MAP_CONFIG_DATA}" '.network.dns.search')")
DHCP_DNS_SERVERS=$(get_dhcp_dns_server "$(get_obj_prop "${NET_MAP_CONFIG_DATA}" '.network.dns.servers')")
QEMU_LIST_DATA=$(pvesh get /nodes/${NODE_NAME}/qemu --output-format json)
LXC_LIST_DATA=$(pvesh get /nodes/${NODE_NAME}/lxc --output-format json)
NET_MAP_CONFIG_DATA=$(cat ${NET_MAP_CONFIG_PATH})
VPN_PUB_KEY=$(cat ${VPN_PUB_KEY_PATH})

# Runtime variables
VM_BRIDGES=""
DHCP_INTERFACES=""
DHCP_CFG=""
VM_BRIDGE_CFG=""
VPN_SUBNETS=""

if [ "${QEMU_LIST_DATA}" != "[]" ]; then
  for QEMU_DATA in $(echo "${QEMU_LIST_DATA}" | jq -r '.[] | @base64'); do
    VMID=$(get_obj_prop "${QEMU_DATA}" '.vmid')
    echo "VMID '${VMID}'"

    # Actual VM configuration
    VM_CONFIG_DATA=$(pvesh get /nodes/${NODE_NAME}/qemu/${VMID}/config)
    VM_NAME=$(get_obj_prop "${VM_CONFIG_DATA}" '.name')

    ADAPTERS_DATA=$(get_obj_prop "${NET_MAP_CONFIG_DATA}" '.network.vms.vm${VMID}.adapters')
    for ADAPTER_DATA in $(echo "${ADAPTERS_DATA}" | jq -r '.[] | @base64'); do

      # Expected VM configuration
      BRIDGE_NAME=$(get_obj_prop "${ADAPTER_DATA}" '.bridge')
      SUBNET=$(get_obj_prop "${ADAPTER_DATA}" '.subnet')
      MASK=$(get_obj_prop "${ADAPTER_DATA}" '.mask')
      GATEWAY=$(get_obj_prop "${ADAPTER_DATA}" '.gateway')
      ADDRESS=$(get_obj_prop "${ADAPTER_DATA}" '.address')
      MAC=$(get_obj_prop "${ADAPTER_DATA}" '.mac')

      # Collect DHCP configuration
      DHCP_CFG="${DHCP_CFG} ${BRIDGE_NAME}"
      DHCP_BLOCK_DATA="${DHCP_BLOCK_TPL_DATA}"
      DHCP_BLOCK_DATA=$(replace_variable_tpl "${DHCP_BLOCK_DATA}" "SUBNET" "${SUBNET%/*}")
      DHCP_BLOCK_DATA=$(replace_variable_tpl "${DHCP_BLOCK_DATA}" "MASK" "${MASK}")
      DHCP_BLOCK_DATA=$(replace_variable_tpl "${DHCP_BLOCK_DATA}" "GATEWAY" "${GATEWAY}")
      DHCP_BLOCK_DATA=$(replace_variable_tpl "${DHCP_BLOCK_DATA}" "DNS_SEARCH" "${DHCP_DNS_SERVERS}")
      DHCP_BLOCK_DATA=$(replace_variable_tpl "${DHCP_BLOCK_DATA}" "DNS_SERVERS" "${DHCP_DNS_SEARCH}")
      DHCP_BLOCK_DATA=$(replace_variable_tpl "${DHCP_BLOCK_DATA}" "VM_HOST" "${VM_NAME}")
      DHCP_BLOCK_DATA=$(replace_variable_tpl "${DHCP_BLOCK_DATA}" "MAC" "${MAC}")
      DHCP_BLOCK_DATA=$(replace_variable_tpl "${DHCP_BLOCK_DATA}" "ADDRESS" "${ADDRESS}")
      DHCP_CFG="${DHCP_CFG}\n${DHCP_BLOCK_DATA}"

      # Collect host network configuration
      VM_BRIDGES="${VM_BRIDGES} ${BRIDGE_NAME}"
      VM_BRIDGE_DATA="${BRIDGE_TPL_DATA}"
      VM_BRIDGE_DATA=$(replace_variable_tpl "${VM_BRIDGE_DATA}" "BRIDGE_NAME" "${BRIDGE_NAME}")
      VM_BRIDGE_DATA=$(replace_variable_tpl "${VM_BRIDGE_DATA}" "GATEWAY" "${GATEWAY}")
      VM_BRIDGE_DATA=$(replace_variable_tpl "${VM_BRIDGE_DATA}" "MASK" "${MASK}")
      VM_BRIDGE_DATA=$(replace_variable_tpl "${VM_BRIDGE_DATA}" "COMMENTS" "${ADDRESS}")
      VM_BRIDGE_CFG="${VM_BRIDGE_CFG}\n${VM_BRIDGE_DATA}"

      # Collect vpn subnets
      VPN_SUBNETS="${VPN_SUBNETS}\nSubnet = ${SUBNET}"
    done
  done
else
  echo "Qemu list is empty"
fi

# Build VPN host configuration
VPN_HOST_CFG=$(replace_variable_tpl "${VPN_HOST_TPL_DATA}" "VPN_WAN_IP" "${VPN_WAN_IP}")
VPN_HOST_CFG=$(replace_variable_tpl "${VPN_HOST_CFG}" "VPN_LAN_IP" "${VPN_LAN_IP}")
VPN_HOST_CFG=$(replace_variable_tpl "${VPN_HOST_CFG}" "VPN_PUB_KEY" "${VPN_PUB_KEY}")
VPN_HOST_CFG=$(replace_variable_tpl "${VPN_HOST_CFG}" "VPN_SUBNETS" "${VPN_SUBNETS}")

# Builder network configuration
NETWORK_CFG=$(replace_variable_tpl "${NETWORK_CFG_TPL_DATA}" "VM_BRIDGE_CFG" "${VM_BRIDGE_CFG}")

echo "DHCP_CFG:\n${DHCP_CFG}\n"
echo "======\n"
echo "NETWORK_CFG:\n${NETWORK_CFG}\n"
echo "======\n"
echo "VPN_HOST_CFG:\n${VPN_HOST_CFG}\n"

# Compare NETWORK_CFG with file NETWORK_CFG_PATH data and replace if not same then restart networking
# Compare DHCP_CFG with original file DHCP_CFG_PATH data and replace if not same then restart service

# if new config same previous then exit

# apply new file config
# drop not persistent vmbrX interfaces
# restart networking