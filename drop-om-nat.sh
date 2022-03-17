#!/bin/bash

# version: 1.0.1

set -e

ROUTES_PATH=$1
CUSTOM_CONTEXT_ID=$2

DEFAULT_CONTEXT_ID="M4RdjRw2ZhT"

if [ "${CUSTOM_CONTEXT_ID}" = "null" ]; then
  CONTEXT_ID="${DEFAULT_CONTEXT_ID}"
else
  CONTEXT_ID="${CUSTOM_CONTEXT_ID}"
fi

echo "CONTEXT_ID: ${CONTEXT_ID}"

iptables-save | grep -v "${CONTEXT_ID}" | iptables-restore