#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# ==============================================================================
# Arch Linux Installation Script
# Author: c0d3h01
# Description: Automated Arch Linux installation with BTRFS and AMD optimizations
# ==============================================================================

set -e

# Global variables
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

info() {
    echo "INFO" "${BLUE}$*${NC}"
}

warn() {
    echo "WARN" "${YELLOW}$*${NC}"
}

error() {
    echo "ERROR" "${RED}$*${NC}"
    exit 1
}

success() {
    echo "SUCCESS" "${GREEN}$*${NC}"
}

# ==============================================================================
# Configuration Functions
# ==============================================================================

init_config() {
    CONFIG=(
        [DRIVE]="/dev/nvme0n1"
        [HOSTNAME]="archlinux"
        [USERNAME]="c0d3h01"
        [PASSWORD]="1981"
        [TIMEZONE]="Asia/Kolkata"
        [LOCALE]="en_US.UTF-8"
        [CPU_VENDOR]="amd"
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
    echo "Preparing disk partitions..."

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
    echo "Setting up filesystems..."

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
    echo "Installing base system..."

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
    echo "Configuring system..."

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
    mkinitcpio -P
EOF
}

apply_optimizations() {
    echo "Applying system optimizations..."
    arch-chroot /mnt /bin/bash <<EOF
    cat > "/etc/systemd/zram-generator.conf" <<'ZRAMCONF'
zram-size = 8192
compression-algorithm = zstd
max-comp-streams = 8
writeback = 0
priority = 32767
device-type = swap
ZRAMCONF

    cat > "sudo micro /etc/sysctl.d/99-kernel-sched-rt.conf" <<'SYS'
# sched: RT throttling activated
kernel.sched_rt_runtime_us=-1

# The sysctl swappiness parameter determines the kernel's preference for pushing anonymous pages or page cache to disk in memory-starved situations.
# A low value causes the kernel to prefer freeing up open files (page cache), a high value causes the kernel to try to use swap space,
# and a value of 100 means IO cost is assumed to be equal.
vm.swappiness = 100

# The value controls the tendency of the kernel to reclaim the memory which is used for caching of directory and inode objects (VFS cache).
# Lowering it from the default value of 100 makes the kernel less inclined to reclaim VFS cache (do not set it to 0, this may produce out-of-memory conditions)
#vm.vfs_cache_pressure=50

# Contains, as a bytes of total available memory that contains free pages and reclaimable
# pages, the number of pages at which a process which is generating disk writes will itself start
# writing out dirty data.
vm.dirty_bytes = 268435456

# page-cluster controls the number of pages up to which consecutive pages are read in from swap in a single attempt.
# This is the swap counterpart to page cache readahead. The mentioned consecutivity is not in terms of virtual/physical addresses,
# but consecutive on swap space - that means they were swapped out together. (Default is 3)
# increase this value to 1 or 2 if you are using physical swap (1 if ssd, 2 if hdd)
vm.page-cluster = 0

# Contains, as a bytes of total available memory that contains free pages and reclaimable
# pages, the number of pages at which the background kernel flusher threads will start writing out
# dirty data.
vm.dirty_background_bytes = 134217728

# This tunable is used to define when dirty data is old enough to be eligible for writeout by the
# kernel flusher threads.  It is expressed in 100'ths of a second.  Data which has been dirty
# in-memory for longer than this interval will be written out next time a flusher thread wakes up
# (Default is 3000).
#vm.dirty_expire_centisecs = 3000

# The kernel flusher threads will periodically wake up and write old data out to disk.  This
# tunable expresses the interval between those wakeups, in 100'ths of a second (Default is 500).
vm.dirty_writeback_centisecs = 1500

# This action will speed up your boot and shutdown, because one less module is loaded. Additionally disabling watchdog timers increases performance and lowers power consumption
# Disable NMI watchdog
kernel.nmi_watchdog = 0

# Enable the sysctl setting kernel.unprivileged_userns_clone to allow normal users to run unprivileged containers.
kernel.unprivileged_userns_clone = 1

# To hide any kernel messages from the console
kernel.printk = 3 3 3 3

# Restricting access to kernel pointers in the proc filesystem
kernel.kptr_restrict = 2

# Disable Kexec, which allows replacing the current running kernel.
kernel.kexec_load_disabled = 1

# Increase the maximum connections
# The upper limit on how many connections the kernel will accept (default 4096 since kernel version 5.6):
net.core.somaxconn = 8192

# Enable TCP Fast Open
# TCP Fast Open is an extension to the transmission control protocol (TCP) that helps reduce network latency
# by enabling data to be exchanged during the sender’s initial TCP SYN [3].
# Using the value 3 instead of the default 1 allows TCP Fast Open for both incoming and outgoing connections:
net.ipv4.tcp_fastopen = 3

# Enable BBR3
# The BBR3 congestion control algorithm can help achieve higher bandwidths and lower latencies for internet traffic
net.ipv4.tcp_congestion_control = bbr

# TCP SYN cookie protection
# Helps protect against SYN flood attacks. Only kicks in when net.ipv4.tcp_max_syn_backlog is reached:
net.ipv4.tcp_syncookies = 1

# TCP Enable ECN Negotiation by default
net.ipv4.tcp_ecn = 1

# TCP Reduce performance spikes
# Refer https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_for_real_time/7/html/tuning_guide/reduce_tcp_performance_spikes
net.ipv4.tcp_timestamps = 0

# Increase netdev receive queue
# May help prevent losing packets
net.core.netdev_max_backlog = 16384

# Disable TCP slow start after idle
# Helps kill persistent single connection performance
net.ipv4.tcp_slow_start_after_idle = 0

# Protect against tcp time-wait assassination hazards, drop RST packets for sockets in the time-wait state. Not widely supported outside of Linux, but conforms to RFC:
net.ipv4.tcp_rfc1337 = 1

# Set the maximum watches on files
fs.inotify.max_user_watches = 524288

# Set size of file handles and inode cache
fs.file-max = 2097152

# Increase writeback interval  for xfs
fs.xfs.xfssyncd_centisecs = 10000

# Only experimental!
# Let Realtime tasks run as long they need
# sched: RT throttling activated
kernel.sched_rt_runtime_us=-1
SYS
EOF
}

configure_pacman() {
    echo "Configuring pacman..."
    arch-chroot /mnt /bin/bash <<EOF
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf
EOF
}

setup_user_environment() {
    echo "Setting up user environment..."
    arch-chroot /mnt /bin/bash <<EOF
    # Install base development packages
    pacman -Sy --needed --noconfirm \
        nodejs npm \
        virt-manager \
        qemu-desktop \
        libvirt \
        edk2-ovmf \
        dnsmasq \
        vde2 \
        bridge-utils \
        iptables-nft \
        dmidecode \
        xclip \
        rocm-hip-sdk \
        rocm-opencl-sdk \
        python \
        python-pip \
        python-numpy \
        python-pandas \
        python-scipy \
        python-matplotlib \
        python-scikit-learn \
        torchvision


    # Install yay
    sudo -u ${CONFIG[USERNAME]} git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    sudo -u ${CONFIG[USERNAME]} makepkg -si
    cd ..
    rm -rf ./yay-bin
    
    # Install regular packages via yay
    sudo -u ${CONFIG[USERNAME]} yay -Sy --needed --noconfirm \
        brave-bin \
        zoom \
        android-ndk \
        android-tools \
        android-sdk \
        android-studio \
        openjdk-src \
        postman-bin \
        flutter \
        youtube-music-bin \
        notion-app-electron \
        zed \
        gparted \
        filelight \
        kdeconnect \
        ufw-extras linutil-bin paru-bin fastfetch nerdfetch \
        docker \
        tor-browser-bin

    # Install packages with --nodeps
    sudo -u ${CONFIG[USERNAME]} yay -Sy --needed --noconfirm --nodeps \
        telegram-desktop-bin \
        github-desktop-bin \
        visual-studio-code-bin \
        ferdium-bin \
        vesktop-bin \
        onlyoffice-bin

    # Configure Android SDK
    echo "export ANDROID_HOME=\$HOME/Android/Sdk" >> /home/${CONFIG[USERNAME]}/.bashrc
    echo "export PATH=\$PATH:\$ANDROID_HOME/tools:\$ANDROID_HOME/platform-tools" >> /home/${CONFIG[USERNAME]}/.bashrc
    chown ${CONFIG[USERNAME]}:${CONFIG[USERNAME]} /home/${CONFIG[USERNAME]}/.bashrc
EOF
}

configure_services() {
    echo "Configuring and enabling services..."
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
    echo "Performing system cleanup..."
    arch-chroot /mnt /bin/bash <<EOF
    # Remove orphaned packages
    pacman -Rns \$(pacman -Qtdq) --noconfirm 2>/dev/null || true

    # Disable file indexing if KDE is installed
    if command -v balooctl6 &> /dev/null; then
        balooctl6 disable
        balooctl6 purge
    fi
    paru -Scc --noconfirm
    yay -Scc --noconfirm
EOF
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    echo "Starting Arch Linux installation script..."

    init_config

    # Main installation steps
    setup_disk
    setup_filesystems
    install_base_system
    configure_system
    configure_pacman
    setup_user_environment
    apply_optimizations
    configure_services
    cleanup_system

    umount -R /mnt

    success "Installation completed! You can now reboot your system."
}

# Execute main function
main "$@"
