#!/bin/bash

# Define drive and mount points
DRIVE="/dev/nvme0n1"
EFI_PART="${DRIVE}p1"
ROOT_PART="${DRIVE}p2"

# Clear all partition data and GPT/MBR structures
sgdisk --zap-all ${DRIVE}
sgdisk --clear ${DRIVE}

# Set optimal alignment for NVMe performance
sgdisk --set-alignment=8 ${DRIVE}

# Create partitions
sgdisk --new=1:0:+2G \
       --typecode=1:ef00 \
       --change-name=1:"EFI" \
       --new=2:0:0 \
       --typecode=2:8300 \
       --change-name=2:"ROOT" \
       --attributes=2:set:2 \
       ${DRIVE}
       
# Verify partitions
sgdisk --verify ${DRIVE}
partprobe ${DRIVE}

# Format partitions
mkfs.fat -F32 -n EFI ${EFI_PART}

# Format BTRFS with optimal settings for NVMe
mkfs.btrfs -f \
    -L ROOT \
    -n 32k \
    -m dup \
    ${ROOT_PART}

# Mount ROOT partition
mount ${ROOT_PART} /mnt

# Create BTRFS subvolumes
cd /mnt
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create @var
btrfs subvolume create @log
btrfs subvolume create @pkg
btrfs subvolume create @.snapshots

# Unmount and remount with subvolumes
cd /
umount /mnt

# Mount subvolumes with optimal options
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@ ${ROOT_PART} /mnt
mkdir -p /mnt/{home,var,var/log,var/cache/pacman/pkg,.snapshots,boot/efi}
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@home ${ROOT_PART} /mnt/home
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@var ${ROOT_PART} /mnt/var
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@log ${ROOT_PART} /mnt/var/log
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@pkg ${ROOT_PART} /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@.snapshots ${ROOT_PART} /mnt/.snapshots

# Mount EFI partition
mount ${EFI_PART} /mnt/boot/efi

# Verify mounts
df -Th
btrfs subvolume list /mnt

# Install base system and AMD-specific packages
pacstrap /mnt base base-devel linux linux-headers linux-firmware btrfs-progs \
    amd-ucode \
    networkmanager \
    grub efibootmgr \
    neovim vim htop glances git \
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
    #lib32-mesa \
    #lib32-vulkan-radeon \
    gamemode \
    corectrl

# Allow kdeconect
#    sudo ufw enable
#    sudo ufw allow 1714:1764/udp
#    sudo ufw allow 1714:1764/tcp
#    sudo ufw default deny incoming
#    sudo ufw default allow outgoing
#    sudo ufw allow ssh
#    sudo ufw allow http
#    sudo ufw allow https
#    sudo ufw logging on
#    sudo ufw reload

echo "Installation completed!"
echo "Please remove installation media and reboot."
