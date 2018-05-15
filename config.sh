# vm prefs : specify vm preferences for your guest
BACKUP_ISO_FILES=no # yes or no
GUEST_NAME=centos7
DOMAIN=vm
VROOTDISKSIZE=10G
VCPUS=2
RAM=2048
#NETWORK="bridge=virbr0,model=virtio"
NETWORK=network=default
# guest image format: qcow2 or raw
FORMAT=qcow2
IMG_USER="centos"
IMG_PATH="output-qemu/packer-centos-7-x86_64.qcow2"
