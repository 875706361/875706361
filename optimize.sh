#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 日志文件
LOG_FILE="/var/log/optimizer.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本 (sudo)${NC}"
    exit 1
fi

# 获取当前运行的内核版本
current_kernel=$(uname -r)

# 获取系统已安装的 kernel-ml 版本
installed_kernels=$(rpm -qa | grep kernel-ml | sed 's/kernel-ml-//')

# 获取最新的 kernel-ml 版本
latest_kernel=$(echo "$installed_kernels" | sort -V | tail -n 1)

# 检测系统类型和版本
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION_ID=$VERSION_ID
    else
        echo -e "${RED}无法检测系统类型${NC}"
        log "无法检测系统类型"
        exit 1
    fi

    if [ "$DISTRO" != "centos" ]; then
        echo -e "${RED}此脚本仅支持 CentOS 系统，检测到: $DISTRO${NC}"
        log "不支持的系统类型: $DISTRO"
        exit 1
    fi

    PKG_MANAGER="yum"
    UPDATE_CMD="yum update -y"
    INSTALL_CMD="yum install -y"
    REMOVE_CMD="yum remove -y"
    if [ "${VERSION_ID%%.*}" -ge 8 ]; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="dnf update -y"
        INSTALL_CMD="dnf install -y"
        REMOVE_CMD="dnf remove -y"
    fi
    echo -e "${BLUE}检测到系统: $DISTRO $VERSION_ID${NC}"
    log "检测到系统: $DISTRO $VERSION_ID"
}

# 检查并更新内核
check_and_update_kernel() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - 当前运行内核: $current_kernel"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - 最新安装内核: $latest_kernel"

    if [[ "$current_kernel" != "$latest_kernel" ]]; then
        echo -e "${RED}当前运行内核与最新安装内核不一致${NC}"
        log "当前运行内核与最新安装内核不一致"

        # 删除旧内核，仅保留最新内核
        echo -e "${YELLOW}正在清理旧内核，仅保留最新内核: $latest_kernel${NC}"
        for kernel in $installed_kernels; do
            if [[ "$kernel" != "$latest_kernel" ]]; then
                echo -e "${RED}卸载旧内核: $kernel${NC}"
                $REMOVE_CMD "kernel-ml-$kernel"
            fi
        done

        # 更新 GRUB 并设置最新内核为默认启动项
        echo -e "${GREEN}更新 GRUB 并设置默认内核: $latest_kernel${NC}"
        grub2-set-default 0
        grub2-mkconfig -o /boot/grub2/grub.cfg

        echo -e "${GREEN}内核已更新，系统即将重启...${NC}"
        log "系统重启以应用新内核"
        reboot
    else
        echo -e "${GREEN}当前运行内核已是最新，无需重启${NC}"
        log "当前运行内核已是最新"
    fi
}

# 应用系统优化
apply_optimizations() {
    echo -e "${YELLOW}应用系统优化...${NC}"
    log "开始应用优化"

    # 应用 sysctl 优化
    SYSCTL_CONF="/etc/sysctl.d/99-optimizer.conf"
    cat <<EOF > "$SYSCTL_CONF"
vm.swappiness = 10
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
EOF
    sysctl -p "$SYSCTL_CONF"

    # 设置 CPU 频率管理为 performance
    if [ -d /sys/devices/system/cpu ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo performance > "$cpu" 2>/dev/null
        done
    fi

    echo -e "${GREEN}优化已应用${NC}"
    log "优化应用完成"
}

# 取消优化
revert_optimizations() {
    echo -e "${YELLOW}恢复系统设置...${NC}"
    log "开始恢复设置"

    SYSCTL_CONF="/etc/sysctl.d/99-optimizer.conf"
    rm -f "$SYSCTL_CONF"
    sysctl -p

    echo -e "${GREEN}系统已恢复到优化前状态${NC}"
    log "恢复完成"
}

# 检查优化状态
check_optimizations() {
    echo -e "${YELLOW}检查优化状态...${NC}"
    log "开始检查优化状态"

    echo -e "${BLUE}当前运行内核:${NC} $current_kernel"
    echo -e "${BLUE}最新安装内核:${NC} $latest_kernel"

    echo -e "${BLUE}sysctl 设置:${NC}"
    [ -f "/etc/sysctl.d/99-optimizer.conf" ] && echo -e "${GREEN}sysctl 优化已应用${NC}" || echo -e "${RED}sysctl 优化未应用${NC}"

    echo -e "${BLUE}CPU 频率管理:${NC}"
    governors=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort | uniq)
    [ "$governors" = "performance" ] && echo -e "${GREEN}已设置为 performance${NC}" || echo -e "${RED}当前模式: $governors${NC}"
}

# 运行主程序
detect_distro
check_and_update_kernel

while true; do
    echo -e "${BLUE}----------------${NC}"
    echo -e "${YELLOW}CentOS 系统优化工具${NC}"
    echo -e "${GREEN}1. 检查优化状态${NC}"
    echo -e "${GREEN}2. 应用优化${NC}"
    echo -e "${GREEN}3. 取消优化${NC}"
    echo -e "${GREEN}4. 退出${NC}"
    echo -e "${BLUE}----------------${NC}"
    read -p "请选择选项 (1-4): " choice

    case $choice in
        1) check_optimizations ;;
        2) apply_optimizations ;;
        3) revert_optimizations ;;
        4) echo -e "${GREEN}退出脚本${NC}"; log "脚本退出"; exit 0 ;;
        *) echo -e "${RED}无效选项，请输入 1-4${NC}" ;;
    esac
done