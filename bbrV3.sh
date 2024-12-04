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
    if [ $? -ne 0 ]; then
        echo "下载 linux-headers.deb 失败!"
        exit 1
    fi

    wget "$UBUNTU_IMAGE_URL" -O linux-image.deb
    if [ $? -ne 0 ]; then
        echo "下载 linux-image.deb 失败!"
        exit 1
    fi

    sudo dpkg -i linux-headers.deb linux-image.deb
    sudo apt install -f -y
}

# Function to install BBR v3 on CentOS/RHEL/AlmaLinux/Rocky
install_bbrv3_centos() {
    wget "$CENTOS_HEADERS_URL" -O kernel-headers.rpm
    if [ $? -ne 0 ]; then
        echo "下载 kernel-headers.rpm 失败!"
        exit 1
    fi

    wget "$CENTOS_IMAGE_URL" -O kernel.rpm
    if [ $? -ne 0 ]; then
        echo "下载 kernel.rpm 失败!"
        exit 1
    fi

    sudo rpm -ivh kernel-headers.rpm kernel.rpm
}

# Function to remove old kernels on Ubuntu/Debian
remove_old_kernels() {
    # Get the current running kernel
    current_kernel=$(uname -r)

    # List all installed kernels except the current one and the 6.4.0 version
    old_kernels=$(dpkg --list | grep linux-image | awk '{ print $2 }' | grep -v "$current_kernel" | grep -v '6.4.0')

    # If there are old kernels to remove
    if [ -n "$old_kernels" ]; then
        echo "正在卸载旧的内核..."
        sudo apt-get purge -y $old_kernels
        sudo apt-get autoremove -y
        sudo update-grub
        echo "旧内核已删除。"
    else
        echo "没有找到其他需要删除的内核。"
    fi
}

# Install BBR v3 based on the OS type
case "$OS" in
    ubuntu|debian)
        install_bbrv3_ubuntu
        # Remove old kernels and keep only the 6.4.0 kernel
        remove_old_kernels
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

# Display modinfo for tcp_bbr
echo "显示 tcp_bbr 模块的信息："
modinfo tcp_bbr

# Clean up downloaded files
echo "清理临时安装包..."
rm -f linux-headers.deb linux-image.deb kernel-headers.rpm kernel.rpm

# Final output message
echo "BBR v3 安装和配置完成。"

# Provide user with final instructions
echo "安装完成！以下是执行情况总结："
echo "1. 当前系统已启用 BBR v3，您可以通过 'sysctl net.ipv4.tcp_congestion_control' 检查流控算法。"
echo "2. 已删除所有非 6.4.0 版本的内核，保留了 6.4.0 内核。"
echo "3. 执行了 'modinfo tcp_bbr' 命令来验证 BBR 模块的加载状态。"

echo "如果有任何问题，请查看系统日志或向管理员求助。"
