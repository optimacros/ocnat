#!/bin/bash

set -e

SCRIPT_PATH="$( cd "$(dirname "$1")" ; pwd -P )"
ROUTES_PATH=${SCRIPT_PATH}/routes.json

DEFAULT_ID="om-nat-M4RdjRw2ZhT"
CUSTOM_ID=$(jq -r '.id' ${ROUTES_PATH})

if [ "${CUSTOM_ID}" = "null" ]
then
    ID="${DEFAULT_ID}"
else
    ID="${CUSTOM_ID}"
fi

echo "Drop OM NAT: ${ID}"

iptables-save | grep -v "${ID}" | iptables-restore