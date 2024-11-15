#!/bin/bash

# Define drive and mount points
DRIVE="/dev/nvme0n1"
EFI_PART="${DRIVE}p1"
ROOT_PART="${DRIVE}p2"

# Clear all partition data and GPT/MBR structures
sgdisk --zap-all ${DRIVE}
sgdisk --clear ${DRIVE}

# Set optimal alignment for NVMe performance
sgdisk --set-alignment=8 ${DRIVE}

# Create partitions
sgdisk --new=1:0:+2G \
       --typecode=1:ef00 \
       --change-name=1:"EFI" \
       --new=2:0:0 \
       --typecode=2:8300 \
       --change-name=2:"ROOT" \
       --attributes=2:set:2 \
       ${DRIVE}
       
# Verify partitions
sgdisk --verify ${DRIVE}
partprobe ${DRIVE}

# Format partitions
mkfs.fat -F32 -n EFI ${EFI_PART}

# Format BTRFS with optimal settings for NVMe
mkfs.btrfs -f \
    -L ROOT \
    -n 32k \
    -m dup \
    ${ROOT_PART}

# Mount ROOT partition
mount ${ROOT_PART} /mnt

# Create BTRFS subvolumes
cd /mnt
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create @var
btrfs subvolume create @log
btrfs subvolume create @pkg
btrfs subvolume create @.snapshots

# Unmount and remount with subvolumes
cd /
umount /mnt

# Mount subvolumes with optimal options
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@ ${ROOT_PART} /mnt
mkdir -p /mnt/{home,var,var/log,var/cache/pacman/pkg,.snapshots,boot/efi}
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@home ${ROOT_PART} /mnt/home
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@var ${ROOT_PART} /mnt/var
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@log ${ROOT_PART} /mnt/var/log
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@pkg ${ROOT_PART} /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd:1,space_cache=v2,commit=120,subvol=@.snapshots ${ROOT_PART} /mnt/.snapshots

# Mount EFI partition
mount ${EFI_PART} /mnt/boot/efi

# Verify mounts
df -Th
btrfs subvolume list /mnt

# Install base system and AMD-specific packages
pacstrap -i /mnt base base-devel linux linux-headers linux-firmware \
    amd-ucode \
    networkmanager \
    grub efibootmgr \
    neovim vim htop glances git \
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
    #lib32-mesa \
    #lib32-vulkan-radeon \
    gamemode \
    corectrl

# Chroot and configure system
arch-chroot /mnt <<EOF
# Set timezone
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "dell-inspiron" > /etc/hostname

# Configure ZRAM (optimized for 8GB RAM)
cat > /etc/systemd/zram-generator.conf <<ZRAM
[zram0]
zram-size = 8192
compression-algorithm = zstd
max_comp_streams = 8
writeback = 0
priority = 32767
fs-type = swap
ZRAM

# AMD-specific kernel parameters and optimizations
cat > /etc/sysctl.d/99-system-tune.conf <<SYSCTL
# The sysctl swappiness parameter determines the kernel's preference for pushing anonymous pages or page cache to disk in memory-starved situations.
vm.swappiness = 180
vm.vfs_cache_pressure=50
vm.dirty_bytes = 268435456
vm.page-cluster = 0
vm.dirty_background_bytes = 134217728
vm.dirty_writeback_centisecs = 1500
kernel.nmi_watchdog = 0
kernel.unprivileged_userns_clone = 1
kernel.printk = 3 3 3 3
kernel.kptr_restrict = 2
kernel.kexec_load_disabled = 1
net.core.somaxconn = 8192
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_timestamps = 0
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_rfc1337 = 1
fs.inotify.max_user_watches = 524288
fs.file-max = 2097152
fs.xfs.xfssyncd_centisecs = 10000
kernel.sched_rt_runtime_us=-1
dev.amdgpu.ppfeaturemask=0xffffffff
SYSCTL

# Configure AMD GPU settings
cat > /etc/modprobe.d/amdgpu.conf <<AMD
options amdgpu ppfeaturemask=0xffffffff
options amdgpu dpm=1
options amdgpu audio=1
AMD

# Set root password
echo "Setting root password..."
echo "root:password" | chpasswd

# Create user
useradd -m -G wheel,video,input -s /bin/bash c0d3h01
echo "c0d3h01:password" | chpasswd

# Add user to sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Configure GRUB for AMD
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_pstate=active amdgpu.ppfeaturemask=0xffffffff zram.enabled=1 zram.num_devices=1 rootflags=subvol=@ mitigations=off"/' /etc/default/grub
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/' /etc/default/grub

# Install and configure bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable thermald
systemctl enable power-profiles-daemon
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable gdm
systemctl enable docker
systemctl enable systemd-zram-setup@zram0.service
systemctl enable fstrim.timer

# Disable file indexing
sudo balooctl6 disable
sudo balooctl6 purge

# Configure power management for AMD
cat > /etc/udev/rules.d/81-powersave.rules <<POWER
ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="auto"
POWER

# Configure git for user
su - c0d3h01 -c 'git config --global user.name "c0d3h01"'
su - c0d3h01 -c 'git config --global user.email "harshalsawant2004h@gmail.com"'

# Configure BTRFS periodic scrub
cat > /etc/systemd/system/btrfs-scrub.service <<SCRUB
[Unit]
Description=BTRFS periodic scrub
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/btrfs scrub start -B /
SCRUB

cat > /etc/systemd/system/btrfs-scrub.timer <<TIMER
[Unit]
Description=BTRFS periodic scrub timer

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
TIMER

systemctl enable btrfs-scrub.timer

# Yay installation
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay

yay -Syu --noconfirm

yay -S --needed --noconfirm \
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
    filelight

# Remove orphaned packages
sudo pacman -Rns $(pacman -Qtdq) --noconfirm

# Install CachyOS repo
curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz
cd cachyos-repo
sudo ./cachyos-repo.sh --remove

yay -S --needed --noconfirm \
    ufw \
    kdeconnect

# Install packages with --nodeps flag
yay -S --needed --noconfirm --nodeps \
    telegram-desktop-bin \
    github-desktop-bin \
    visual-studio-code-bin \
    ferdium-bin \
    vesktop-bin \
    onlyoffice-bin

# Install GNOME environment
sudo pacman -S gnome gnome-terminal cachyos-gnome-settings --noconfirm

# Enable UFW service
sudo systemctl enable ufw

EOF

# Allow kdeconect
#    sudo ufw enable
#    sudo ufw allow 1714:1764/udp
#    sudo ufw allow 1714:1764/tcp
#    sudo ufw default deny incoming
#    sudo ufw default allow outgoing
#    sudo ufw allow ssh
#    sudo ufw allow http
#    sudo ufw allow https
#    sudo ufw logging on
#    sudo ufw reload

echo "Installation completed!"
echo "Please remove installation media and reboot."
