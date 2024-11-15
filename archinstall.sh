#!/bin/bash

# Exit on any error
set -e

# Set system time
timedatectl set-ntp true

# Create partitions for 1.3TB drive
echo "Creating partitions..."
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart primary fat32 1MiB 2049MiB     # 2GB EFI partition
parted -s /dev/sda set 1 esp on
parted -s /dev/sda mkpart primary btrfs 2049MiB 100%     # Rest for BTRFS root

# Format partitions
mkfs.fat -F32 /dev/sda1
mkfs.btrfs -f /dev/sda2

# Mount and create BTRFS subvolumes with optimizations for SSD
mount -o ssd,noatime /dev/sda2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@log

# Unmount and remount with proper options
umount /mnt

# Create the base directory
mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@ /dev/sda2 /mnt

# Create all necessary directories before mounting
mkdir -p /mnt/{boot/efi,home,var,tmp,.snapshots}
mkdir -p /mnt/var/log  # Create the log directory explicitly

# Now mount all subvolumes
mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@home /dev/sda2 /mnt/home
mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@var /dev/sda2 /mnt/var
mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@tmp /dev/sda2 /mnt/tmp
mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@snapshots /dev/sda2 /mnt/.snapshots
mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@log /dev/sda2 /mnt/var/log
mount /dev/sda1 /mnt/boot/efi

# Mount subvolumes with optimized options for AMD Ryzen
#mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@ /dev/sda2 /mnt
#mkdir -p /mnt/{home,var,tmp,.snapshots,var/log,boot/efi}
#mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@home /dev/sda2 /mnt/home
#mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@var /dev/sda2 /mnt/var
#mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@tmp /dev/sda2 /mnt/tmp
#mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@snapshots /dev/sda2 /mnt/.snapshots
#mount -o noatime,compress=zstd:2,space_cache=v2,ssd,discard=async,autodefrag,subvol=@log /dev/sda2 /mnt/var/log
#mount /dev/sda1 /mnt/boot/efi

# Install base system and AMD-specific packages
pacstrap /mnt base base-devel linux-cachyos linux-cachyos-headers linux-firmware \
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
    lib32-mesa \
    lib32-vulkan-radeon \
    gamemode \
    corectrl

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot and configure system
arch-chroot /mnt /bin/bash <<EOF
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
# A low value causes the kernel to prefer freeing up open files (page cache), a high value causes the kernel to try to use swap space,
# and a value of 100 means IO cost is assumed to be equal.
vm.swappiness = 180

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

# AMD-specific
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
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers #EDITOR:nano visudo

# Configure GRUB for AMD
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_pstate=active amdgpu.ppfeaturemask=0xffffffff zram.enabled=1 zram.num_devices=1 rootflags=subvol=@ mitigations=off"/' /etc/default/grub
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/' /etc/default/grub

# Install and configure bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
grub-mkconfig -o /boot/grub/grub.cfg

# Enable AMD-specific services
systemctl enable thermald
systemctl enable power-profiles-daemon
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable gdm
systemctl enable docker
systemctl enable systemd-zram-setup@zram0.service
systemctl enable fstrim.timer

# Disable file indexing.
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
    youtube-music-bin \ #Music is priority ;)
    notion-app-electron \
    zed \
    gparted \
    filelight

# First remove orphaned packages if needed   #
sudo pacman -Rns $(pacman -Qtdq) --noconfirm

# Cachyos optimized repo best combination with arch ;)
curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz
cd cachyos-repo
sudo ./cachyos-repo.sh --remove

yay -S --needed --noconfirm \
    ufw \
    kdeconnect 

# Install all packages at once with --nodeps flag to avoid debug dependencies   #
yay -S --needed --noconfirm --nodeps \
    telegram-desktop-bin \
    github-desktop-bin \
    visual-studio-code-bin \
    ferdium-bin \
    vesktop-bin \
    onlyoffice-bin

# Envirnment installation (GNOME).
sudo pacman -S gnome gnome-terminal cachyos-gnome-settings --noconfirm

# Enable UFW service
sudo systemctl enable ufw

EOF # END arch-chroot eof here.

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
