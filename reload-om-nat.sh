#!/bin/bash

# version: 1.0.1

set -e

ROUTES_PATH=$1
NODE_NAME=$2
CUSTOM_CONTEXT_ID=$3

echo "NODE_NAME: ${NODE_NAME}"

DEFAULT_CONTEXT_ID="M4RdjRw2ZhT"

if [ "${CUSTOM_CONTEXT_ID}" = "null" ]; then
  CONTEXT_ID="${DEFAULT_CONTEXT_ID}"
else
  CONTEXT_ID="${CUSTOM_CONTEXT_ID}"
fi

echo "CONTEXT_ID: ${CONTEXT_ID}"

CURRENT_RULES=$(iptables-save | { grep -oP "${CONTEXT_ID}_[a-z0-9]{40}" || :; })

get_obj_prop() {
  local DATA=$1
  local KEY=$2
  echo ${DATA} | base64 --decode | jq -r "${KEY}"
}

drop_rule() {
  local RULE_ID=$1
  echo "Drop rule: ${RULE_ID}"
  iptables-save | grep -v "${RULE_ID}" | iptables-restore
}

drop_from_current_rule() {
  local RULE_ID=$1
  CURRENT_RULES=$(echo "${CURRENT_RULES}" | { grep -v "${RULE_ID}" || :; })
}

has_rule() {
  local RULE_ID=$1
  echo $(iptables-save | { grep "${RULE_ID}" || :; })
}

get_rule_hash() {
  local RULE_DATA=$1
  echo -n "${RULE_DATA}" | sha1sum | awk '{print $1}'
}

add_rule() {
  local RULE_DATA=$1
  local RULE_HASH=$(get_rule_hash "${RULE_DATA}")
  local RULE_ID="${CONTEXT_ID}_${RULE_HASH}"
  local HAS_RULE=$(has_rule "${RULE_ID}")
  if [ "${HAS_RULE}" == "" ]; then
    echo "Append rule (${RULE_ID}): ${RULE_DATA}"
    iptables ${RULE_DATA} -m comment --comment "${RULE_ID}"
  else
    echo "Ignore rule (${RULE_ID}): ${RULE_DATA}"
    drop_from_current_rule "${RULE_ID}"
  fi
}

ROUTES=$(jq -r ".nodes.${NODE_NAME}.routes" ${ROUTES_PATH})

if [ "${ROUTES}" != "null" ]; then
  for row in $(echo "${ROUTES}" | jq -r '.[] | @base64'); do
    NAME=$(get_obj_prop ${row} '.name')
    echo "Add rules to ${NAME}"
    FROM_ADDRESS=$(get_obj_prop ${row} '.from.address')
    TO_ADDRESS=$(get_obj_prop ${row} '.to.address')
    TO_INTERFACE=$(get_obj_prop ${row} '.to.interface')
    PREROUTING=$(get_obj_prop ${row} '.prerouting')
    POSTROUTING_DEST=""
    if [ "${TO_ADDRESS}" = "null" ]; then
      POSTROUTING_DEST="MASQUERADE"
    else
      POSTROUTING_DEST="SNAT --to-source ${TO_ADDRESS}"
    fi
    POSTROUTING_RULE="-t nat -A POSTROUTING -s ${FROM_ADDRESS} -o ${TO_INTERFACE} -j ${POSTROUTING_DEST}"
    add_rule "${POSTROUTING_RULE}"
    if [ "${PREROUTING}" = true ]; then
      PREROUTING_RULE="-t nat -A PREROUTING -p tcp -d ${TO_ADDRESS} -j DNAT --to-destination ${FROM_ADDRESS%/*}"
      add_rule "${PREROUTING_RULE}"
    fi
  done
else
  echo "Routes not found"
fi

add_rule "-t raw -I PREROUTING -i fwbr+ -j CT --zone 1"

if [ "${CURRENT_RULES}" != "" ]; then
  while IFS= read -r LINE; do
    drop_rule "${LINE}"
  done <<<"${CURRENT_RULES}"
fi
