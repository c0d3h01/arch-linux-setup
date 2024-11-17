#!/bin/bash
set -euxo pipefail

DRIVE="/dev/nvme0n1"
EFI_PART="${DRIVE}p1"
ROOT_PART="${DRIVE}p2"

# Function to handle errors
error_handler() {
    echo "An error occurred on line $1"
    exit 1
}
trap 'error_handler ${LINENO}' ERR

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
#mount -o ${MOUNT_OPTS},subvol=@var ${ROOT_PART} /mnt/var
mount -o ${MOUNT_OPTS},subvol=@log ${ROOT_PART} /mnt/var/log
mount -o ${MOUNT_OPTS},subvol=@pkg ${ROOT_PART} /mnt/var/cache/pacman/pkg
mount -o ${MOUNT_OPTS},subvol=@.snapshots ${ROOT_PART} /mnt/.snapshots

# Mount EFI partition
mount ${EFI_PART} /mnt/boot/efi

echo "Verifying mount points..."
df -Th
btrfs subvolume list /mnt

echo "Installing base system..."
# Install base system and AMD-specific packages
    pacstrap /mnt \
        base base-devel \
        linux linux-headers linux-firmware \
        btrfs-progs \
        amd-ucode \
        xf86-video-amdgpu \
        vulkan-radeon \
        libva-mesa-driver \
        mesa-vdpau \
        mesa \
        vulkan-icd-loader \
        vulkan-tools \
        libva-utils \
        vdpauinfo \
        radeontop \
        networkmanager \
        grub efibootmgr \
        neovim glances git \
        gcc gdb cmake make \
        python python-pip \
        nodejs npm \
        git-lfs \
        zram-generator \
        power-profiles-daemon \
        thermald \
        bluez bluez-utils \
        gamemode \
        corectrl \
        acpid \
        lm_sensors \
        nvme-cli \
        powertop \
        s-tui \
        gstreamer-vaapi \
        ffmpeg

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

cat > /mnt/chroot-setup.sh <<'CHROOT_EOF'
#!/bin/bash
set -euxo pipefail
echo "Chroot setup starting"

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
CHROOT_EOF

cat > /mnt/user-setup.sh <<'USER_EOF'
#!/bin/bash
set -euxo pipefail

# Configure pacman
sudo sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
sudo sed -i '/\[options\]/a ILoveCandy' /etc/pacman.conf

echo "Installing CachyOS repository..."
# Install CachyOS repo
curl -L https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xf ./cachyos-repo.tar.xz
cd cachyos-repo
chmod +x ./cachyos-repo.sh
sudo ./cachyos-repo.sh --noconfirm
cd ..

# System update and base packages
sudo pacman -Syu --noconfirm

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
    filelight \
    kdeconnect \
    ufw \
    docker

echo "Installing packages with --nodeps flag..."
# Packages with --nodeps
yay -S --needed --noconfirm --nodeps \
    telegram-desktop-bin \
    github-desktop-bin \
    visual-studio-code-bin \
    ferdium-bin \
    vesktop-bin \
    onlyoffice-bin

echo "Installing GNOME environment..."
# GNOME installation
sudo pacman -S --needed --noconfirm \
    gnome \
    gnome-terminal \
    cachyos-gnome-settings

echo "Removing orphaned packages..."
# Cleanup orphaned packages
sudo pacman -Rns $(pacman -Qtdq) --noconfirm 2>/dev/null || true

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
# The sysctl swappiness parameter determines the kernel's preference for pushing anonymous pages or page cache to disk in memory-starved situations.
# A low value causes the kernel to prefer freeing up open files (page cache), a high value causes the kernel to try to use swap space,
# and a value of 100 means IO cost is assumed to be equal.
vm.swappiness = 100

# The value controls the tendency of the kernel to reclaim the memory which is used for caching of directory and inode objects (VFS cache).
# Lowering it from the default value of 100 makes the kernel less inclined to reclaim VFS cache (do not set it to 0, this may produce out-of-memory conditions)
vm.vfs_cache_pressure=50

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
vm.dirty_expire_centisecs = 3000

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

# Enable services
systemctl enable btrfs-scrub.timer

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
)

for service in "${SERVICES[@]}"; do
    sudo systemctl enable "$service"
done

echo "Configuring firewall..."
# Configure UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
# KDE Connect ports
sudo ufw allow 1714:1764/udp
sudo ufw allow 1714:1764/tcp
sudo ufw logging on
sudo ufw enable
sudo systemctl enable ufw

echo "Disabling file indexing..."
# Disable file indexing
if command -v balooctl6 &> /dev/null; then
    sudo balooctl6 disable
    sudo balooctl6 purge
fi

# Android SDK setup for bashrc
echo 'export ANDROID_HOME=$HOME/Android/Sdk' >> ~/.bashrc
echo 'export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools' >> ~/.bashrc
echo "User setup completed successfully!"
USER_EOF

# Create a wrapper script to run the user setup as c0d3h01
cat > /mnt/run-user-setup.sh <<'WRAPPER_EOF'
#!/bin/bash

# Enable debug mode
set -euxo pipefail

# Export terminal type
export TERM=linux

# Change to user's home directory
cd /home/c0d3h01 || exit 1

# Execute user setup with proper environment
TERM=linux
sudo -u c0d3h01 bash -c 'cd /home/c0d3h01 && ./user-setup.sh'

WRAPPER_EOF

# Make the scripts executable
chmod +x /mnt/chroot-setup.sh
chmod +x /mnt/run-user-setup.sh
chmod +x /mnt/user-setup.sh

# Create necessary directories and fix permissions
mkdir -p /mnt/home/c0d3h01
chown -R 1000:1000 /mnt/home/c0d3h01
cp /mnt/user-setup.sh /mnt/home/c0d3h01/
chown 1000:1000 /mnt/home/c0d3h01/user-setup.sh

# Execute the chroot scripts in sequence with proper logging
echo "Entering chroot and executing setup..."
arch-chroot /mnt /chroot-setup.sh 2>&1 | tee /mnt/chroot-setup.log

echo "Executing user setup in chroot..."
arch-chroot /mnt bash -c 'mount -t devpts devpts /dev/pts && /run-user-setup.sh' 2>&1 | tee /mnt/user-setup.log

umount -R /mnt

echo "Installation completed successfully!"
