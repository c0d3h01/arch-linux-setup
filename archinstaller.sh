#!/usr/bin/env bash
# shellcheck disable=SC2129
# shellcheck disable=SC2024
# shellcheck disable=SC2162
# shellcheck disable=SC2154
set -e
set -x
#exec > >(tee -i arch_install.log) 2>&1

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

cachyos_repo_setup() {
    curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
    tar xvf cachyos-repo.tar.xz
    cd cachyos-repo
    ./cachyos-repo.sh

    mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = http://mirror.sahil.world/archlinux/$repo/os/$arch
Server = https://mirror.sahil.world/archlinux/$repo/os/$arch
EOF

    # Update package database
    pacman -Syy --noconfirm
}

# Base system installation function
install_base_system() {
    info "Installing base system..."

    # Add keys
     pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
     pacman-key --lsign-key F3B607488DB35A47

    # Install CachyOS packages
      pacman -U --noconfirm \
         'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
         'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-18-1-any.pkg.tar.zst' \
         'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-18-1-any.pkg.tar.zst' \
         'https://mirror.cachyos.org/repo/x86_64/cachyos/pacman-7.0.0.r3.gf3211df-3.1-x86_64.pkg.tar.zst'

    # Add CachyOS repositories to pacman.conf
     cat >> /etc/pacman.conf <<'CONF'
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
CONF

    mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = http://mirror.sahil.world/archlinux/$repo/os/$arch
Server = https://mirror.sahil.world/archlinux/$repo/os/$arch
EOF

    # Update package database
    pacman -Syy --noconfirm
    
    local base_packages=(
        # Core System
        base base-devel
        linux-cachyos linux-cachyos-headers # default kernel
        linux-cachyos-autofdo linux-cachyos-autofdo-headers # perf-optimized kernel
        linux-firmware

        # CPU & GPU Drivers
        amd-ucode xf86-video-amdgpu
        vulkan-radeon vulkan-tools
        libva-mesa-driver mesa-vdpau mesa
        vulkan-icd-loader libva-utils gvfs

        # Essential System Utilities
        networkmanager grub efibootmgr
        btrfs-progs bash-completion
        snapper vim fastfetch
        reflector sudo

        # System Performance
        zram-generator thermald ananicy-cpp

        # Multimedia & Bluetooth
        gstreamer-vaapi ffmpeg
        bluez bluez-utils
        pipewire pipewire-alsa pipewire-jack
        pipewire-pulse wireplumber
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

    curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
    tar xvf cachyos-repo.tar.xz
    cd cachyos-repo
    ./cachyos-repo.sh

    mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    cat > /etc/pacman.d/mirrorlist <<'EOFM'
Server = http://mirror.sahil.world/archlinux/$repo/os/$arch
Server = https://mirror.sahil.world/archlinux/$repo/os/$arch
EOFM

    # Update package database
    pacman -Syyu
    
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
    sed -i '/^# Misc options/a DisableDownloadTimeout\nILoveCandy' /etc/pacman.conf

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
# VM settings optimized
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 3
vm.dirty_bytes = 134217728
vm.page-cluster = 0
vm.dirty_background_bytes = 67108864
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 1500

# Kernel settings
kernel.nmi_watchdog = 0
kernel.unprivileged_userns_clone = 1
kernel.printk = 3 3 3 3
kernel.kptr_restrict = 2
kernel.kexec_load_disabled = 1
kernel.sched_rt_runtime_us = -1

# AMD CPU specific optimizations
kernel.sched_autogroup_enabled = 1
kernel.sched_cfs_bandwidth_slice_us = 500

# File system settings
fs.inotify.max_user_watches = 524288
fs.file-max = 2097152

# Network optimizations for desktop use
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
net.ipv4.tcp_slow_start_after_idle = 0

# IOMMU settings for AMD
kernel.perf_event_max_sample_rate = 100000
kernel.perf_cpu_time_max_percent = 25
SYS

mkdir -p /etc/ananicy.d/

cat > "/etc/ananicy.d/ananicy.conf" <<'ANA'
# More frequent checks for faster response
check_freq = 10  

# Core functionality
cgroup_load = true
type_load = true
rule_load = true

# All optimizations enabled
apply_nice = true
apply_latnice = true
apply_ionice = true
apply_sched = true
apply_oom_score_adj = true
apply_cgroup = true

# Minimal logging for better performance
loglevel = warn
log_applied_rule = false
cgroup_realtime_workaround = true
ANA

# Now let's create optimized rules
cat > "/etc/ananicy.d/00-desktop.rules" <<'RULES'
# GNOME Desktop Environment
{ "name": "gnome-shell", "type": "de", "nice": -5, "sched": "other", "ioclass": "realtime", "ionice": 1 }
{ "name": "mutter", "type": "de", "nice": -5, "sched": "other", "ioclass": "realtime", "ionice": 1 }
{ "name": "gnome-session-binary", "type": "de", "nice": -3 }

# System UI responsiveness
{ "name": "pipewire", "type": "audio", "nice": -15, "sched": "rr", "ioclass": "realtime" }
{ "name": "wireplumber", "type": "audio", "nice": -15, "sched": "rr", "ioclass": "realtime" }

# Browsers for fast web response
{ "name": "brave", "type": "browser", "nice": -3, "ioclass": "best-effort", "ionice": 5 }
{ "name": "WebContent", "type": "browser", "nice": -1, "ioclass": "best-effort", "ionice": 5 }
{ "name": "chromium", "type": "browser", "nice": -3, "ioclass": "best-effort", "ionice": 5 }

# System services
{ "name": "systemd", "type": "system", "nice": -5 }
{ "name": "systemd-*", "type": "system", "nice": -5 }
{ "name": "dbus-daemon", "type": "system", "nice": -4 }

# GPU related
{ "name": "glxgears", "type": "gpu", "nice": -10 }
{ "name": "vulkan*", "type": "gpu", "nice": -10 }
{ "name": "vkBasalt", "type": "gpu", "nice": -10 }

# Video/Media
{ "name": "ffmpeg", "type": "video-transcoding", "nice": 0, "ioclass": "best-effort", "ionice": 4 }
{ "name": "gstreamer*", "type": "video-transcoding", "nice": 0, "ioclass": "best-effort" }

# Games and real-time applications
{ "name": "*steam*", "type": "game", "nice": -5, "ioclass": "best-effort", "ionice": 3 }
{ "name": "gamescope", "type": "game", "nice": -5, "ioclass": "best-effort", "ionice": 3 }
{ "name": "mangohud", "type": "game", "nice": -5 }

# Background tasks - lower priority
{ "name": "packagekitd", "type": "package-manager", "nice": 10, "ioclass": "idle" }
{ "name": "pacman", "type": "package-manager", "nice": 10, "ioclass": "best-effort", "ionice": 7 }
{ "name": "yay", "type": "package-manager", "nice": 10, "ioclass": "best-effort", "ionice": 7 }
{ "name": "paru", "type": "package-manager", "nice": 10, "ioclass": "best-effort", "ionice": 7 }
RULES

# Add schedulers types
cat > "/etc/ananicy.d/00-types.types" <<'TYPES'
# Types configuration
{ "type": "de", "nice": -5, "sched": "other", "ioclass": "best-effort", "ionice": 3 }
{ "type": "audio", "nice": -15, "sched": "rr", "ioclass": "realtime" }
{ "type": "browser", "nice": -3, "ioclass": "best-effort", "ionice": 5 }
{ "type": "system", "nice": -5 }
{ "type": "gpu", "nice": -10 }
{ "type": "game", "nice": -5, "ioclass": "best-effort", "ionice": 3 }
{ "type": "video-transcoding", "nice": 0, "ioclass": "best-effort", "ionice": 4 }
{ "type": "package-manager", "nice": 10, "ioclass": "best-effort", "ionice": 7 }
TYPES
EOF
}

desktop_install() {
    arch-chroot /mnt /bin/bash <<EOF
    # Desktop Environment GNOME
    pacman -Sy --needed --noconfirm \
        gnome gnome-tweaks \
        gnome-terminal \
        alacritty cups
        
    systemctl enable gdm
EOF
}

archinstall() {
    info "Starting Arch Linux installation script..."
    init_config

    # Main installation steps
    setup_disk
    setup_filesystems
   # setup_cachyos_repo
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
    sudo pacman -S --needed \
        nodejs npm \
        virt-manager \
        qemu-full iptables \
        libvirt edk2-ovmf \
        dnsmasq bridge-utils \
        vde2 dmidecode xclip \
        rocm-hip-sdk \
        rocm-opencl-sdk \
        python python-pip \
        python-numpy \
        python-pandas \
        python-scipy \
        python-matplotlib \
        python-scikit-learn \
        flatpak ufw-extras \
        ninja gcc gdb cmake clang

    # Configure firewall
    sudo ufw enable
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow http
    sudo ufw allow https
    sudo ufw allow 1714:1764/udp
    sudo ufw allow 1714:1764/tcp
    sudo ufw logging on
    
    # Enable services
    sudo systemctl enable docker
    sudo systemctl enable ufw

    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si

    # Install user applications via yay
    sudo yay -S --needed \
        brave-bin \
        telegram-desktop-bin \
        onlyoffice-bin \
        tor-browser-bin \
        vesktop-bin \
        zoom \
        docker-desktop \
        android-ndk \
        android-sdk \
        android-studio \
        postman-bin \
        flutter-bin \
        youtube-music-bin \
        notion-app-electron \
        zed

    # Configure Android SDK
    sudo echo "export ANDROID_HOME=\$HOME/Android/Sdk" >> "\$HOME/.bashrc"
    sudo echo "export PATH=\$PATH:\$ANDROID_HOME/tools:\$ANDROID_HOME/platform-tools" >> "\$HOME/.bashrc"
    sudo echo "export ANDROID_NDK_ROOT=/opt/android-ndk" >> "\$HOME/.bashrc"
    sudo echo "export PATH=\$PATH:\$ANDROID_NDK_ROOT" >> "\$HOME/.bashrc"
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
EOF
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
    cat <<EOF
Usage: $(basename "$0") [OPTION]

Options:
    -i, --install    Run Arch Linux installation
    -s, --setup      Setup user configuration
    -h, --help       Display this help message
EOF
}

# Execute main function
main "$@"
