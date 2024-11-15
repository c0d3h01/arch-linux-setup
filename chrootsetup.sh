#!/bin/bash

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
echo "root:password"
passwd

# Create user
useradd -m -G wheel,video,input -s /bin/bash c0d3h01
echo "c0d3h01:password"
passwd c0d3h01

# Add user to sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Configure GRUB for AMD
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_pstate=active amdgpu.ppfeaturemask=0xffffffff zram.enabled=1 zram.num_devices=1 rootflags=subvol=@ mitigations=off"/' /etc/default/grub
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/' /etc/default/grub

# Install and configure bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCH
grub-mkconfig -o /boot/grub/grub.cfg

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
