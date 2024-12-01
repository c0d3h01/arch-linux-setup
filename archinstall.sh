#!/usr/bin/env bash
# shellcheck disable=SC2162
# shellcheck disable=SC2129
# shellcheck disable=SC2024
# shellcheck disable=SC2016
set -euxo pipefail
#exec > >(tee -i /mnt/var/log/arch_install.log) 2>&1

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

    while true; do
        read -s -p "Enter a single password for root and user: " PASSWORD
        echo
        read -s -p "Confirm the password: " CONFIRM_PASSWORD
        echo
        if [ "$PASSWORD" = "$CONFIRM_PASSWORD" ]; then
            break
        else
            echo "Passwords do not match. Try again."
        fi
    done

    CONFIG=(
        [DRIVE]="/dev/nvme0n1"
        [HOSTNAME]="archlinux"
        [USERNAME]="c0d3h01"
        [PASSWORD]="$PASSWORD"
        [TIMEZONE]="Asia/Kolkata"
        [LOCALE]="en_US.UTF-8"
        [CPU_VENDOR]="amd"
        [BTRFS_OPTS]="defaults,noatime,compress=zstd:1,commit=128,discard=async"
    )

    CONFIG[EFI_PART]="${CONFIG[DRIVE]}p1"
    CONFIG[ROOT_PART]="${CONFIG[DRIVE]}p2"
}

# Logging functions
info() { echo -e "${BLUE}INFO: $* ${NC}"; }
warn() { echo -e "${YELLOW}WARN: $* ${NC}"; }
error() {
    echo -e "${RED}ERROR: $* ${NC}" >&2
    exit 1
}
success() { echo -e "${GREEN}SUCCESS:$* ${NC}"; }

# Disk preparation function
setup_disk() {
    info "Preparing disk partitions..."

    # Safety check
    read -p "WARNING: This will erase ${CONFIG[DRIVE]}. Continue? (y/N)" -n 1 -r
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

    # Pacman configure for arch-iso
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    sed -i '/^# Misc options/a DisableDownloadTimeout\nILoveCandy' /etc/pacman.conf
    sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf

    rm -rf "/etc/pacman.d/mirrorlist"
    tee > "/etc/pacman.d/mirrorlist" <<'MIRROR'
Server = http://mirror.sahil.world/archlinux/$repo/os/$arch
Server = https://mirror.sahil.world/archlinux/$repo/os/$arch
Server = http://mirrors.nxtgen.com/archlinux-mirror/$repo/os/$arch
Server = https://mirrors.nxtgen.com/archlinux-mirror/$repo/os/$arch
Server = http://in-mirror.garudalinux.org/archlinux/$repo/os/$arch
Server = https://in-mirror.garudalinux.org/archlinux/$repo/os/$arch
MIRROR
    
    # Refresh package databases
    pacman -Syy

    local base_packages=(
        # Core System
        base base-devel
        linux-lts linux-lts-headers
        linux-firmware sof-firmware

        # CPU & GPU Drivers
        amd-ucode xf86-video-amdgpu
        xf86-input-libinput gvfs
        mesa-vdpau mesa lib32-mesa
        lib32-glibc vulkan-radeon lib32-vulkan-radeon
        vulkan-tools vulkan-icd-loader
        libva-utils libva-mesa-driver

        # Essential System Utilities
        networkmanager grub efibootmgr
        btrfs-progs bash-completion
        snapper vim fastfetch nodejs npm
        reflector sudo git nano xclip
        laptop-detect noto-fonts
        flatpak xorg htop firewalld
        ninja gcc gdb cmake clang
        zram-generator ananicy-cpp
        alacritty cups rsync glances
        irqbalance tlp tlp-rdw

        # Dev tools
        rocm-hip-sdk rocm-opencl-sdk
        python python-pip python-scikit-learn
        python-numpy python-pandas
        python-scipy python-matplotlib

        # Multimedia & Bluetooth
        gstreamer-vaapi ffmpeg
        bluez bluez-utils
        pipewire pipewire-alsa pipewire-jack
        pipewire-pulse wireplumber

        # Daily Usage Needs
        firefox zed micro kdeconnect rhythmbox
    )
    pacstrap -K /mnt --needed "${base_packages[@]}"
}

# System configuration function
configure_system() {
    info "Configuring system..."

    # Generate fstab
    genfstab -U /mnt >>/mnt/etc/fstab

    # Chroot and configure
    arch-chroot /mnt /bin/bash <<'EOF'
    # Set timezone and clock
    ln -sf /usr/share/zoneinfo/${CONFIG[TIMEZONE]} /etc/localtime
    hwclock --systohc

    # Set locale
    echo "${CONFIG[LOCALE]} UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=${CONFIG[LOCALE]}" > /etc/locale.conf

    # Set Keymap
    echo "KEYMAP=us" > "/etc/vconsole.conf"

    # Set hostname
    hostnamectl hostname ${CONFIG[HOSTNAME]}

    # Configure hosts
    tee > /etc/hosts <<'HOST'
127.0.0.1  localhost
::1        localhost ip6-localhost ip6-loopback
ff02::1    ip6-allnodes
ff02::2    ip6-allrouters
127.0.1.1  ${CONFIG[HOSTNAME]}
HOST

    # Set root password
    echo "root:${CONFIG[PASSWORD]}" | chpasswd

    # Create user
    useradd -m -G wheel -s /bin/bash ${CONFIG[USERNAME]}
    echo "${CONFIG[USERNAME]}:${CONFIG[PASSWORD]}" | chpasswd
    
    # Configure sudo
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

    # Configure bootloader
    sed -i 's|GRUB_CMDLINE_LINUX_DEFAULT=".*"|GRUB_CMDLINE_LINUX_DEFAULT="nowatchdog zswap.enabled=0 zram.enabled=1 splash loglevel=3"|' /etc/default/grub
    sed -i 's|GRUB_TIMEOUT=.*|GRUB_TIMEOUT=2|' /etc/default/grub

    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
    grub-mkconfig -o /boot/grub/grub.cfg
    mkinitcpio -P
EOF
}

# Performance optimization function
apply_optimizations() {
    info "Applying system optimizations..."
    arch-chroot /mnt /bin/bash <<'EOF'

    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    sed -i '/^# Misc options/a DisableDownloadTimeout\nILoveCandy' /etc/pacman.conf
    sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf

    rm -rf "/etc/pacman.d/mirrorlist"
    tee > "/etc/pacman.d/mirrorlist" <<'MIRROR'
Server = http://mirror.sahil.world/archlinux/$repo/os/$arch
Server = https://mirror.sahil.world/archlinux/$repo/os/$arch
Server = http://mirrors.nxtgen.com/archlinux-mirror/$repo/os/$arch
Server = https://mirrors.nxtgen.com/archlinux-mirror/$repo/os/$arch
Server = http://in-mirror.garudalinux.org/archlinux/$repo/os/$arch
Server = https://in-mirror.garudalinux.org/archlinux/$repo/os/$arch
MIRROR

    # Refresh package databases
    pacman -Syy

    tee > "/etc/xdg/reflector/reflector.conf" <<'MIRROR'
--save /etc/pacman.d/mirrorlist
--fastest 5
--country IN,SG
--protocol https
--latest 5
MIRROR

    # ZRAM configuration
    tee > "/etc/systemd/zram-generator.conf" <<'ZRAMCONF'
[zram0] 
compression-algorithm = zstd
zram-size = ram * 2
swap-priority = 100
fs-type = swap
ZRAMCONF

    # ZRAM Rules
    tee > "/etc/udev/rules.d/99-zram.rules" <<'ZRULES'
# Prefer to recompress only huge pages. This will result in additional memory
# savings, but may slightly increase CPU load due to additional compression
# overhead.
ACTION=="add", KERNEL=="zram[0-9]*", ATTR{recomp_algorithm}="algo=lz4 priority=1", \
  RUN+="/sbin/sh -c echo 'type=huge' > /sys/block/%k/recompress"
TEST!="/dev/zram0", GOTO="zram_end"
SYSCTL{vm.swappiness}="150"
LABEL="zram_end"
ZRULES

    # I/O Schedulers
    tee > "/usr/lib/udev/rules.d/60-ioschedulers.rules" <<'IOSHED'
# HDD
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
# SSD
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# NVMe SSD
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
IOSHED
EOF
}

# Desktop Environment GNOME
desktop_install() {
    arch-chroot /mnt /bin/bash <<'EOF'
    pacman -S --needed --noconfirm gnome gnome-terminal gnome-boxes
    pacman -Rns gnome-calendar gnome-text-editor gnome-tour gnome-user-docs gnome-weather gnome-music epiphany malcontent gnome-software gnome-music gnome-characters
    rm -rf /usr/share/gnome-shell/extensions/*

    systemctl enable gdm
EOF
}

# Services configuration function
configure_services() {
    info "Configuring services..."
    arch-chroot /mnt /bin/bash <<'EOF'
    # Enable system services
    systemctl enable NetworkManager
    systemctl enable bluetooth.service
    systemctl enable systemd-zram-setup@zram0.service
    systemctl enable fstrim.timer
    systemctl enable ananicy-cpp.service
    systemctl enable cups
    systemctl enable irqbalance
    systemctl enable tlp.service
    systemctl enable firewalld
    systemctl enable reflector
EOF
}

archinstall() {
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

# User environment setup function
usrsetup() {
    # Yay installation AUR pkg manager
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si

    # Install user applications via yay
    yay -S --needed --noconfirm \
        telegram-desktop-bin \
        onlyoffice-bin \
        tor-browser-bin \
        vesktop-bin \
        github-desktop-bin \
        zoom linutil-bin \
        docker-desktop \
        ananicy-rules-git wine preload \
        visual-studio-code-bin \
        android-ndk \
        android-sdk \
        android-studio \
        postman-bin \
        flutter-bin \
        youtube-music-bin \
        notion-app-electron

    # Enable services
    sudo systemctl enable --now preload

    # Set up variables
    sed -i '$a\export PATH="/opt/android-ndk:$PATH"' "/home/c0d3h01/.bashrc"
    sed -i '$a\export PATH="/opt/android-sdk:$PATH"' "/home/c0d3h01/.bashrc"
    sed -i '$a\export PATH="/opt/flutter:$PATH"' "/home/c0d3h01/.bashrc"
}

# Main execution function
main() {
    case "$1" in
    "--install" | "-i")
        archinstall
        ;;
    "--setup" | "-s")
        usrsetup
        ;;
    "--help" | "-h")
        show_help
        ;;
    "")
        echo "Error: No arguments provided"
        show_help
        exit 1
        ;;
    *)
        echo "Error: Unknown option: $1"
        show_help
        exit 1
        ;;
    esac

}

show_help() {
    tee <<EOF
Usage: $(basename "$0") [OPTION]

Options:
    -i, --install    Run Arch Linux installation
    -s, --setup      Setup user configuration
    -h, --help       Display this help message
EOF
}

# Execute main function
main "$@"
