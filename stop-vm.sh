#!/bin/bash

THIS_DIR=$( (cd "$(dirname -- "$BASH_SOURCE")" && pwd -P))

set -e

source "$THIS_DIR/config.sh"

cd "$THIS_DIR"

# check if the script is run as root user
if [[ $EUID != 0 ]]; then
	echo "This script must be run as root!"
	exit 1
fi

# kvm pool
POOL_NAME=${POOL_NAME:-default}

if [[ -z "${POOL_PATH}" ]]; then
	POOL_PATH=$(virsh pool-dumpxml "$POOL_NAME" | xmllint --xpath '//target/path/text()' - | head -n 1)
fi

virsh shutdown "${GUEST_NAME}" || true
virsh vol-delete --pool "$POOL_NAME" "${GUEST_NAME}.root.img" || true
