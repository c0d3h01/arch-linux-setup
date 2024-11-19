#!/usr/bin/env bash
set -eu

# Configure pacman  #
sudo sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf

echo "Installing CachyOS repository..."
# Install CachyOS repo
curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz
cd cachyos-repo
chmod +x ./cachyos-repo.sh
sudo ./cachyos-repo.sh

# System update and base packages & VM install.
sudo pacman -Sy --needed --noconfirm \
    cachyos-rate-mirrors \
    virt-manager \
    qemu-desktop \
    libvirt \
    edk2-ovmf \
    dnsmasq \
    vde2 \
    bridge-utils \
    iptables-nft \
    dmidecode

# Update Arch mirrors
rate-mirrors arch
sudo cachyos-rate-mirrors

echo "Installing (yay)..."
# Yay installation
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
cd ..
rm -rf yay

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

# Create necessary directories for Android development
echo "Setting up Android development environment..."
mkdir -p ~/Android/Sdk

echo "Installation completed successfully!"
