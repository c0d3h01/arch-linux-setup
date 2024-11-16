#!/bin/bash
set -e  # Exit on error

# Check if running as regular user
if [ "$(id -u)" = "0" ]; then
   echo "This script must be run as a regular user, not root" >&2
   exit 1
fi

echo "Installing CachyOS repository..."
# Install CachyOS repo
cd /tmp
curl -L https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xf cachyos-repo.tar.xz
cd cachyos-repo
chmod +x ./cachyos-repo.sh
sudo ./cachyos-repo.sh --remove

echo "Installing (yay)..."
# Yay installation
cd /tmp
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

# Docker post installation
sudo usermod -aG docker $USER

# Create necessary directories for Android development
echo "Setting up Android development environment..."
mkdir -p ~/Android/Sdk

echo "Installation completed successfully!"
