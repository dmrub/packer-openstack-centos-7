#!/bin/bash

set -ex

yum install -y acpid cloud-init cloud-utils-growpart
systemctl enable acpid

echo "NOZEROCONF=yes" >> /etc/sysconfig/network

yum clean all

# $1 - filename
# $2 - variable prefix, CFG_ is used by default
read-config-file() {
    local configfile=$1
    local prefix=$2
    if [[ ! -f "$configfile" ]]; then
        echo >&2 "[read-config-file] '$configfile' is not a file";
        return 1;
    fi
    if [[ -z "$prefix" ]]; then prefix=CFG_; fi

    local lhs rhs cfg

    if ! cfg=$(tr -d '\r' < "$configfile"); then
        return 1
    fi

    while IFS='=' read -rs lhs rhs;
    do
        if [[ "$lhs" =~ ^[A-Za-z_][A-Za-z_0-9]*$ && -n "$lhs" ]]; then
            rhs="${rhs%%\#*}"               # Del in line right comments
            rhs="${rhs%"${rhs##*[^ ]}"}"    # Del trailing spaces
            rhs="${rhs%\"*}"                # Del opening string quotes
            rhs="${rhs#\"*}"                # Del closing string quotes
            declare -g "${prefix}${lhs}=${rhs}"
        fi
    done <<<"$cfg"
}

read-config-file /etc/default/grub
GRUB_CMDLINE_LINUX=""
for param in $CFG_GRUB_CMDLINE_LINUX; do
    case "$param" in
        rhgb|quiet) ;;
        *) GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX} ${param}"
    esac
done
GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX} console=tty0 console=ttyS0,115200n8"

sed -i -e 's/GRUB_CMDLINE_LINUX=.*$/GRUB_CMDLINE_LINUX="'"${GRUB_CMDLINE_LINUX}"'"/g' /etc/default/grub

grub2-mkconfig -o /boot/grub2/grub.cfg
