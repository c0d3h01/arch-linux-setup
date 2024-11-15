#!/bin/bash

# Install CachyOS repo
curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz
cd cachyos-repo
chmod 777 ./cachyos-repo.sh
sudo ./cachyos-repo.sh --remove

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
    kdeconnect
    ufw

# Remove orphaned packages
sudo pacman -Rns $(pacman -Qtdq) --noconfirm

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

sudo ufw enable
sudo systemctl enable ufw
sudo ufw allow 1714:1764/udp
sudo ufw allow 1714:1764/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw logging on
sudo ufw reload
