#!/bin/bash

# Determine the OS type
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法确定操作系统类型。"
    exit 1
fi

# Set URLs for download
UBUNTU_HEADERS_URL="https://github.com/Zxilly/bbr-v3-pkg/releases/download/2024-03-07-190234/linux-headers-6.4.0-bbrv3_6.4.0-g7542cc7c41c0-1_amd64.deb"
UBUNTU_IMAGE_URL="https://github.com/Zxilly/bbr-v3-pkg/releases/download/2024-03-07-190234/linux-image-6.4.0-bbrv3_6.4.0-g7542cc7c41c0-1_amd64.deb"
CENTOS_HEADERS_URL="https://github.com/Zxilly/bbr-v3-pkg/releases/download/2024-03-07-190234/kernel-headers-6.4.0_bbrv3-1.x86_64.rpm"
CENTOS_IMAGE_URL="https://github.com/Zxilly/bbr-v3-pkg/releases/download/2024-03-07-190234/kernel-devel-6.4.0_bbrv3-1.x86_64.rpm"

# Function to install BBR v3 on Ubuntu/Debian
install_bbrv3_ubuntu() {
    wget "$UBUNTU_HEADERS_URL" -O linux-headers.deb
    wget "$UBUNTU_IMAGE_URL" -O linux-image.deb
    sudo dpkg -i linux-headers.deb linux-image.deb
    sudo apt install -f
}

# Function to install BBR v3 on CentOS/RHEL/AlmaLinux/Rocky
install_bbrv3_centos() {
    wget "$CENTOS_HEADERS_URL" -O kernel-headers.rpm
    wget "$CENTOS_IMAGE_URL" -O kernel.rpm
    sudo rpm -ivh kernel-headers.rpm kernel.rpm
}

# Install BBR v3 based on the OS type
case "$OS" in
    ubuntu|debian)
        install_bbrv3_ubuntu
        ;;
    centos|rhel|almalinux|rocky)
        install_bbrv3_centos
        ;;
    *)
        echo "不支持的操作系统类型：$OS"
        exit 1
        ;;
esac

# Enable BBR v3
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Display the current TCP congestion control algorithm
echo "当前的TCP流控算法："
sysctl net.ipv4.tcp_congestion_control

# Display available TCP congestion control algorithms
echo "可用的TCP流控算法："
sysctl net.ipv4.tcp_available_congestion_control

echo "BBR v3 安装和配置完成。"

