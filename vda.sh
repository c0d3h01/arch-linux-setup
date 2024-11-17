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

echo "Installing CachyOS repo..."
cd /tmp
curl -LJO https://mirror.cachyos.org/cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz
cd cachyos-repo
chmod +x cachyos-repo.sh
./cachyos-repo.sh
cd ..
rm -rf cachyos-repo.tar.xz cachyos-repo

# Configure pacman
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i '/\[options\]/a ILoveCandy' /etc/pacman.conf

# System update and base packages
pacman -Syyu --noconfirm

echo "Installing yay..."
# Switch to regular user for yay installation
su - c0d3h01 <<'YAYEOF'
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay

echo "Installing regular packages..."
yay -S --needed --noconfirm \
    brave-bin \
    ufw
    
echo "Installing packages with --nodeps flag..."
yay -S --needed --noconfirm --nodeps \
    telegram-desktop-bin 
YAYEOF

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

cat > usr/lib/udev/rules.d/30-zram.rules <<'ZCONF'
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
ZCONF

cat > usr/lib/udev/rules.d/60-ioschedulers.rules <<'IOSHED'
# NVMe SSD
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", \
    ATTR{queue/scheduler}="none"
IOSHED

# System tuning parameters
cat > /etc/sysctl.d/99-system-tune.conf <<'SYSCTL'
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
