#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# ==============================================================================
# Arch Linux Installation Script
# Author: c0d3h01
# Description: Automated Arch Linux installation with BTRFS and AMD optimizations
# ==============================================================================

# Strict bash settings
set -euo pipefail
IFS=$'\n\t'

# Global variables
declare -r LOG_FILE="/tmp/arch_install.log"
declare -A CONFIG

# Color codes for pretty output
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r NC='\033[0m' # No Color

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
    local level=$1
    shift
    local message=$*
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

info() {
    log "INFO" "${BLUE}$*${NC}"
}

warn() {
    log "WARN" "${YELLOW}$*${NC}"
}

error() {
    log "ERROR" "${RED}$*${NC}"
    exit 1
}

success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

# ==============================================================================
# Configuration Functions
# ==============================================================================

init_config() {
    CONFIG=(
        [DRIVE]="/dev/nvme0n1"
        [HOSTNAME]="archlinux"
        [USERNAME]="c0d3h01"
        [PASSWORD]="hell" # Note: In production, use secure password handling
        [TIMEZONE]="Asia/Kolkata"
        [LOCALE]="en_US.UTF-8"
        [CPU_VENDOR]="amd" # or "intel"
        [BTRFS_OPTS]="noatime,compress=zstd:1,space_cache=v2,commit=120"
    )

    # Derived configurations
    CONFIG[EFI_PART]="${CONFIG[DRIVE]}p1"
    CONFIG[ROOT_PART]="${CONFIG[DRIVE]}p2"
}

# ==============================================================================
# Installation Steps
# ==============================================================================

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

install_base_system() {
    info "Installing base system..."

    local packages=(
        # Base system
        base base-devel linux linux-headers linux-firmware

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

        # Performance tools
        zram-generator power-profiles-daemon
        thermald ananicy-cpp gamemode
        corectrl acpid lm_sensors
        nvme-cli powertop s-tui

        # Multimedia
        gstreamer-vaapi ffmpeg

        # Bluetooth
        bluez bluez-utils
    )

    pacstrap /mnt "${packages[@]}" || error "Failed to install base packages"
}

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
EOF
}

apply_optimizations() {
    info "Applying system optimizations..."
    cat > "/etc/systemd/zram-generator.conf" <<'ZRAMCONF'
[zram0]
zram-size = 8192    # 8GB of RAM for ZRAM
compression-algorithm = zstd
max-comp-streams = 8
writeback = 0
priority = 32767
device-type = swap
ZRAMCONF
}

configure_pacman() {
    info "Configuring pacman..."
    arch-chroot /mnt /bin/bash <<EOF
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf
EOF
}

# Cachyos repo installation
add_specific_repo() {
    local isa_level="$1"
    local gawk_script="$2"
    local repo_name="$3"
    local cmd_check="check_supported_isa_level ${isa_level}"

    local pacman_conf="/etc/pacman.conf"
    local pacman_conf_cachyos="./pacman.conf"
    local pacman_conf_path_backup="/etc/pacman.conf.bak"

    local is_isa_supported="$(eval ${cmd_check})"
    if [ $is_isa_supported -eq 0 ]; then
        info "${isa_level} is supported"

        cp $pacman_conf $pacman_conf_cachyos
        gawk -i inplace -f $gawk_script $pacman_conf_cachyos || true

        info "Backup old config"
        mv $pacman_conf $pacman_conf_path_backup

        info "CachyOS ${repo_name} Repo changed"
        mv $pacman_conf_cachyos $pacman_conf
    else
        info "${isa_level} is not supported"
    fi
}

check_supported_isa_level() {
    /lib/ld-linux-x86-64.so.2 --help | grep "$1 (supported, searched)" > /dev/null
    echo $?
}

check_supported_znver45() {
    gcc -march=native -Q --help=target 2>&1 | head -n 35 | grep -E '(znver4|znver5)' > /dev/null
    echo $?
}

check_if_repo_was_added() {
    cat /etc/pacman.conf | grep "(cachyos\|cachyos-v3\|cachyos-core-v3\|cachyos-extra-v3\|cachyos-testing-v3\|cachyos-v4\|cachyos-core-v4\|cachyos-extra-v4\|cachyos-znver4\|cachyos-core-znver4\|cachyos-extra-znver4)" > /dev/null
    echo $?
}

check_if_repo_was_commented() {
    cat /etc/pacman.conf | grep "cachyos\|cachyos-v3\|cachyos-core-v3\|cachyos-extra-v3\|cachyos-testing-v3\|cachyos-v4\|cachyos-core-v4\|cachyos-extra-v4\|cachyos-znver4\|cachyos-core-znver4\|cachyos-extra-znver4" | grep -v "#\[" | grep "\[" > /dev/null
    echo $?
}

install_cachyos_repo() {
    info "Installing CachyOS repository..."
    arch-chroot /mnt /bin/bash <<EOF
    pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    pacman-key --lsign-key F3B607488DB35A47

    local mirror_url="https://mirror.cachyos.org/repo/x86_64/cachyos"

    pacman -U "${mirror_url}/cachyos-keyring-20240331-1-any.pkg.tar.zst" \
              "${mirror_url}/cachyos-mirrorlist-18-1-any.pkg.tar.zst"    \
              "${mirror_url}/cachyos-v3-mirrorlist-18-1-any.pkg.tar.zst" \
              "${mirror_url}/cachyos-v4-mirrorlist-6-1-any.pkg.tar.zst"  \
              "${mirror_url}/pacman-7.0.0.r3.gf3211df-3.1-x86_64.pkg.tar.zst"

    local is_repo_added="$(check_if_repo_was_added)"
    local is_repo_commented="$(check_if_repo_was_commented)"
    local is_isa_v4_supported="$(check_supported_isa_level x86-64-v4)"
    local is_znver_supported="$(check_supported_znver45)"
    
    if [ $is_repo_added -ne 0 ] || [ $is_repo_commented -ne 0 ]; then
        if [ $is_znver_supported -eq 0 ]; then
            add_specific_repo x86-64-v4 ./install-znver4-repo.awk cachyos-znver4
        elif [ $is_isa_v4_supported -eq 0 ]; then
            add_specific_repo x86-64-v4 ./install-v4-repo.awk cachyos-v4
        else
            add_specific_repo x86-64-v3 ./install-repo.awk cachyos-v3
        fi
    sudo pacman -Syu --needed --noconfirm
EOF
}

install_desktop_environment() {
    info "Installing GNOME environment..."
    arch-chroot /mnt /bin/bash <<EOF
    pacman -S --needed --noconfirm \
        gnome \
        gnome-terminal \
        cachyos-gnome-settings
EOF
}

setup_user_environment() {
    info "Setting up user environment..."
    arch-chroot /mnt /bin/bash <<EOF
    # Install base development packages
    pacman -Sy --needed --noconfirm \
        cachyos-rate-mirrors \
        nodejs npm \
        fish \
        virt-manager \
        qemu-desktop \
        libvirt \
        edk2-ovmf \
        dnsmasq \
        vde2 \
        bridge-utils \
        iptables-nft \
        dmidecode \
        xclip

    # Update mirrors
    rate-mirrors arch
    cachyos-rate-mirrors

    # Install yay
    cd /tmp
    sudo -u ${CONFIG[USERNAME]} git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    sudo -u ${CONFIG[USERNAME]} makepkg -si --needed --noconfirm
    
    # Install regular packages via yay
    sudo -u ${CONFIG[USERNAME]} yay -S --needed --noconfirm \
        brave-bin \
        zoom \
        android-ndk \
        android-sdk \
        openjdk-src \
        postman-bin \
        youtube-music-bin \
        notion-app-electron \
        zed \
        gparted \
        filelight \
        kdeconnect \
        ufw \
        docker \
        tor-browser-bin

    # Install packages with --nodeps
    sudo -u ${CONFIG[USERNAME]} yay -S --needed --noconfirm --nodeps \
        telegram-desktop-bin \
        github-desktop-bin \
        visual-studio-code-bin \
        ferdium-bin \
        vesktop-bin \
        onlyoffice-bin

    # Install CPU auto-freq
    #cd /tmp
    #git clone https://github.com/AdnanHodzic/auto-cpufreq.git
    #cd auto-cpufreq
    #./auto-cpufreq-installer

    # Configure Android SDK
    echo "export ANDROID_HOME=\$HOME/Android/Sdk" >> /home/${CONFIG[USERNAME]}/.bashrc
    echo "export PATH=\$PATH:\$ANDROID_HOME/tools:\$ANDROID_HOME/platform-tools" >> /home/${CONFIG[USERNAME]}/.bashrc
    chown ${CONFIG[USERNAME]}:${CONFIG[USERNAME]} /home/${CONFIG[USERNAME]}/.bashrc
EOF
}

configure_services() {
    info "Configuring and enabling services..."
    arch-chroot /mnt /bin/bash <<EOF
    # Enable system services
    systemctl enable thermald
    systemctl enable power-profiles-daemon
    systemctl enable NetworkManager
    systemctl enable bluetooth
    systemctl enable gdm
    systemctl enable docker
    systemctl enable systemd-zram-setup@zram0.service
    systemctl enable fstrim.timer
    systemctl enable ufw
    systemctl enable libvirtd.service

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

cleanup_system() {
    info "Performing system cleanup..."
    arch-chroot /mnt /bin/bash <<EOF
    # Remove orphaned packages
    pacman -Rns \$(pacman -Qtdq) --noconfirm 2>/dev/null || true

    # Disable file indexing if KDE is installed
    if command -v balooctl6 &> /dev/null; then
        balooctl6 disable
        balooctl6 purge
    fi
EOF
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    # Start logging
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)

    info "Starting Arch Linux installation script..."

    init_config

    # Main installation steps
    setup_disk
    setup_filesystems
    install_base_system
    configure_system
    configure_pacman
    install_cachyos_repo
    install_desktop_environment
    setup_user_environment
    apply_optimizations
    configure_services
    cleanup_system

    success "Installation completed! You can now reboot your system."
}

# Execute main function
main "$@"
