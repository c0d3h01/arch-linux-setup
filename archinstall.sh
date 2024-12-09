#!/usr/bin/env bash
#
# shellcheck disable=SC1078
# shellcheck disable=SC2162
# shellcheck disable=SC1079
# shellcheck disable=SC1009
# shellcehck disable=SC1072
# shellcheck disable=SC1073
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
        [HOSTNAME]="archlinux"
        [USERNAME]="harshal"
        [PASSWORD]="$PASSWORD"
        [TIMEZONE]="Asia/Kolkata"
        [LOCALE]="en_IN.UTF-8"
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
    info "Preparing disk for low-end laptop performance..."
    
    # Safety confirmation
    read -p "WARNING: This will erase ${CONFIG[DRIVE]}. Continue? (y/N)" -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && error "Operation cancelled by user"

    # Optimized disk preparation
    sgdisk --zap-all "${CONFIG[DRIVE]}"
    sgdisk --clear "${CONFIG[DRIVE]}"
    
    # Performance-focused alignment
    sgdisk --set-alignment=4096 "${CONFIG[DRIVE]}"

    # Minimalist, performance-optimized partitioning
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

setup_filesystems() {
    info "Optimizing filesystems for low-end laptop..."

    # Format with performance-focused options
    mkfs.fat -F32 "${CONFIG[EFI_PART]}"
    mkfs.btrfs -f -L ROOT \
        -n 32k \
        -m dup \
        -O discard \
        "${CONFIG[ROOT_PART]}"

    # Mount and create subvolumes
    mount "${CONFIG[ROOT_PART]}" /mnt

    # Optimize subvolume layout
    pushd /mnt >/dev/null
    local subvolumes=("@" "@home" "@cache" "@tmp" "@log")
    for subvol in "${subvolumes[@]}"; do
        btrfs subvolume create "$subvol"
    done
    popd >/dev/null
    umount /mnt

    # Mount with performance options
    mount -o "noatime,compress=zstd:1,discard=async,ssd,space_cache=v2,subvol=@" "${CONFIG[ROOT_PART]}" /mnt

    # Create necessary mount points
    mkdir -p /mnt/{home,var/{cache,log},tmp,boot/efi}

    # Mount subvolumes with optimized options
    mount -o "noatime,compress=zstd:1,discard=async,ssd,space_cache=v2,subvol=@home" "${CONFIG[ROOT_PART]}" /mnt/home
    mount -o "noatime,compress=zstd:1,discard=async,ssd,space_cache=v2,subvol=@cache" "${CONFIG[ROOT_PART]}" /mnt/var/cache
    mount -o "noatime,compress=zstd:1,discard=async,ssd,space_cache=v2,subvol=@log" "${CONFIG[ROOT_PART]}" /mnt/var/log
    mount -o "noatime,compress=zstd:1,discard=async,ssd,space_cache=v2,subvol=@tmp" "${CONFIG[ROOT_PART]}" /mnt/tmp
    mount "${CONFIG[EFI_PART]}" /mnt/boot/efi

    # Create swap file with SSD optimization
    truncate -s 0 /mnt/swap/swapfile
    chattr +C /mnt/swap/swapfile
    fallocate -l 8G /mnt/swap/swapfile
    chmod 600 /mnt/swap/swapfile
    mkswap /mnt/swap/swapfile
}

# Base system installation function
install_base_system() {
    info "Installing base system..."

    # Pacman configure for arch-iso
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    sed -i '/^# Misc options/a DisableDownloadTimeout\nILoveCandy' /etc/pacman.conf
    sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf

    # Refresh package databases
    pacman -Syy

    local base_packages=(
        # Core System
        base base-devel
        linux-firmware sof-firmware
        linux linux-headers
        linux-zen linux-zen-headers

        # CPU & GPU Drivers
        amd-ucode mesa-vdpau
        libva-mesa-driver libva-utils mesa lib32-mesa
        vulkan-radeon lib32-vulkan-radeon vulkan-headers
        xf86-video-amdgpu xf86-video-ati xf86-input-libinput
        xorg-server xorg-xinit

        # Essential System Utilities
        networkmanager grub efibootmgr
        btrfs-progs bash-completion noto-fonts
        htop vim fastfetch nodejs npm
        git xclip laptop-detect kitty
        flatpak  htop glances firewalld timeshift
        ninja gcc gdb cmake clang rsync

        # Multimedia & Bluetooth
        bluez bluez-utils
        pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber
        
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

    # Refresh package databases
    pacman -Syy --noconfirm

    echo "/swap/swapfile none swap defaults,pri=100 0 0" >> /etc/fstab

    # Create snapper configuration
    snapper -c root create-config /

    # Modify snapper configuration
    cat << SNAPCONF >> /etc/snapper/configs/root
# Custom snapshot configuration
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="5"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="12"
SNAPCONF

# Configure btrbk for backups
cat << SNAP > /etc/btrbk/btrbk.conf
volume /
  snapshot_preserve_min   2d
  snapshot_preserve      14d 10w 6m

  subvolume @
    snapshot_name        @_${HOSTNAME}_snap
  
  subvolume @home
    snapshot_name        @home_${HOSTNAME}_snap
SNAP

# Enable and start services
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer
systemctl enable --now btrbk.timer

EOF
}

# Desktop Environment GNOME
desktop_install() {
    arch-chroot /mnt /bin/bash <<'EOF'
    pacman -S --needed --noconfirm \
    gnome gnome-tweaks gnome-terminal

    # Remove gnome bloat's & enable gdm
    pacman -Rns --noconfirm \
    gnome-calendar gnome-text-editor \
    gnome-tour gnome-user-docs \
    gnome-weather gnome-music \
    epiphany yelp malcontent \
    gnome-software
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
    yay -S --noconfirm \
        telegram-desktop-bin flutter-bin \
        vesktop-bin youtube-music-bin \
        zoom visual-studio-code-bin \
        wine 

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
    -i, --install
    -s, --setup
    -h, --help
EOF
}

# Execute main function
main "$@"
