#!/usr/bin/env bash
# ==============================================================================
# Automated Arch Linux Installation Personal Setup Script
# ==============================================================================
set -euxo pipefail
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
        [HOSTNAME]="world"
        [USERNAME]="harsh"
        [PASSWORD]="$PASSWORD"
        [TIMEZONE]="Asia/Kolkata"
        [LOCALE]="en_IN.UTF-8"
        [CPU_VENDOR]="amd"
        [BTRFS_OPTS]="compress=zstd:1"
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

    local subvolumes=("@" "@home" "@cache" "@tmp" "@log" "@.snapshots")
    for subvol in "${subvolumes[@]}"; do
        btrfs subvolume create "$subvol"
    done

    popd >/dev/null
    umount /mnt

    # Mount subvolumes
    mount -o "${CONFIG[BTRFS_OPTS]},subvol=@" "${CONFIG[ROOT_PART]}" /mnt

    # Create mount points
    mkdir -p /mnt/{home,var/log,.snapshots,boot/efi,tmp}

    # Mount other subvolumes
    mount -o "subvol=@home,${CONFIG[BTRFS_OPTS]}" "${CONFIG[ROOT_PART]}" /mnt/home
    mount -o "subvol=@log,${CONFIG[BTRFS_OPTS]}" "${CONFIG[ROOT_PART]}" /mnt/var/log
    mount -o "subvol=@.snapshots,${CONFIG[BTRFS_OPTS]}" "${CONFIG[ROOT_PART]}" /mnt/.snapshots
    mount -o "subvol=@tmp,${CONFIG[BTRFS_OPTS]}" "${CONFIG[ROOT_PART]}" /mnt/tmp
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
Server = http://mirrors.nxtgen.com/archlinux-mirror/$repo/os/$arch
Server = https://mirrors.nxtgen.com/archlinux-mirror/$repo/os/$arch
Server = http://mirrors.piconets.webwerks.in/archlinux-mirror/$repo/os/$arch
Server = https://mirrors.piconets.webwerks.in/archlinux-mirror/$repo/os/$arch
Server = http://mirror.sahil.world/archlinux/$repo/os/$arch
Server = https://mirror.sahil.world/archlinux/$repo/os/$arch
Server = http://mirrors.saswata.cc/archlinux/$repo/os/$arch
Server = https://mirrors.saswata.cc/archlinux/$repo/os/$arch
Server = http://in-mirror.garudalinux.org/archlinux/$repo/os/$arch
Server = https://in-mirror.garudalinux.org/archlinux/$repo/os/$arch
MIRROR


    # Refresh package databases
    pacman -Syy

    local base_packages=(
        # Core System
        base base-devel
        linux-firmware sof-firmware
        linux linux-headers
        linux-lts linux-lts-headers

        # CPU & GPU Drivers
        amd-ucode gvfs mesa-vdpau
        libva-mesa-driver libva-utils mesa lib32-mesa
        vulkan-radeon lib32-vulkan-radeon vulkan-headers
        xf86-video-amdgpu xf86-video-ati xf86-input-libinput
        xorg-server xorg-xinit

        # Essential System Utilities
        networkmanager grub efibootmgr
        btrfs-progs bash-completion noto-fonts
        htop neovim fastfetch nodejs npm
        git xclip laptop-detect
        flatpak  htop glances firewalld timeshift
        ninja gcc gdb cmake clang zram-generator rsync

        # Multimedia & Bluetooth
        bluez bluez-utils
        
        # Daily Usage Needs
        zed kdeconnect rhythmbox libreoffice-fresh
        python python-pip python-scikit-learn
        python-numpy python-pandas
        python-scipy python-matplotlib
    )
    pacstrap -K /mnt --needed "${base_packages[@]}"
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

    # Set Keymap
    echo "KEYMAP=us" > "/etc/vconsole.conf"

    # Set hostname
    echo "${CONFIG[HOSTNAME]}" > /etc/hostname

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

    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
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
Server = http://mirrors.nxtgen.com/archlinux-mirror/$repo/os/$arch
Server = https://mirrors.nxtgen.com/archlinux-mirror/$repo/os/$arch
Server = http://mirrors.piconets.webwerks.in/archlinux-mirror/$repo/os/$arch
Server = https://mirrors.piconets.webwerks.in/archlinux-mirror/$repo/os/$arch
Server = http://mirror.sahil.world/archlinux/$repo/os/$arch
Server = https://mirror.sahil.world/archlinux/$repo/os/$arch
Server = http://mirrors.saswata.cc/archlinux/$repo/os/$arch
Server = https://mirrors.saswata.cc/archlinux/$repo/os/$arch
Server = http://in-mirror.garudalinux.org/archlinux/$repo/os/$arch
Server = https://in-mirror.garudalinux.org/archlinux/$repo/os/$arch
MIRROR


    # Refresh package databases
    pacman -Syy --noconfirm

    # ZRAM configuration
    tee > "/etc/systemd/zram-generator.conf" <<'ZRAMCONF'
[zram0] 
compression-algorithm = zstd
zram-size = ram
swap-priority = 100
fs-type = swap
ZRAMCONF

    tee > "/etc/sysctl.d/99-kernel-sched-rt.conf" <<'KSHED'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_writeback_centisecs = 500
fs.file-max = 2097152
KSHED

    tee > "/usr/lib/udev/rules.d/30-zram.rules" <<'ZRULES
# Prefer to recompress only huge pages. This will result in additional memory
# savings, but may slightly increase CPU load due to additional compression
# overhead.
ACTION=="add", KERNEL=="zram[0-9]*", ATTR{recomp_algorithm}="algo=lz4 priority=1", \
  RUN+="/sbin/sh -c echo 'type=huge' > /sys/block/%k/recompress"

TEST!="/dev/zram0", GOTO="zram_end"

# Since ZRAM stores all pages in compressed form in RAM, we should prefer
# preempting anonymous pages more than a page (file) cache.  Preempting file
# pages may not be desirable because a process may want to access a file at any
# time, whereas if it is preempted, it will cause an additional read cycle from
# the disk.
SYSCTL{vm.swappiness}="150"

LABEL="zram_end"
ZRULES

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
    pacman -S --needed --noconfirm \
    gvfs pavucontrol xarchiver xfce4 xfce4-goodies network-manager-applet \
    lightdm lightdm-gtk-greeter
    systemctl enable lightdm
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
    systemctl enable firewalld
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

# Check if yay is already installed
if command -v yay &> /dev/null; then
    echo "yay is already installed. Skipping installation."
else
    # Clone yay-bin from AUR
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si
    cd ..
    rm -rf yay-bin
fi

    # Install user applications via yay
    yay -S --needed --noconfirm \
        telegram-desktop-bin flutter-bin \
        vesktop-bin ferdium-bin brave-bin \
        zoom visual-studio-code-bin \
        wine youtube-music-bin

    # Set up variables
    # Bash configuration
sed -i '$a\
\
alias i="sudo pacman -S"\
alias o="sudo pacman -Rns"\
alias update="sudo pacman -Syyu --needed --noconfirm && yay --noconfirm"\
alias clean="yay -Scc --noconfirm"\
alias la="ls -la"\
\
# Use bash-completion, if available\
[[ $PS1 && -f /usr/share/bash-completion/bash_completion ]] &&\
    . /usr/share/bash-completion/bash_completion\
\
export CHROME_EXECUTABLE=$(which brave)\
export PATH=$PATH:/opt/platform-tools:/opt/android-ndk\
\
fastfetch' ~/.bashrc

echo "Configuration updated for shell."

    # sudo chown -R harsh:harsh android-sdk
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
