#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 函数：显示提示信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 函数：提示是否重启
prompt_reboot() {
    while true; do
        read -p "是否立即重启系统以应用更改？(y/n): " reboot_choice
        case $reboot_choice in
            [Yy]*)
                print_info "系统即将重启..."
                sudo reboot
                break
                ;;
            [Nn]*)
                print_info "已选择不重启。请稍后手动重启以应用所有设置：sudo reboot"
                break
                ;;
            *)
                print_error "无效输入，请输入 y 或 n。"
                ;;
        esac
    done
}

# 函数：检查内核版本
check_kernel_version() {
    local required_version="4.9"
    local current_version=$(uname -r | cut -d'.' -f1-2)
    print_info "检查内核版本..."
    if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" != "$required_version" ]]; then
        print_error "当前内核版本 $current_version 不支持 BBR。请升级到 4.9 或更高版本。"
        exit 1
    else
        print_success "内核版本 $current_version 支持 BBR，继续执行..."
    fi
}

# 函数：安装必要软件
install_necessary_software() {
    print_info "检查并安装必要软件..."
    if ! command -v sysctl &> /dev/null; then
        print_warning "sysctl 未安装，正在尝试安装..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y procps
        elif command -v yum &> /dev/null; then
            sudo yum install -y procps-ng
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y procps-ng
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm procps-ng
        else
            print_error "无法确定包管理器，请手动安装 procps 或 procps-ng。"
            exit 1
        fi
    fi
    if ! command -v cpufreq-info &> /dev/null; then
        print_warning "cpufrequtils 未安装，正在尝试安装..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y cpufrequtils
        elif command -v yum &> /dev/null; then
            sudo yum install -y cpufrequtils
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y cpufrequtils
        else
            print_error "无法确定包管理器，请手动安装 cpufrequtils。"
            exit 1
        fi
    fi
    print_success "必要软件已安装。"
}

# 函数：永久开启 BBR
enable_bbr() {
    print_info "正在永久开启 BBR..."
    sudo sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sudo sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    grep -q "net.core.default_qdisc" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf >/dev/null
    grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf >/dev/null
    sudo sysctl -p >/dev/null 2>&1
    if ! lsmod | grep -q tcp_bbr; then
        sudo modprobe tcp_bbr
        grep -q "tcp_bbr" /etc/modules || echo "tcp_bbr" | sudo tee -a /etc/modules >/dev/null
    fi
    print_success "BBR 已永久开启。"
}

# 函数：设置性能模式
set_performance_mode() {
    print_info "正在设置性能模式..."
    # 设置 CPU 调速器为 performance
    if [ -f /etc/default/cpufrequtils ]; then
        sudo sed -i 's/^GOVERNOR=.*/GOVERNOR="performance"/' /etc/default/cpufrequtils || echo 'GOVERNOR="performance"' | sudo tee -a /etc/default/cpufrequtils >/dev/null
    else
        echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils >/dev/null
    fi
    cat <<EOF | sudo tee /etc/systemd/system/cpu-performance.service >/dev/null
[Unit]
Description=Set CPU governor to performance

[Service]
Type=oneshot
ExecStart=/usr/bin/cpufreq-set -r -g performance

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload >/dev/null 2>&1
    sudo systemctl enable cpu-performance.service >/dev/null 2>&1
    sudo systemctl start cpu-performance.service >/dev/null 2>&1
    # 设置 I/O 调度器为 deadline
    if [ -f /etc/default/grub ]; then
        sudo sed -i 's/GRUB_CMDLINE_LINUX="[^"]*/& elevator=deadline/' /etc/default/grub
        if command -v update-grub &> /dev/null; then
            sudo update-grub >/dev/null 2>&1
        elif command -v grub2-mkconfig &> /dev/null; then
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
        fi
    fi
    # 设置 swappiness
    sudo sysctl -w vm.swappiness=10 >/dev/null 2>&1
    grep -q "vm.swappiness" /etc/sysctl.conf || echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf >/dev/null
    sudo sysctl -p >/dev/null 2>&1
    print_success "性能模式已设置并持久化。"
}

# 函数：安装所有优化
install_optimization() {
    check_kernel_version
    install_necessary_software
    enable_bbr
    set_performance_mode
    print_success "所有优化已安装并设置为永久生效。"
    prompt_reboot
}

# 函数：查看当前优化设置
view_settings() {
    print_info "当前优化设置如下："
    echo -e "${YELLOW}1. TCP 拥塞控制算法：${NC}"
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null || echo "未设置"
    echo -e "${YELLOW}2. 默认队列规则 (default_qdisc)：${NC}"
    sysctl net.core.default_qdisc 2>/dev/null || echo "未设置"
    echo -e "${YELLOW}3. BBR 模块状态：${NC}"
    lsmod | grep -q tcp_bbr && echo "已加载" || echo "未加载"
    echo -e "${YELLOW}4. CPU 调速器：${NC}"
    cpufreq-info -p 2>/dev/null || echo "无法检测"
    echo -e "${YELLOW}5. I/O 调度器（示例磁盘 sda）：${NC}"
    cat /sys/block/sda/queue/scheduler 2>/dev/null || echo "无法检测"
    echo -e "${YELLOW}6. Swappiness：${NC}"
    sysctl vm.swappiness 2>/dev/null || echo "未设置"
}

# 函数：删除所有优化
remove_optimization() {
    print_info "正在删除所有优化..."
    sudo sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
    sudo sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1
    sudo sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sudo sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sudo sysctl -p >/dev/null 2>&1
    sudo sed -i '/tcp_bbr/d' /etc/modules
    sudo systemctl disable cpu-performance.service >/dev/null 2>&1
    sudo rm -f /etc/systemd/system/cpu-performance.service
    sudo systemctl daemon-reload >/dev/null 2>&1
    sudo sed -i '/GOVERNOR/d' /etc/default/cpufrequtils
    if [ -f /etc/default/grub ]; then
        sudo sed -i 's/ elevator=deadline//' /etc/default/grub
        if command -v update-grub &> /dev/null; then
            sudo update-grub >/dev/null 2>&1
        elif command -v grub2-mkconfig &> /dev/null; then
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
        fi
    fi
    sudo sysctl -w vm.swappiness=60 >/dev/null 2>&1
    sudo sed -i '/vm.swappiness/d' /etc/sysctl.conf
    sudo sysctl -p >/dev/null 2>&1
    print_success "所有优化已删除并恢复为默认设置。"
    prompt_reboot
}

# 主菜单
while true; do
    clear
    echo -e "${GREEN}===== Linux 系统自动调优脚本 =====${NC}"
    echo -e "${BLUE}1. 安装优化（开启 BBR 和性能模式）${NC}"
    echo -e "${BLUE}2. 查看优化设置${NC}"
    echo -e "${BLUE}3. 删除优化（恢复默认设置）${NC}"
    echo -e "${BLUE}4. 退出${NC}"
    echo -e "${YELLOW}提示：部分设置需重启系统后生效。${NC}"
    read -p "请输入选项 (1-4): " choice
    case $choice in
        1)
            install_optimization
            read -p "按 Enter 键继续..."
            ;;
        2)
            view_settings
            read -p "按 Enter 键继续..."
            ;;
        3)
            remove_optimization
            read -p "按 Enter 键继续..."
            ;;
        4)
            print_success "退出脚本，感谢使用！"
            exit 0
            ;;
        *)
            print_error "无效选项，请输入 1-4 之间的数字。"
            read -p "按 Enter 键继续..."
            ;;
    esac
done