#!/bash/bin

set -e
set -euxo pipefail

exec 1> >(tee -a "./debug.logs")

# variables.
DRIVE="/dev/nvme0n1"
EFI_PART="${DRIVE}p1"
ROOT_PART="${DRIVE}p2"


function disk_partition() {
  echo "[*] Preparing disk partitions..."
# Clear all partition data and GPT/MBR structures
sgdisk --zap-all ${DRIVE}
sgdisk --clear ${DRIVE}
sgdisk --set-alignment=8 ${DRIVE}

# Create partitions
echo "[*] Creating partitions..."
sgdisk --new=1:0:+2G \
       --typecode=1:ef00 \
       --change-name=1:"EFI" \
       --new=2:0:0 \
       --typecode=2:8300 \
       --change-name=2:"ROOT" \
       --attributes=2:set:2 \
       ${DRIVE}

# Verify partitions
echo "[*] Verifying partitions..."
sgdisk --verify ${DRIVE}
partprobe ${DRIVE}

# Format partitions
echo "[*] Formatting partitions..."
mkfs.fat -F32 -n EFI ${EFI_PART}
mkfs.btrfs -f \
    -L ROOT \
    -n 32k \
    -m dup \
    ${ROOT_PART}
};

function mount_partition() {
# Unmount and remount with subvolumes
umount /mnt

echo "Mounting subvolumes..."
# Mount options
MOUNT_OPTS="noatime,compress=zstd:1,space_cache=v2,commit=120"

# Mount subvolumes
mount -o ${MOUNT_OPTS},subvol=@ ${ROOT_PART} /mnt

# Create mount points
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot/efi}

# Mount other subvolumes
mount -o ${MOUNT_OPTS},subvol=@home ${ROOT_PART} /mnt/home
mount -o ${MOUNT_OPTS},subvol=@log ${ROOT_PART} /mnt/var/log
mount -o ${MOUNT_OPTS},subvol=@pkg ${ROOT_PART} /mnt/var/cache/pacman/pkg
mount -o ${MOUNT_OPTS},subvol=@.snapshots ${ROOT_PART} /mnt/.snapshots

# Mount EFI partition
mount ${EFI_PART} /mnt/boot/efi
};

function pacstraps() {
# Install base system and AMD-specific packages
    pacstrap /mnt \
        base base-devel \
        linux linux-headers linux-firmware \
        btrfs-progs \
        amd-ucode \
        xf86-video-amdgpu \
        vulkan-radeon \
        libva-mesa-driver \
        mesa-vdpau \
        mesa \
        vulkan-icd-loader \
        vulkan-tools \
        libva-utils \
        vdpauinfo \
        radeontop \
        networkmanager \
        grub efibootmgr \
        neovim glances git nano sudo \
        gcc gdb cmake make \
        python python-pip \
        nodejs npm \
        git-lfs \
        zram-generator \
        power-profiles-daemon \
        thermald \
        bluez bluez-utils \
        gamemode \
        corectrl \
        acpid \
        lm_sensors \
        nvme-cli \
        powertop \
        s-tui \
        gstreamer-vaapi \
        ffmpeg
};
