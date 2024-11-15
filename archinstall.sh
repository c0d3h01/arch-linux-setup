#!/bin/bash

set -e
set -u
set -o pipefail

# Variables
DRIVE="/dev/nvme0n1"
EFI_PART="${DRIVE}p1"
ROOT_PART="${DRIVE}p2"
MOUNT_POINT="/mnt"

# Functions
log() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

error() {
    echo -e "\e[31m[ERROR]\e[0m $1" >&2
    exit 1
}

verify_command() {
    if ! command -v "$1" > /dev/null 2>&1; then
        error "Required command '$1' not found. Please install it and try again."
    fi
}

for cmd in sgdisk mkfs.fat mkfs.btrfs mount umount partprobe btrfs pacstrap; do
    verify_command $cmd
done

log "Setting up partitions on ${DRIVE}..."
sgdisk --zap-all ${DRIVE}
sgdisk --clear ${DRIVE}
sgdisk --set-alignment=8 ${DRIVE}
sgdisk --new=1:0:+2G --typecode=1:ef00 --change-name=1:"EFI" ${DRIVE}
sgdisk --new=2:0:0   --typecode=2:8300 --change-name=2:"ROOT" ${DRIVE}
sgdisk --verify ${DRIVE}
partprobe ${DRIVE}

log "Formatting partitions..."
mkfs.fat -F32 -n EFI ${EFI_PART}
mkfs.btrfs -f -L ROOT -n 32k -m dup ${ROOT_PART}

log "Creating and mounting BTRFS subvolumes..."
mount ${ROOT_PART} ${MOUNT_POINT}
btrfs subvolume create ${MOUNT_POINT}/@
btrfs subvolume create ${MOUNT_POINT}/@home
btrfs subvolume create ${MOUNT_POINT}/@var
btrfs subvolume create ${MOUNT_POINT}/@log
btrfs subvolume create ${MOUNT_POINT}/@pkg
btrfs subvolume create ${MOUNT_POINT}/@.snapshots
umount ${MOUNT_POINT}

log "Mounting subvolumes with optimal options..."
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@ ${ROOT_PART} ${MOUNT_POINT}
mkdir -p ${MOUNT_POINT}/{home,var,var/log,var/cache/pacman/pkg,.snapshots,boot/efi}
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@home ${ROOT_PART} ${MOUNT_POINT}/home
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@var ${ROOT_PART} ${MOUNT_POINT}/var
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@log ${ROOT_PART} ${MOUNT_POINT}/var/log
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@pkg ${ROOT_PART} ${MOUNT_POINT}/var/cache/pacman/pkg
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@.snapshots ${ROOT_PART} ${MOUNT_POINT}/.snapshots
mount ${EFI_PART} ${MOUNT_POINT}/boot/efi

log "Verifying mounts..."
df -Th
btrfs subvolume list ${MOUNT_POINT}

# Installing Base System
log "Installing base system and essential packages..."
pacstrap ${MOUNT_POINT} base base-devel linux linux-headers linux-firmware btrfs-progs \
    amd-ucode \
    networkmanager \
    grub efibootmgr \
    neovim htop glances git \
    gcc gdb cmake make \
    python python-pip \
    nodejs npm \
    docker \
    git-lfs \
    btrfs-progs \
    zram-generator \
    power-profiles-daemon \
    thermald \
    xf86-video-amdgpu \
    vulkan-radeon \
    libva-mesa-driver \
    mesa-vdpau \
    mesa \
    bluez bluez-utils \
    gamemode \
    corectrl

log "Generating fstab..."
genfstab -U ${MOUNT_POINT} >> ${MOUNT_POINT}/etc/fstab

log "Entering chroot environment..."
arch-chroot ${MOUNT_POINT} /bin/bash <<EOF
set -e

log "Configuring system..."
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

log "Setting up locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

log "Setting up hostname and hosts..."
echo "archlinux" > /etc/hostname
cat <<EOL > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlinux.localdomain archlinux
EOL

log "Configuring bootloader..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

log "Enabling essential services..."
systemctl enable NetworkManager.service
systemctl enable bluetooth.service
systemctl enable zram-generator.service
EOF

log "Setup complete! You can now reboot into your new system."

