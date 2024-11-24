#!/bin/bash

# ==============================================================================
# User setup Installation Script
# ==============================================================================

# User environment setup function
main() {
    # Install AUR helper
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si

    # Install development packages, utilitys
    sudo pacman -S --needed \
        nodejs npm \
        virt-manager \
        qemu-full \
        iptables \
        libvirt \
        edk2-ovmf \
        dnsmasq \
        bridge-utils \
        vde2 \
        dmidecode \
        xclip \
        rocm-hip-sdk \
        rocm-opencl-sdk \
        python-numpy \
        python-pandas \
        python-scipy \
        python-matplotlib \
        python-scikit-learn \
        ttf-dejavu \
        noto-fonts \
        noto-fonts-cjk \
        noto-fonts-emoji \
        ttf-liberation \
        ttf-fira-code \
        flatpak \
        go \
        rust \
        ninja \
        cargo

    # Install user applications via yay
    paru -S --needed \
        brave-bin \
        telegram-desktop-bin \
        onlyoffice-bin \
        tor-browser-bin \
        vesktop-bin \
        zoom \
        docker \
        docker-compose \
        android-ndk \
        android-tools \
        android-sdk \
        android-studio \
        postman-bin \
        flutter \
        youtube-music-bin \
        notion-app-electron \
        zed

    # Configure firewall
    sudo ufw enable
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow http
    sudo ufw allow https
    sudo ufw allow 1714:1764/udp
    sudo ufw allow 1714:1764/tcp
    sudo ufw logging on
    systemctl enable docker
    systemctl enable ufw

    # Configure Android SDK
    echo "export ANDROID_HOME=\$HOME/Android/Sdk" >>"/home/c0d3h01/.bashrc"
    echo "export PATH=\$PATH:\$ANDROID_HOME/tools:\$ANDROID_HOME/platform-tools" >>"/home/c0d3h01/.bashrc"
    chown c0d3h01:c0d3h01 "/home/c0d3h01/.bashrc"
    EOF
}

main "@"
