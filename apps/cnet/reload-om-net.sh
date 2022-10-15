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



# load actual

QEMU_LIST_OUTPUT=$(pvesh get /nodes/c001-n020/qemu --output-format json)

QEMU_LIST=$(echo ${QEMU_LIST_OUTPUT} | jq -r ".routes.post")

if [ "${QEMU_LIST}" != "null" ]; then
  for row in $(echo "${QEMU_LIST}" | jq -r '.[] | @base64'); do
    VMID=$(get_obj_prop ${row} '.vmid')
    echo "VMID '${VMID}'"
    # get current network adapter
  done
else
  echo "Qemu list is empty"
fi