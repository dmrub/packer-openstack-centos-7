#!/bin/bash

THIS_DIR=$( (cd "$(dirname -- "$BASH_SOURCE")" && pwd -P) )

set -eux

cd "$THIS_DIR"
rm -rf output-qemu
PACKER_LOG=1 packer build --only=qemu centos7.json
