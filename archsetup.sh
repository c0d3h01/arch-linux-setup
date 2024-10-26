#!/bin/bash
set -e
set -o pipefail

# System update and base packages
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git

# Install yay
if ! command -v yay &>/dev/null; then
    git clone https://aur.archlinux.org/yay.git
    cd yay 
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
fi

# Update AUR
yay -Syu --noconfirm

# Configure pacman
sudo sed -i '/\[options\]/a ParallelDownloads = 5' /etc/pacman.conf
sudo sed -i '/\[options\]/a Color' /etc/pacman.conf

# Remove conflicts and install AUR packages
yay -S --needed --noconfirm \
    brave-bin \
    telegram-desktop \
    github-desktop \
    visual-studio-code-bin \
    ferdium-bin \
    zoom \
    cmake \
    android-ndk \
    openjdk-src

# Install official packages
sudo pacman -S --needed --noconfirm \
    neovim \
    neofetch \
    htop \
    fastfetch \
    docker \
    nodejs \
    npm \
    discord \
    libreoffice

# Enable services
sudo systemctl enable fstrim.timer
sudo systemctl enable docker.service

# Git configuration
git config --global user.name "c0d3h01"
git config --global user.email "harshalsawant2004h@gmail.com"

# Clean package cache
yay -Sc --noconfirm
