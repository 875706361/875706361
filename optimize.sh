#!/bin/bash

# 函数：检查内核版本
check_kernel_version() {
    local required_version="4.9"
    local current_version=$(uname -r | cut -d'.' -f1-2)
    if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo "错误：当前内核版本 $current_version 不支持 BBR。请升级到 4.9 或更高版本。"
        exit 1
    else
        echo "内核版本 $current_version 支持 BBR，继续执行..."
    fi
}

# 函数：安装必要软件
install_necessary_software() {
    if ! command -v sysctl &> /dev/null; then
        echo "sysctl 未安装，正在尝试安装..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y procps
        elif command -v yum &> /dev/null; then
            sudo yum install -y procps-ng
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y procps-ng
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm procps-ng
        else
            echo "错误：无法确定包管理器，请手动安装 procps 或 procps-ng。"
            exit 1
        fi
    fi
    if ! command -v cpufreq-info &> /dev/null; then
        echo "cpufrequtils 未安装，正在尝试安装..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y cpufrequtils
        elif command -v yum &> /dev/null; then
            sudo yum install -y cpufrequtils
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y cpufrequtils
        else
            echo "错误：无法确定包管理器，请手动安装 cpufrequtils。"
            exit 1
        fi
    fi
}

# 函数：永久开启 BBR
enable_bbr() {
    echo "正在永久开启 BBR..."
    sudo sysctl -w net.core.default_qdisc=fq
    sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
    grep -q "net.core.default_qdisc" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
    if ! lsmod | grep -q tcp_bbr; then
        sudo modprobe tcp_bbr
        grep -q "tcp_bbr" /etc/modules || echo "tcp_bbr" | sudo tee -a /etc/modules
    fi
    echo "BBR 已永久开启。"
}

# 函数：设置性能模式
set_performance_mode() {
    echo "正在设置性能模式..."
    # 设置 CPU 调速器为 performance
    if [ -f /etc/default/cpufrequtils ]; then
        sudo sed -i 's/^GOVERNOR=.*/GOVERNOR="performance"/' /etc/default/cpufrequtils || echo 'GOVERNOR="performance"' | sudo tee -a /etc/default/cpufrequtils
    else
        echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
    fi
    cat <<EOF | sudo tee /etc/systemd/system/cpu-performance.service
[Unit]
Description=Set CPU governor to performance

[Service]
Type=oneshot
ExecStart=/usr/bin/cpufreq-set -r -g performance

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable cpu-performance.service
    sudo systemctl start cpu-performance.service
    # 设置 I/O 调度器为 deadline
    if [ -f /etc/default/grub ]; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX="[^"]*/& elevator=deadline/' /etc/default/grub
        if command -v update-grub &> /dev/null; then
            sudo update-grub
        elif command -v grub2-mkconfig &> /dev/null; then
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
    fi
    # 设置 swappiness
    sudo sysctl -w vm.swappiness=10
    grep -q "vm.swappiness" /etc/sysctl.conf || echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
    echo "性能模式已设置并持久化。"
}

# 函数：安装所有优化
install_optimization() {
    check_kernel_version
    install_necessary_software
    enable_bbr
    set_performance_mode
    echo "所有优化已安装并设置为永久生效，重启后生效。"
}

# 函数：查看当前优化设置
view_settings() {
    echo "当前优化设置如下："
    echo "1. TCP 拥塞控制算法："
    sysctl net.ipv4.tcp_congestion_control || echo "未设置"
    echo "2. 默认队列规则 (default_qdisc)："
    sysctl net.core.default_qdisc || echo "未设置"
    echo "3. BBR 模块状态："
    lsmod | grep -q tcp_bbr && echo "已加载" || echo "未加载"
    echo "4. CPU 调速器："
    cpufreq-info -p || echo "无法检测"
    echo "5. I/O 调度器（示例磁盘 sda）："
    cat /sys/block/sda/queue/scheduler 2>/dev/null || echo "无法检测"
    echo "6. Swappiness："
    sysctl vm.swappiness || echo "未设置"
}

# 函数：删除所有优化
remove_optimization() {
    echo "正在删除所有优化..."
    # 关闭 BBR
    sudo sysctl -w net.ipv4.tcp_congestion_control=cubic
    sudo sysctl -w net.core.default_qdisc=pfifo_fast
    sudo sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sudo sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sudo sysctl -p
    sudo sed -i '/tcp_bbr/d' /etc/modules
    # 恢复 CPU 调速器
    sudo systemctl disable cpu-performance.service
    sudo rm -f /etc/systemd/system/cpu-performance.service
    sudo systemctl daemon-reload
    sudo sed -i '/GOVERNOR/d' /etc/default/cpufrequtils
    # 恢复 I/O 调度器
    if [ -f /etc/default/grub ]; then
        sudo sed -i 's/ elevator=deadline//' /etc/default/grub
        if command -v update-grub &> /dev/null; then
            sudo update-grub
        elif command -v grub2-mkconfig &> /dev/null; then
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
    fi
    # 恢复 swappiness
    sudo sysctl -w vm.swappiness=60
    sudo sed -i '/vm.swappiness/d' /etc/sysctl.conf
    sudo sysctl -p
    echo "所有优化已删除，恢复为默认设置，重启后生效。"
}

# 主菜单
while true; do
    echo ""
    echo "===== Linux 系统自动调优脚本 ====="
    echo "1. 安装优化（开启 BBR 和性能模式）"
    echo "2. 查看优化设置"
    echo "3. 删除优化（恢复默认设置）"
    echo "4. 退出"
    read -p "请输入选项 (1-4): " choice
    case $choice in
        1)
            install_optimization
            ;;
        2)
            view_settings
            ;;
        3)
            remove_optimization
            ;;
        4)
            echo "退出脚本，感谢使用！"
            exit 0
            ;;
        *)
            echo "无效选项，请输入 1-4 之间的数字。"
            ;;
    esac
done