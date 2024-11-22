#!/usr/bin/env bash
set -e

# ==============================================================================
# Advanced Arch Linux Installation Script
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration function
init_config() {
    declare -A CONFIG=(
        [DRIVE]="/dev/nvme0n1"
        [HOSTNAME]="archlinux"
        [USERNAME]="c0d3h01"
        [PASSWORD]="1981"
        [TIMEZONE]="Asia/Kolkata"
        [LOCALE]="en_US.UTF-8"
        [CPU_VENDOR]="amd"
        [KERNEL_TYPE]="default"  # Options: default, zen, lts, cachyos-autofdo
        [BTRFS_OPTS]="noatime,compress=zstd:1,space_cache=v2,commit=120"
    )

    CONFIG[EFI_PART]="${CONFIG[DRIVE]}p1"
    CONFIG[ROOT_PART]="${CONFIG[DRIVE]}p2"
}

# Logging functions
info() { echo -e "${BLUE}INFO:${NC} $*"; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }
error() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
success() { echo -e "${GREEN}SUCCESS:${NC} $*"; }

# Kernel selection function
select_kernel() {
    local kernel_packages=()
    local headers_packages=()

    case "${CONFIG[KERNEL_TYPE]}" in
        "zen")
            kernel_packages+=("linux-zen" "linux-zen-headers")
            ;;
        "lts")
            kernel_packages+=("linux-lts" "linux-lts-headers")
            ;;
        "cachyos-autofdo")
            # Add CachyOS repository first
            pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
            pacman-key --lsign-key F3B607488DB35A47
            
            # Add CachyOS repositories to pacman.conf
            cat >> /etc/pacman.conf <<EOL
[cachyos]
Server = https://repo.cachyos.org/x86_64/x86_64
SigLevel = Required DatabaseOptional
EOL
            
            kernel_packages+=("linux-cachyos-autofdo" "linux-cachyos-autofdo-headers")
            ;;
        *)
            kernel_packages+=("linux" "linux-headers")
            ;;
    esac

    echo "${kernel_packages[@]}"
}

# Disk preparation function
setup_disk() {
    info "Preparing disk partitions..."

    # Safety check
    read -p "WARNING: This will erase ${CONFIG[DRIVE]}. Continue? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && error "Operation cancelled by user"

    # Partition the disk
    sgdisk --zap-all "${CONFIG[DRIVE]}"
    sgdisk --clear "${CONFIG[DRIVE]}"
    sgdisk --set-alignment=8 "${CONFIG[DRIVE]}"

    # Create partitions
    sgdisk --new=1:0:+2G \
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

    local subvolumes=("@" "@home" "@cache" "@log" "@pkg" "@.snapshots")
    for subvol in "${subvolumes[@]}"; do
        btrfs subvolume create "$subvol"
    done

    popd >/dev/null
    umount /mnt

    # Mount subvolumes
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@" "${CONFIG[ROOT_PART]}" /mnt

    # Create mount points
    mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot/efi}

    # Mount other subvolumes
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@home" "${CONFIG[ROOT_PART]}" /mnt/home
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@log" "${CONFIG[ROOT_PART]}" /mnt/var/log
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@pkg" "${CONFIG[ROOT_PART]}" /mnt/var/cache/pacman/pkg
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@.snapshots" "${CONFIG[ROOT_PART]}" /mnt/.snapshots
    mount "${CONFIG[EFI_PART]}" /mnt/boot/efi
}

# Base system installation function
install_base_system() {
    info "Installing base system..."

    # Select kernel based on configuration
    local kernel_packages
    mapfile -t kernel_packages < <(select_kernel)

    local base_packages=(
        # Base system
        base base-devel "${kernel_packages[@]}" linux-firmware
        # Filesystem
        btrfs-progs
        # AMD-specific
        amd-ucode xf86-video-amdgpu
        vulkan-radeon vulkan-tools
        libva-mesa-driver mesa-vdpau mesa
        vulkan-icd-loader libva-utils
        vdpauinfo radeontop
        # System utilities
        networkmanager grub efibootmgr
        neovim glances git nano sudo
        gcc gdb cmake make
        python python-pip
        nodejs npm git-lfs
    )

    pacstrap /mnt "${base_packages[@]}" || error "Failed to install base packages"
}

# System configuration function
configure_system() {
    info "Configuring system..."

    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab

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
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${CONFIG[HOSTNAME]}.localdomain ${CONFIG[HOSTNAME]}
END

    # Set root password
    echo "root:${CONFIG[PASSWORD]}" | chpasswd

    # Create user
    useradd -m -G wheel -s /bin/bash ${CONFIG[USERNAME]}
    echo "${CONFIG[USERNAME]}:${CONFIG[PASSWORD]}" | chpasswd
    
    # Configure sudo
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

    # Configure bootloader
    sed -i 's|GRUB_CMDLINE_LINUX_DEFAULT=".*"|GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_pstate=active amdgpu.ppfeaturemask=0xffffffff zswap.enabled=0 zram.enabled=1 zram.num_devices=1 rootflags=subvol=@ mitigations=off random.trust_cpu=on page_alloc.shuffle=1"|' /etc/default/grub
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

    # ZRAM configuration
    cat > "/etc/systemd/zram-generator.conf" <<'ZRAMCONF'
zram-size = 8192
compression-algorithm = zstd
max-comp-streams = 8
writeback = 0
priority = 32767
device-type = swap
ZRAMCONF

    # Advanced kernel tuning
    cat > "/etc/sysctl.d/99-kernel-optimization.conf" <<'SYS'
kernel.sched_rt_runtime_us=-1
vm.swappiness=100
vm.dirty_bytes=268435456
vm.page-cluster=0
vm.dirty_background_bytes=134217728
vm.dirty_writeback_centisecs=1500
kernel.nmi_watchdog=0
SYS
EOF
}

# User environment setup function
setup_user_environment() {
    info "Setting up user environment..."
    arch-chroot /mnt /bin/bash <<EOF
    # Install AUR helper
    sudo -u ${CONFIG[USERNAME]} git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    sudo -u ${CONFIG[USERNAME]} makepkg -si --noconfirm

    # Install development packages
    pacman -Sy --needed --noconfirm \
        nodejs npm \
        virt-manager \
        qemu-desktop \
        libvirt \
        edk2-ovmf \
        dnsmasq \
        vde2 \
        bridge-utils \
        dmidecode \
        xclip \
        rocm-hip-sdk \
        rocm-opencl-sdk \
        python-numpy \
        python-pandas \
        python-scipy \
        python-matplotlib \
        python-scikit-learn \
        torchvision \
        zram-generator \
        thermald ananicy-cpp \
        gstreamer-vaapi ffmpeg \
        bluez bluez-utils

    # Install user applications via yay
    sudo -u ${CONFIG[USERNAME]} yay -Sy --needed --noconfirm \
        brave-bin \
        zoom \
        android-ndk \
        android-tools \
        android-sdk \
        android-studio \
        postman-bin \
        flutter \
        youtube-music-bin \
        notion-app-electron \
        zed

    # Configure Android SDK
    echo "export ANDROID_HOME=\$HOME/Android/Sdk" >> "/home/${CONFIG[USERNAME]}/.bashrc"
    echo "export PATH=\$PATH:\$ANDROID_HOME/tools:\$ANDROID_HOME/platform-tools" >> "/home/${CONFIG[USERNAME]}/.bashrc"
    chown ${CONFIG[USERNAME]}:${CONFIG[USERNAME]} "/home/${CONFIG[USERNAME]}/.bashrc"
EOF
}

# Services configuration function
configure_services() {
    info "Configuring services..."
    arch-chroot /mnt /bin/bash <<EOF
    # Enable system services
    systemctl enable thermald
    systemctl enable NetworkManager
    systemctl enable bluetooth
    systemctl enable systemd-zram-setup@zram0.service
    systemctl enable fstrim.timer
    systemctl enable docker
    systemctl enable ufw

    # Configure firewall
    ufw enable
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    ufw allow 1714:1764/udp
    ufw allow 1714:1764/tcp
    ufw logging on
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
    setup_user_environment
    configure_services
    
    umount -R /mnt

    success "Installation completed! You can now reboot your system."
}

# Execute main function
main "$@"
