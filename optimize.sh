#!/bin/bash

# 定义颜色代码，便于输出美化
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # 无颜色

# 日志文件路径
LOG_FILE="/var/log/optimizer.log"

# 日志记录函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本 (sudo)${NC}"
    exit 1
fi

# 配置文件路径
SYSCTL_CONF="/etc/sysctl.d/99-optimizer.conf"
SERVICE_FILE="/etc/systemd/system/cpu-optimizer.service"

# 检测系统类型和版本（支持 CentOS 和 Ubuntu）
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

    if [ "$DISTRO" == "centos" ]; then
        # CentOS 包管理器配置
        if [ "${VERSION_ID%%.*}" -ge 8 ]; then
            PKG_MANAGER="dnf"
            UPDATE_CMD="dnf update -y"
            INSTALL_CMD="dnf install -y"
            REMOVE_CMD="dnf remove -y"
        else
            PKG_MANAGER="yum"
            UPDATE_CMD="yum update -y"
            INSTALL_CMD="yum install -y"
            REMOVE_CMD="yum remove -y"
        fi
    elif [ "$DISTRO" == "ubuntu" ]; then
        # Ubuntu 包管理器配置
        PKG_MANAGER="apt-get"
        UPDATE_CMD="apt-get update -y"
        INSTALL_CMD="apt-get install -y"
        REMOVE_CMD="apt-get remove -y"
    else
        echo -e "${RED}此脚本仅支持 CentOS 和 Ubuntu 系统，检测到: $DISTRO${NC}"
        log "不支持的系统类型: $DISTRO"
        exit 1
    fi
    echo -e "${BLUE}检测到系统: $DISTRO $VERSION_ID${NC}"
    log "检测到系统: $DISTRO $VERSION_ID"
}

# 安装依赖工具
install_dependencies() {
    echo -e "${YELLOW}安装依赖...${NC}"
    log "开始安装依赖"
    $UPDATE_CMD || { echo -e "${RED}更新包索引失败${NC}"; log "更新包索引失败"; exit 1; }
    if [ "$DISTRO" == "centos" ]; then
        $INSTALL_CMD procps systemd cpupowerutils grub2-tools || { echo -e "${RED}安装依赖失败${NC}"; log "安装依赖失败"; exit 1; }
    elif [ "$DISTRO" == "ubuntu" ]; then
        $INSTALL_CMD procps systemd cpufrequtils || { echo -e "${RED}安装依赖失败${NC}"; log "安装依赖失败"; exit 1; }
    fi
    echo -e "${GREEN}依赖安装完成${NC}"
    log "依赖安装完成"
}

# 添加 ELRepo 仓库（仅 CentOS）
add_elrepo_repo() {
    if [ "$DISTRO" != "centos" ]; then
        return
    fi
    echo -e "${YELLOW}检测 ELRepo 仓库...${NC}"
    log "检测 ELRepo 仓库"
    if [ -f "/etc/yum.repos.d/elrepo.repo" ]; then
        echo -e "${GREEN}ELRepo 仓库已存在${NC}"
        log "ELRepo 仓库已存在"
    else
        echo -e "${YELLOW}正在添加 ELRepo 仓库...${NC}"
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org || { echo -e "${RED}导入 GPG 密钥失败${NC}"; log "导入 GPG 密钥失败"; exit 1; }
        if [ "$VERSION_ID" = "7" ]; then
            $INSTALL_CMD https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
        elif [ "$VERSION_ID" = "8" ]; then
            $INSTALL_CMD https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm
        elif [ "$VERSION_ID" = "9" ]; then
            $INSTALL_CMD https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm
        else
            echo -e "${RED}不支持的 CentOS 版本: $VERSION_ID${NC}"
            log "不支持的 CentOS 版本: $VERSION_ID"
            exit 1
        fi
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}ELRepo 仓库添加成功${NC}"
            log "ELRepo 仓库添加成功"
        else
            echo -e "${RED}添加 ELRepo 仓库失败${NC}"
            log "添加 ELRepo 仓库失败"
            exit 1
        fi
    fi
}

# 更新内核
update_kernel() {
    if [ "$DISTRO" == "centos" ]; then
        update_kernel_centos
    elif [ "$DISTRO" == "ubuntu" ]; then
        update_kernel_ubuntu
    fi
}

# CentOS 内核更新
update_kernel_centos() {
    local current_kernel installed_kernels latest_kernel kernel_version
    current_kernel=$(uname -r)
    installed_kernels=$(rpm -qa | grep '^kernel-ml-[0-9]' | sort -V)
    
    if [ -z "$installed_kernels" ]; then
        echo -e "${YELLOW}未检测到 kernel-ml，正在安装...${NC}"
        log "未检测到 kernel-ml，开始安装新内核"
        $INSTALL_CMD --enablerepo=elrepo-kernel kernel-ml || { echo -e "${RED}安装新内核失败${NC}"; log "安装新内核失败"; exit 1; }
        latest_kernel=$(rpm -qa | grep '^kernel-ml-[0-9]' | sort -V | tail -n 1)
        kernel_version=$(echo "$latest_kernel" | sed 's/kernel-ml-//')
        set_default_kernel "$kernel_version"
        prompt_reboot
    else
        latest_kernel=$(echo "$installed_kernels" | tail -n 1)
        kernel_version=$(echo "$latest_kernel" | sed 's/kernel-ml-//')
        if [[ "$current_kernel" != "$kernel_version" ]]; then
            echo -e "${RED}当前内核 ($current_kernel) 不是最新内核 ($kernel_version)${NC}"
            log "当前内核与最新内核不一致"
            set_default_kernel "$kernel_version"
            prompt_reboot
        else
            echo -e "${GREEN}当前内核 ($current_kernel) 已是最新${NC}"
            log "当前内核已是最新"
            clean_old_kernels
        fi
    fi
}

# Ubuntu 内核更新
update_kernel_ubuntu() {
    echo -e "${YELLOW}更新 Ubuntu 内核...${NC}"
    log "开始更新 Ubuntu 内核"
    $INSTALL_CMD linux-image-generic || { echo -e "${RED}安装最新内核失败${NC}"; log "安装最新内核失败"; exit 1; }
    echo -e "${GREEN}内核更新完成，请重启系统以应用新内核${NC}"
    prompt_reboot
}

# 设置默认引导内核（CentOS）
set_default_kernel() {
    local kernel_version=$1
    grubby --set-default="/boot/vmlinuz-$kernel_version"
    grub2-mkconfig -o /boot/grub2/grub.cfg
    echo -e "${GREEN}已将 kernel-ml-$kernel_version 设置为默认引导内核${NC}"
    log "已将 kernel-ml-$kernel_version 设置为默认引导内核"
}

# 清理旧内核（CentOS）
clean_old_kernels() {
    if [ "$DISTRO" != "centos" ]; then
        return
    fi
    local installed_kernels=$(rpm -qa | grep '^kernel-ml-[0-9]' | sort -V)
    local latest_kernel=$(echo "$installed_kernels" | tail -n 1)
    for pkg in $installed_kernels; do
        if [ "$pkg" != "$latest_kernel" ]; then
            echo -e "${YELLOW}卸载旧内核包: $pkg${NC}"
            $REMOVE_CMD "$pkg"
        fi
    done
    echo -e "${GREEN}旧内核清理完成${NC}"
    log "旧内核清理完成"
}

# 提示用户重启
prompt_reboot() {
    read -p "$(echo -e ${YELLOW}"请重启系统以应用新内核，是否立即重启？ (y/N): "${NC})" answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}系统即将重启...${NC}"
        log "用户选择立即重启"
        reboot
    else
        echo -e "${YELLOW}请重启系统后再次运行脚本以继续${NC}"
        log "用户未选择重启，退出脚本"
        exit 0
    fi
}

# 应用系统优化
apply_optimizations() {
    echo -e "${YELLOW}应用系统优化...${NC}"
    log "开始应用系统优化"

    # 写入 sysctl 优化参数
    cat <<EOF > "$SYSCTL_CONF"
vm.swappiness = 10
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
EOF
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1

    # 设置 CPU 频率为 performance 模式
    if [ -d /sys/devices/system/cpu ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo performance > "$cpu" 2>/dev/null
        done
        # 创建 systemd 服务以持久化设置
        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=CPU Optimizer Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > \$cpu; done"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable cpu-optimizer.service >/dev/null 2>&1
        systemctl start cpu-optimizer.service >/dev/null 2>&1
    fi

    echo -e "${GREEN}系统优化已应用${NC}"
    log "系统优化完成"
}

# 取消优化（恢复默认设置）
revert_optimizations() {
    echo -e "${YELLOW}恢复系统默认设置...${NC}"
    log "开始恢复系统默认设置"
    if [ -f "$SYSCTL_CONF" ]; then
        rm -f "$SYSCTL_CONF"
        sysctl -p >/dev/null 2>&1
    fi
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable cpu-optimizer.service >/dev/null 2>&1
        systemctl stop cpu-optimizer.service >/dev/null 2>&1
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    echo -e "${GREEN}系统已恢复默认状态${NC}"
    log "系统默认设置恢复完成"
}

# 检查优化状态
check_optimizations() {
    echo -e "${YELLOW}检查优化状态...${NC}"
    log "开始检查优化状态"

    local current_kernel
    current_kernel=$(uname -r)

    echo -e "${BLUE}当前运行内核:${NC} $current_kernel"

    echo -e "${BLUE}sysctl 设置:${NC}"
    [ -f "$SYSCTL_CONF" ] && echo -e "${GREEN}sysctl 优化已应用${NC}" || echo -e "${RED}sysctl 优化未应用${NC}"

    echo -e "${BLUE}CPU 频率管理:${NC}"
    governors=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort | uniq)
    [ "$governors" = "performance" ] && echo -e "${GREEN}已设置为 performance${NC}" || echo -e "${RED}当前模式: $governors${NC}"

    systemctl is-enabled cpu-optimizer.service >/dev/null 2>&1 && echo -e "${GREEN}CPU 优化服务已启用${NC}" || echo -e "${RED}CPU 优化服务未启用${NC}"
}

# 主程序入口
detect_distro
install_dependencies
if [ "$DISTRO" == "centos" ]; then
    add_elrepo_repo
fi
update_kernel

# 交互式菜单
while true; do
    echo -e "${BLUE}----------------${NC}"
    echo -e "${YELLOW}$DISTRO 系统优化工具${NC}"
    echo -e "${GREEN}1. 检查优化状态${NC}"
    echo -e "${GREEN}2. 应用系统优化${NC}"
    echo -e "${GREEN}3. 取消优化${NC}"
    echo -e "${GREEN}4. 退出${NC}"
    echo -e "${BLUE}----------------${NC}"
    read -p "请选择选项 (1-4): " choice

    case $choice in
        1) check_optimizations ;;
        2) apply_optimizations ;;
        3) revert_optimizations ;;
        4) echo -e "${GREEN}退出脚本${NC}"; log "用户退出脚本"; exit 0 ;;
        *) echo -e "${RED}无效选项，请输入 1-4${NC}" ;;
    esac
done