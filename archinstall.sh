#!/bin/bash
set -e  # Exit on error

# Script configuration
USERSETUP="./usrsetup.sh"
CHROOTSETUP="./chrootsetup.sh"
DRIVE="/dev/nvme0n1"
EFI_PART="${DRIVE}p1"
ROOT_PART="${DRIVE}p2"

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" >&2
   exit 1
fi

# Check if scripts exist
if [ ! -f "$USERSETUP" ] || [ ! -f "$CHROOTSETUP" ]; then
    echo "Setup scripts not found!" >&2
    exit 1
fi

# Function to handle errors
error_handler() {
    echo "An error occurred on line $1"
    exit 1
}
trap 'error_handler ${LINENO}' ERR

echo "Starting Arch Linux installation..."

echo "Preparing disk partitions..."
# Clear all partition data and GPT/MBR structures
sgdisk --zap-all ${DRIVE}
sgdisk --clear ${DRIVE}
sgdisk --set-alignment=8 ${DRIVE}

# Create partitions
echo "Creating partitions..."
sgdisk --new=1:0:+2G \
       --typecode=1:ef00 \
       --change-name=1:"EFI" \
       --new=2:0:0 \
       --typecode=2:8300 \
       --change-name=2:"ROOT" \
       --attributes=2:set:2 \
       ${DRIVE}

# Verify partitions
echo "Verifying partitions..."
sgdisk --verify ${DRIVE}
partprobe ${DRIVE}

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 -n EFI ${EFI_PART}
mkfs.btrfs -f \
    -L ROOT \
    -n 32k \
    -m dup \
    ${ROOT_PART}

echo "Setting up BTRFS subvolumes..."
# Mount ROOT partition
mount ${ROOT_PART} /mnt

# Create BTRFS subvolumes
pushd /mnt
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create @var
btrfs subvolume create @log
btrfs subvolume create @pkg
btrfs subvolume create @.snapshots
popd

# Unmount and remount with subvolumes
umount /mnt

echo "Mounting subvolumes..."
# Mount options
MOUNT_OPTS="noatime,compress=zstd:1,space_cache=v2,commit=120"

# Mount subvolumes
mount -o ${MOUNT_OPTS},subvol=@ ${ROOT_PART} /mnt

# Create mount points
mkdir -p /mnt/{home,var,var/log,var/cache/pacman/pkg,.snapshots,boot/efi}

# Mount other subvolumes
mount -o ${MOUNT_OPTS},subvol=@home ${ROOT_PART} /mnt/home
mount -o ${MOUNT_OPTS},subvol=@var ${ROOT_PART} /mnt/var
mount -o ${MOUNT_OPTS},subvol=@log ${ROOT_PART} /mnt/var/log
mount -o ${MOUNT_OPTS},subvol=@pkg ${ROOT_PART} /mnt/var/cache/pacman/pkg
mount -o ${MOUNT_OPTS},subvol=@.snapshots ${ROOT_PART} /mnt/.snapshots

# Mount EFI partition
mount ${EFI_PART} /mnt/boot/efi

echo "Verifying mount points..."
df -Th
btrfs subvolume list /mnt

echo "Installing base system..."
# Base packages installation
pacstrap /mnt \
    base base-devel \
    linux linux-headers linux-firmware \
    btrfs-progs \
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

# Install base system and AMD-specific packages
    pacstrap /mnt \
        base base-devel \
        linux linux-headers linux-firmware \
        btrfs-progs \
        # AMD CPU & GPU
        amd-ucode \
        xf86-video-amdgpu \
        vulkan-radeon \
        libva-mesa-driver \
        mesa-vdpau \
        mesa \
        vulkan-icd-loader \
        lib32-vulkan-icd-loader \
        vulkan-tools \
        lib32-mesa \
        lib32-vulkan-radeon \
        lib32-libva-mesa-driver \
        lib32-mesa-vdpau \
        libva-utils \
        vdpauinfo \
        radeontop \
        # System utilities
        networkmanager \
        grub efibootmgr \
        neovim htop glances git \
        gcc gdb cmake make \
        python python-pip \
        nodejs npm \
        docker \
        git-lfs \
        zram-generator \
        power-profiles-daemon \
        thermald \
        bluez bluez-utils \
        gamemode \
        corectrl \
        # Additional system utilities
        acpid \
        cpupower \
        lm_sensors \
        smartmontools \
        nvme-cli \
        # Performance monitoring
        powertop \
        s-tui \
        # Hardware video acceleration
        gstreamer-vaapi \
        ffmpeg

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Setting up execution permissions for setup scripts..."
chmod +x ${CHROOTSETUP} ${USERSETUP}

echo "Entering chroot environment..."
# Copy setup scripts to /mnt
cp ${CHROOTSETUP} ${USERSETUP} /mnt/
arch-chroot /mnt /bin/bash -c "./chrootsetup.sh && ./usrsetup.sh"

echo "Installation completed successfully!"
