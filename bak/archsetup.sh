#!/bin/bash

#######################
# Update Arch mirrors #
#######################
rate-mirrors arch

####################################
# System update and base packages  #
####################################
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git wget curl

###############
# Install yay #
###############
if [! command -v yay &>/dev/null]; then
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
fi

###############
# Update AUR  #
###############
yay -Syu --noconfirm

#####################
# Configure pacman  #
#####################
sudo sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
sudo sed -i '/\[options\]/a ILoveCandy' /etc/pacman.conf

####################
# Cashyos repo add #
####################
wget https://mirror.cachyos.org/cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz
cd cachyos-repo
sudo ./cachyos-repo.sh
sudo cachyos-rate-mirrors

#################
# AUR packages  #
#################
yay -S --needed --noconfirm \
    brave-bin \
    zoom \
    cmake \
    android-ndk \
    android-sdk \
    openjdk-src \
    postman-bin \
    youtube-music-bin \
    notion-app-electron \
    zed \
    gparted \
    pipewire-pulse \
    pipewire-jack \
    lib32-pipewire-jack \
    alsa-plugins \
    alsa-firmware \
    sof-firmware \
    alsa-card-profiles \
    filelight \
    ufw-extras \
    ananicy-cpp \
    irqbalance \
    memavaild \
    nohang \
    preload \
    prelockd

##############################################
# First remove orphaned packages if needed   #
##############################################
sudo pacman -Rns $(pacman -Qtdq) --noconfirm

#################################################################################
# Install all packages at once with --nodeps flag to avoid debug dependencies   #
#################################################################################
yay -S --needed --noconfirm --nodeps \
    telegram-desktop-bin \
    github-desktop-bin \
    visual-studio-code-bin \
    ferdium-bin \
    vesktop-bin \
    onlyoffice-bin

######################################################
# Clean up orphaned packages after all installations #
######################################################
sudo pacman -Rns $(pacman -Qtdq) --noconfirm

##############################
# Install official packages  #
##############################
sudo pacman -S --needed --noconfirm \
    neovim \
    htop \
    glances \
    #fish \
    nerdfetch \
    docker \
    nodejs \
    npm \
    #spectacle
    #udisks2 \
    gvfs \
    gvfs-mtp \
    kdeconnect

###################
# Enable services #
###################
sudo systemctl enable fstrim.timer
sudo systemctl enable docker.service

#####################
# Disable indexing  #
#####################
sudo balooctl6 disable
sudo balooctl6 purge

#######################
# Enable bluetooth    #
#######################
sudo systemctl start bluetooth.service
sudo systemctl enable bluetooth.service

####################################
# Perf tweaks services enable/start #
####################################

# Disable the systemd-oomd service (Out Of Memory Daemon)
sudo systemctl disable systemd-oomd.service
sudo systemctl stop systemd-oomd.service

# Enable and start performance optimization services
# Preload - Adaptive readahead daemon
sudo systemctl enable preload.service
sudo systemctl start preload.service

# Optional performance services (uncomment if installed)
# Ananicy-CPP - Auto nice daemon in C++
sudo systemctl enable ananicy-cpp.service
sudo systemctl start ananicy-cpp.service

# IRQ Balance - Distribute hardware interrupts across processors
sudo systemctl enable irqbalance.service
sudo systemctl start irqbalance.service

# Memory management services (uncomment if installed)
sudo systemctl enable memavaild.service
sudo systemctl start memavaild.service

# Low memory handler
sudo systemctl enable nohang.service
sudo systemctl start nohang.service

# Process resource usage daemon
sudo systemctl enable uresourced.service
sudo systemctl start uresourced.service

# Prelockd - Memory locking daemon
sudo systemctl enable prelockd.service
sudo systemctl start prelockd.service

################
# UFW Services #
################
sudo systemctl enable ufw.service
sudo systemctl start ufw.service
sudo ufw enable

# No-hang Zram config
sudo sed -i 's|zram_checking_enabled = False|zram_checking_enabled = True|g' /etc/nohang/nohang.conf

########################
# Git configuration    #
########################
git config --global user.name "c0d3h01"
git config --global user.email "harshalsawant2004h@gmail.com"

###############################################################
# Firewall configuration to avoid kconnect from restrictions. #
###############################################################
sudo ufw allow 1714:1764/udp
sudo ufw allow 1714:1764/tcp
sudo ufw reload

#######################
# Clean package cache #
#######################
yay -Scc --noconfirm
sudo pacman -Scc --noconfirm
paru -Syyu --noconfirm

###########################
sudo pacman -S gnome --noconfirm
sudo systemctl enable gdm
###########################

###########################
# Start Gnome envirnment
###########################
sudo systemctl start gdm
