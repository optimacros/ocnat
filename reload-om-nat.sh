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

bash ${SCRIPT_PATH}/drop-om-nat.sh

get_obj_prop() {
   local data=$1
   local key=$2
   echo ${data} | base64 --decode | jq -r ${key}
}

ROUTES=$(jq -r '.routes' ${ROUTES_PATH})

for row in $(echo "${ROUTES}" | jq -r '.[] | @base64'); do
    NAME=$(get_obj_prop ${row} '.name')
    echo "Add rules to ${NAME}"
    FROM_ADDRESS=$(get_obj_prop ${row} '.from.address')
    TO_ADDRESS=$(get_obj_prop ${row} '.to.address')
    TO_INTERFACE=$(get_obj_prop ${row} '.to.interface')
    PREROUTING=$(get_obj_prop ${row} '.prerouting')
    POSTROUTING_DEST=""
    if [ "${TO_ADDRESS}" = "null" ]
    then
        POSTROUTING_DEST="MASQUERADE"
    else
        POSTROUTING_DEST="SNAT --to-source ${TO_ADDRESS}"
    fi
    POSTROUTING_RULE="-t nat -A POSTROUTING -s ${FROM_ADDRESS} -o ${TO_INTERFACE} -m comment --comment "${ID}" -j ${POSTROUTING_DEST}"
    echo "Postrouting rule: iptables ${POSTROUTING_RULE}"
    iptables ${POSTROUTING_RULE}
    if [ "${PREROUTING}" = true ] ; then
        PREROUTING_RULE="-t nat -A PREROUTING -p tcp -d ${TO_ADDRESS} -m comment --comment "${ID}" -j DNAT --to-destination ${FROM_ADDRESS%/*}"
        echo "Prerouting rule: iptables ${PREROUTING_RULE}"
        iptables ${PREROUTING_RULE}
    fi
done

iptables -t raw -I PREROUTING -i fwbr+  -m comment --comment "${ID}" -j CT --zone 1