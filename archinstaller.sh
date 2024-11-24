#!/usr/bin/env bash
set -e
set -x

# ==============================================================================
# Arch Linux Installation Script
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

declare -A CONFIG

# Configuration function
init_config() {
    CONFIG=(
        [DRIVE]="/dev/nvme0n1"
        [HOSTNAME]="archlinux"
        [USERNAME]="c0d3h01"
        [PASSWORD]="1981"
        [TIMEZONE]="Asia/Kolkata"
        [LOCALE]="en_US.UTF-8"
        [CPU_VENDOR]="amd"
        [BTRFS_OPTS]="defaults,noatime,compress=zstd:1,compress-force=zstd,space_cache=v2,commit=120,discard=async,autodefrag,clear_cache,ssd,nodiratime"
    )

    CONFIG[EFI_PART]="${CONFIG[DRIVE]}p1"
    CONFIG[ROOT_PART]="${CONFIG[DRIVE]}p2"
}

# Logging functions
info() { echo -e "${BLUE}INFO:${NC} $*"; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }
error() {
    echo -e "${RED}ERROR:${NC} $*" >&2
    exit 1
}
success() { echo -e "${GREEN}SUCCESS:${NC} $*"; }

# Disk preparation function
setup_disk() {
    info "Preparing disk partitions..."

    # Safety check
    read -p "${RED}WARNING: This will erase ${CONFIG[DRIVE]}. Continue? (y/N) ${NC}" -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && error "Operation cancelled by user"

    # Partition the disk
    sgdisk --zap-all "${CONFIG[DRIVE]}"
    sgdisk --clear "${CONFIG[DRIVE]}"
    sgdisk --set-alignment=8 "${CONFIG[DRIVE]}"

    # Create partitions
    sgdisk --new=1:0:+1G \
        --typecode=1:ef00 \
        --change-name=1:"EFI" \
        --new=2:0:0 \
        --typecode=2:8300 \
        --change-name=2:"ROOT" \
        --attributes=2:set:2 \
        "${CONFIG[DRIVE]}"

    # Verify and update partition table
    sgdisk --verify "${CONFIG[DRIVE]}" || error "Partition verification failed"
    partprobe "${CONFIG[DRIVE]}"
}

# Filesystem setup function
setup_filesystems() {
    info "Setting up filesystems..."

    # Format partitions
    mkfs.fat -F32 -n EFI "${CONFIG[EFI_PART]}"
    mkfs.btrfs -f -L ROOT -n 32k -m dup "${CONFIG[ROOT_PART]}"

    # Create BTRFS subvolumes
    mount "${CONFIG[ROOT_PART]}" /mnt
    pushd /mnt >/dev/null

    local subvolumes=("@" "@home" "@cache" "@srv" "@tmp" "@log" "@pkg" "@.snapshots")
    for subvol in "${subvolumes[@]}"; do
        btrfs subvolume create "$subvol"
    done

    popd >/dev/null
    umount /mnt

    # Mount subvolumes
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@" "${CONFIG[ROOT_PART]}" /mnt

    # Create mount points
    mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot/efi,tmp,srv}

    # Mount other subvolumes
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@home" "${CONFIG[ROOT_PART]}" /mnt/home
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@log" "${CONFIG[ROOT_PART]}" /mnt/var/log
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@pkg" "${CONFIG[ROOT_PART]}" /mnt/var/cache/pacman/pkg
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@.snapshots" "${CONFIG[ROOT_PART]}" /mnt/.snapshots
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@tmp" "${CONFIG[ROOT_PART]}" /mnt/tmp
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@srv" "${CONFIG[ROOT_PART]}" /mnt/srv
    mount "${CONFIG[EFI_PART]}" /mnt/boot/efi
}

# Base system installation function
install_base_system() {
    info "Installing base system..."

    local base_packages=(
        # Core System
        base base-devel linux-lts linux-lts-docs linux-headers linux-firmware

        # CPU & GPU Drivers
        amd-ucode
        xf86-video-amdgpu
        vulkan-radeon vulkan-tools
        libva-mesa-driver mesa-vdpau mesa
        vulkan-icd-loader libva-utils
        vdpauinfo radeontop
        os-prober mesa e2fsprogs dosfstools ntfs-3g

        # Graphics Extensions
        lib32-mesa
        lib32-vulkan-radeon
        mesa-vdpau
        lib32-mesa-vdpau

        # Essential System Utilities
        networkmanager
        grub
        efibootmgr
        btrfs-progs
        mtools nmcli
        snapper nano neovim

        # Development Tools
        gcc gdb cmake make clang
        python python-pip
        nodejs npm git-lfs

        # System Performance
        zram-generator
        thermald
        ananicy-cpp

        # Multimedia & Bluetooth
        gstreamer-vaapi
        ffmpeg
        bluez
        bluez-utils
        pipewire
        pipewire-alsa
        pipewire-jack
        pipewire-pulse
        wireplumber
    )

    pacstrap /mnt "${base_packages[@]}" || error "Failed to install base packages"
}

# System configuration function
configure_system() {
    info "Configuring system..."

    # Generate fstab
    genfstab -U /mnt >>/mnt/etc/fstab

    # Chroot and configure
    arch-chroot /mnt /bin/bash <<EOF
    # Set timezone and clock
    ln -sf /usr/share/zoneinfo/${CONFIG[TIMEZONE]} /etc/localtime
    hwclock --systohc

    # Set locale
    echo "${CONFIG[LOCALE]} UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=${CONFIG[LOCALE]}" > /etc/locale.conf

    # Set hostname
    echo "${CONFIG[HOSTNAME]}" > /etc/hostname

    # Configure hosts
    cat > /etc/hosts <<-END
# Standard host addresses
127.0.0.1  localhost
::1        localhost ip6-localhost ip6-loopback
ff02::1    ip6-allnodes
ff02::2    ip6-allrouters
# This host address
127.0.1.1  ${CONFIG[HOSTNAME]}
END

    # Set root password
    echo "root:${CONFIG[PASSWORD]}" | chpasswd

    # Create user
    useradd -m -G wheel -s /bin/bash ${CONFIG[USERNAME]}
    echo "${CONFIG[USERNAME]}:${CONFIG[PASSWORD]}" | chpasswd
    
    # Configure sudo
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

    # Configure bootloader
    sed -i 's|GRUB_CMDLINE_LINUX_DEFAULT=".*"|GRUB_CMDLINE_LINUX_DEFAULT="nowatchdog nvme_load=YES zswap.enabled=0 splash loglevel=3"|' /etc/default/grub
    sed -i 's|GRUB_TIMEOUT=.*|GRUB_TIMEOUT=2|' /etc/default/grub

    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
    grub-mkconfig -o /boot/grub/grub.cfg
    mkinitcpio -P
EOF
}

# Performance optimization function
apply_optimizations() {
    info "Applying system optimizations..."
    arch-chroot /mnt /bin/bash <<EOF
    
    # Pacman optimization
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    echo "ILoveCandy" >> /etc/pacman.conf
    echo "DisableDownloadTimeout" >> /etc/pacman.conf

    cat > "/usr/lib/udev/rules.d/60-ioschedulers.rules" <<'IO'
# HDD
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", \
    ATTR{queue/scheduler}="bfq"

# SSD
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", \
    ATTR{queue/scheduler}="mq-deadline"

# NVMe SSD
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", \
    ATTR{queue/scheduler}="none"
IO

    cat > "/usr/lib/modprobe.d/nvidia.conf" <<'NVID'
options nvidia NVreg_UsePageAttributeTable=1 \
    NVreg_InitializeSystemMemoryAllocations=0 \
    NVreg_DynamicPowerManagement=0x02 \
    NVreg_EnableGpuFirmware=0
options nvidia_drm modeset=1 fbdev=1
NVID

    # ZRAM configuration
    cat > "/etc/systemd/zram-generator.conf" <<'ZRAMCONF'
[zram0]
zram-size = ram
compression-algorithm = zstd
max-comp-streams = auto
swap-priority = 100
fs-type = swap
ZRAMCONF

    cat > "/usr/lib/udev/rules.d/30-zram.rules" <<'ZRULES'
ACTION=="add", KERNEL=="zram[0-9]*", ATTR{recomp_algorithm}="algo=lz4 priority=1", \
  RUN+="/sbin/sh -c echo 'type=huge' > /sys/block/%k/recompress"

TEST!="/dev/zram0", GOTO="zram_end"

SYSCTL{vm.swappiness}="150"

LABEL="zram_end"
ZRULES

    # Advanced kernel tuning
    cat > "/etc/sysctl.d/99-kernel-optimization.conf" <<'SYS'
vm.swappiness = 100
vm.vfs_cache_pressure=50
vm.dirty_bytes = 268435456
vm.page-cluster = 0
vm.dirty_background_bytes = 134217728
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 1500

kernel.nmi_watchdog = 0
kernel.unprivileged_userns_clone = 1
kernel.printk = 3 3 3 3
kernel.kptr_restrict = 2
kernel.kexec_load_disabled = 1

fs.inotify.max_user_watches = 524288
fs.file-max = 2097152
fs.xfs.xfssyncd_centisecs = 10000

kernel.sched_rt_runtime_us=-1
SYS

mkdir -p /etc/ananicy.d/

cat > "/etc/ananicy.d/ananicy.conf" <<'ANA'
## Ananicy 2.X configuration
# Ananicy run full system scan every "check_freq" seconds
# supported values 0.01..86400
# values which have sense: 1..60
check_freq = 15

# Disables functionality
cgroup_load = true
type_load = true
rule_load = true

apply_nice = true
apply_latnice = true
apply_ionice = true
apply_sched = true
apply_oom_score_adj = true
apply_cgroup = true

# Loglevel
# supported values: trace, debug, info, warn, error, critical
loglevel = info

# If enabled it does log task name after rule matched and got applied to the task
log_applied_rule = false

# It tries to move realtime task to root cgroup to be able to move it to the ananicy-cpp controlled one
# NOTE: may introduce issues, for example with polkit
cgroup_realtime_workaround = false
ANA
EOF
}

# Services configuration function
configure_services() {
    info "Configuring services..."
    arch-chroot /mnt /bin/bash <<EOF
    # Enable system services
    systemctl enable thermald
    systemctl enable NetworkManager
    systemctl enable bluetooth.service
    systemctl enable systemd-zram-setup@zram0.service
    systemctl enable fstrim.timer
    systemctl enable ananicy-cpp.service
    systemctl enable cups
    systemctl enable lightdm
EOF
}

desktop_install() {
arch-chroot /mnt /bin/bash <<EOF
    # Desktop Environment GNOME
    pacman -Sy --needed --noconfirm \
        wayland \
        xorg-server \
        xorg-xwayland \
        gnome \
        gnome-tweaks \
        gnome-terminal \
        alacritty \
        cups
        
    systemctl enable gdm
EOF
}

# Main execution function
main() {
    info "Starting Arch Linux installation script..."

    init_config

    # Main installation steps
    setup_disk
    setup_filesystems
    install_base_system
    configure_system
    apply_optimizations
    desktop_install
    configure_services

    umount -R /mnt

    success "Installation completed! You can now reboot your system."
}

# Execute main function
main "$@"
