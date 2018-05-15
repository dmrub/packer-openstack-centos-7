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

#
# cloud-init config files : specify cloud-init data for your guest
# xenial, use ens3 instead of eth0
cat <<EOF >meta-data
instance-id: iid-${GUEST_NAME};
hostname: ${GUEST_NAME}
local-hostname: ${GUEST_NAME}
EOF
#
cat <<EOF >user-data
#cloud-config
password: centos
chpasswd: { expire: False }
ssh_pwauth: True
# upgrade packages on startup
package_upgrade: false
#run 'apt-get upgrade' or yum equivalent on first boot
apt_upgrade: false
#manage_etc_hosts: localhost
manage_etc_hosts: true
fqdn: ${GUEST_NAME}.${DOMAIN}
#datasource_list:
#  - ConfigDrive
# install additional packages
#packages:
#  - mc
#  - htop
#  - language-pack-fr
# run commands
runcmd:
# install htop on centos/fedora
#  - [ sh, -c, "curl http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-2.noarch.rpm -o /tmp/epel-release.rpm" ]
#  - [ sh, -c, "yum install -y /tmp/epel-release.rpm" ]
#  - [ sh, -c, "yum install -y htop" ]
#ssh_authorized_keys:
#  - ssh-rsa AAAAB3NzaC1yc2QwAAADAQABAAa3BAQC0g+ZTxC7weoIJLUafOgrm+h...
EOF

if [[ ! -f "$IMG_PATH" || ! -r "$IMG_PATH" ]]; then
  echo >&2 "Image $IMG_PATH is not a file or is not readable"
  exit 1
fi

echo "Using existing image ${IMG_PATH}..."

cleanup() {
  echo "Cleanup..."
  cd "$THIS_DIR"
  rm -f configuration.iso meta-data user-data
}

trap cleanup INT EXIT

# check if pool exists, otherwise create it
if [[ "$(virsh pool-list | grep ${POOL_NAME} -c)" -ne "1" ]]; then
	echo "Creating pool ${POOL_NAME}..."
	virsh pool-define-as --name "${POOL_NAME}" --type dir --target ${POOL_PATH}
	virsh pool-autostart "${POOL_NAME}"
	virsh pool-build "${POOL_NAME}"
	virsh pool-start "${POOL_NAME}"
fi

# write the two cloud-init files into an ISO
echo "Preparing ISO file required by cloud-init..."
genisoimage -input-charset utf8 -output configuration.iso -volid cidata -joliet -rock user-data meta-data
#xorriso -in_charset utf8 -outdev configuration.iso -volid cidata -joliet on -rockridge on -map user-data user-data -map meta-data meta-data

# keep a backup of the files for future reference
if [[ "${BACKUP_ISO_FILE}" == "yes" ]]; then
	cp user-data "${GUEST_NAME}.user-data"
	cp meta-data "${GUEST_NAME}.meta-data"
	chmod 666 "${GUEST_NAME}.user-data" "${GUEST_NAME}.meta-data"
fi

# copy ISO into libvirt's directory
(
	set -xe;
	cp configuration.iso "${POOL_PATH}/${GUEST_NAME}.configuration.iso"
	virsh pool-refresh "${POOL_NAME}"
)

# copy image to libvirt's pool
IMG_NAME=$(basename "$IMG_PATH")
if [[ ! -f "${POOL_PATH}/${IMG_NAME}" ]]; then
	cp "${IMG_PATH}" "${POOL_PATH}"
	virsh pool-refresh "${POOL_NAME}"
fi

# clone root image
(
  set -xe;
  virsh vol-clone --pool "${POOL_NAME}" "${IMG_NAME}" "${GUEST_NAME}.root.img";
  virsh vol-resize --pool "${POOL_NAME}" "${GUEST_NAME}.root.img" "${VROOTDISKSIZE}";
)

# convert image format
if [[ "${CONVERT}" == "yes" ]]; then
  echo "Converting image to format ${FORMAT}..."
  (
    set -xe;
    qemu-img convert -O "${FORMAT}" "${POOL_PATH}/${GUEST_NAME}.root.img" "${POOL_PATH}/${GUEST_NAME}.root.img.${FORMAT}"
    rm "${POOL_PATH}/${GUEST_NAME}.root.img"
    mv "${POOL_PATH}/${GUEST_NAME}.root.img.${FORMAT}" "${POOL_PATH}/${GUEST_NAME}.root.img"
  )
fi

echo "Creating guest ${GUEST_NAME}..."

virsh net-start default || true

echo "Creating guest ${GUEST_NAME}..."
virsh destroy "${GUEST_NAME}" || true
virsh undefine "${GUEST_NAME}" || true
virt-install \
	--virt-type kvm \
	--name "${GUEST_NAME}" \
	--ram "${RAM}" \
	--vcpus "${VCPUS}" \
	--noautoconsole \
	--autostart \
	--memballoon virtio \
	--network "${NETWORK}" \
	--disk "vol=${POOL_NAME}/${GUEST_NAME}.root.img,format=$FORMAT,bus=virtio" \
	--disk "vol=${POOL_NAME}/${GUEST_NAME}.configuration.iso,bus=virtio" \
	--graphics vnc,listen=0.0.0.0 \
	--os-type=linux --os-variant=centos7.0 \
	--import

# display result
echo
echo "List of running VMs :"
echo
virsh list

# stuff to remember
echo
echo "************************"
echo "Useful stuff to remember"
echo "************************"
echo
echo "To login to vm guest:"
echo " sudo virsh console ${GUEST_NAME}"
echo "To exit from virsh console:"
echo " Ctrl+[ or Ctrl+5"
echo "To connect via VNC with vm guest:"
echo " vncviewer localhost"
echo "Default user for cloud image is :"
echo " ${IMG_USER}"
echo
echo "To edit guest vm config:"
echo " sudo virsh edit ${GUEST_NAME}"
echo
echo "To create a volume:"
echo " virsh vol-create-as ${POOL_NAME} ${GUEST_NAME}.vol1.img 20G --format ${FORMAT}"
echo "To attach a volume to an existing guest:"
echo " virsh attach-disk ${GUEST_NAME} --source ${POOL_PATH}/${GUEST_NAME}.vol1.img --target vdc --driver qemu --subdriver ${FORMAT} --persistent"
echo "To prepare the newly attached volume on guest:"
echo " sgdisk -n 1 -g /dev/vdc && && mkfs -t ext4 /dev/vdc1 && sgdisk -c 1:'vol1' -g /dev/vdc && sgdisk -p /dev/vdc"
echo " mkdir /mnt/vol1"
echo " echo '/dev/vdc1 /mnt/vol1 ext4 defaults,relatime 0 0' >> /etc/fstab"
echo
echo "To shutdown a guest vm:"
echo "  sudo virsh shutdown ${GUEST_NAME}"
echo
