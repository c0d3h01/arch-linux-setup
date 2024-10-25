#!/bin/bash
sudo pacman -Syu --noconfirm #update
sudo pacman -S --noconfirm base-devel git wget curl
#
if ! command -v yay &>/dev/null; then
  git clone https://aur.archlinux.org/yay.git
  cd yay 
  makepkg -si --noconfirm
  cd ..
  rm -rf yay
fi;
#
yay # Update
#
#
# /etc/pacman.conf ,parrelel downloading, colour enable.
#
sudo pacman -S --noconfirm \
  neovim \
  neofetch \
  htop \
  fastfetch \
  docker \
  nodejs \
  npm \
  discord \
  libreoffice
  #
yay -S --noconfirm \
  brave-bin \
  telegram-desktop \
  github-desktop \
  visual-studio-code-bin \
  ferdium-bin \
  zoom \
  cmake \
  android-ndk \
  openjdk-src
#
sudo systemctl enable fstrim.timer

git config --global user.name "c0d3h01"
git config --global user.email "harshalsawant2004h@gmail.com"

#######################
