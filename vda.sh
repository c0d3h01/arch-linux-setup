#!/bin/bash
set -euxo pipefail

DRIVE="/dev/vda"
EFI_PART="${DRIVE}1"
ROOT_PART="${DRIVE}2"

echo "Starting Arch Linux installation..."

echo "Preparing disk partitions..."
# Clear all partition data and GPT/MBR structures
sgdisk --zap-all ${DRIVE}
sgdisk --clear ${DRIVE}
sgdisk --set-alignment=8 ${DRIVE}

# Create partitions
echo "Creating partitions..."
sgdisk --new=1:0:+2G \
       --typecode=1:ef00 \
       --change-name=1:"EFI" \
       --new=2:0:0 \
       --typecode=2:8300 \
       --change-name=2:"ROOT" \
       --attributes=2:set:2 \
       ${DRIVE}

# Verify partitions
echo "Verifying partitions..."
sgdisk --verify ${DRIVE}
partprobe ${DRIVE}

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 -n EFI ${EFI_PART}
mkfs.btrfs -f \
    -L ROOT \
    -n 32k \
    -m dup \
    ${ROOT_PART}

echo "Setting up BTRFS subvolumes..."
# Mount ROOT partition
mount ${ROOT_PART} /mnt

# Create BTRFS subvolumes
pushd /mnt
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create @cache
btrfs subvolume create @log
btrfs subvolume create @pkg
btrfs subvolume create @.snapshots
popd

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

echo "Verifying mount points..."
df -Th
btrfs subvolume list /mnt

echo "Installing base system..."
pacstrap /mnt \
        base base-devel \
        linux linux-headers linux-firmware \
        networkmanager \
        grub efibootmgr \
        neovim nano \
        virtualbox-guest-utils
        
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<'EOF'
# Basic System Configuration
# Set timezone
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "archlinux" > /etc/hostname

# Host configuration
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 archlinux.localdomain archlinux" >> /etc/hosts

# User Management
# Set root password
echo "Setting root password..."
echo "root:1991" | chpasswd

# Create user and set password
useradd -m -G wheel,video,input -s /bin/bash c0d3h01
echo "c0d3h01:1991" | chpasswd

# Configure sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Boot Configuration
# Configure GRUB
sed -i 's|GRUB_CMDLINE_LINUX_DEFAULT=".*"|GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_pstate=active amdgpu.ppfeaturemask=0xffffffff zswap.enabled=0 zram.enabled=1 zram.num_devices=1 rootflags=subvol=@ mitigations=off random.trust_cpu=on page_alloc.shuffle=1"|' /etc/default/grub
sed -i 's|GRUB_TIMEOUT=.*|GRUB_TIMEOUT=2|' /etc/default/grub

# Install bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
grub-mkconfig -o /boot/grub/grub.cfg
echo "Chroot setup completed successfully!"

# Configure pacman
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i '/\[options\]/a ILoveCandy' /etc/pacman.conf

# System update and base packages
pacman -Syu --noconfirm

echo "Installing (yay)..."
# Yay installation
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay

echo "Updating system..."
yay -Syu --noconfirm

echo "Installing regular packages..."
# Regular package installation
yay -Sy --needed --noconfirm \
    brave-bin 
    
echo "Installing packages with --nodeps flag..."
# Packages with --nodeps
yay -Sy --needed --noconfirm --nodeps \
    telegram-desktop-bin 
    
echo "Installing GNOME environment..."
# GNOME installation
pacman -Sy --needed --noconfirm \
    gnome \
    gnome-terminal 

echo "Removing orphaned packages..."
# Cleanup orphaned packages
pacman -Rns $(pacman -Qtdq) --noconfirm 2>/dev/null || true

# System Optimization
# Configure ZRAM (optimized for 8GB RAM)
cat > /etc/systemd/zram-generator.conf <<'ZRAM'
[zram0]
zram-size = 8192
compression-algorithm = zstd
max_comp_streams = 8
writeback = 0
priority = 32767
fs-type = swap
ZRAM

# System tuning parameters
cat > /etc/sysctl.d/99-system-tune.conf <<'SYSCTL'
vm.swappiness = 100
vm.vfs_cache_pressure = 50
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

dev.amdgpu.ppfeaturemask=0xffffffff
SYSCTL

# AMD-specific Configuration
# GPU settings
cat > /etc/modprobe.d/amdgpu.conf <<'AMD'
options amdgpu ppfeaturemask=0xffffffff
options amdgpu dpm=1
options amdgpu audio=1
AMD

# Power management
cat > /etc/udev/rules.d/81-powersave.rules <<'POWER'
ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="auto"
POWER

# BTRFS configuration
cat > /etc/systemd/system/btrfs-scrub.service <<'SCRUB'
[Unit]
Description=BTRFS periodic scrub
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/bin/btrfs scrub start -B /
SCRUB

cat > /etc/systemd/system/btrfs-scrub.timer <<'TIMER'
[Unit]
Description=BTRFS periodic scrub timer
[Timer]
OnCalendar=monthly
Persistent=true
[Install]
WantedBy=timers.target
TIMER

echo "Enabling system services..."
# Enable system services
SERVICES=(
    "thermald"
    "power-profiles-daemon"
    "NetworkManager"
    "bluetooth"
    "gdm"
    "docker"
    "systemd-zram-setup@zram0.service"
    "fstrim.timer"
    "btrfs-scrub.timer"
)

for service in "${SERVICES[@]}"; do
    systemctl enable "$service"
done

echo "Configuring firewall..."
# Configure UFW
 ufw default deny incoming
 ufw default allow outgoing
 ufw allow ssh
 ufw allow http
 ufw allow https
# KDE Connect ports
 ufw allow 1714:1764/udp
 ufw allow 1714:1764/tcp
 ufw logging on
 ufw enable
 systemctl enable ufw

echo "Disabling file indexing..."
# Disable file indexing
if [command -v balooctl6] &> /dev/null; then
     balooctl6 disable
     balooctl6 purge
fi

# Android SDK setup for bashrc
echo 'export ANDROID_HOME=$HOME/Android/Sdk' >> ~/.bashrc
echo 'export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools' >> ~/.bashrc
echo "User setup completed successfully!"
EOF

umount -R /mnt

echo "Installation completed successfully!"
