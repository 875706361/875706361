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

# 定义配置文件路径
BACKUP_FILE="/etc/optimizer_backup"
SYSCTL_CONF="/etc/sysctl.d/99-optimizer.conf"
SERVICE_FILE="/etc/systemd/system/cpu-optimizer.service"

# 检测发行版并设置包管理器
detect_distro() {
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
        UPDATE_CMD="apt-get update -y"
        INSTALL_CMD="apt-get install -y"
        DISTRO="Ubuntu"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="dnf update -y"
        INSTALL_CMD="dnf install -y"
        DISTRO="CentOS 8+"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        UPDATE_CMD="yum update -y"
        INSTALL_CMD="yum install -y"
        DISTRO="CentOS 7"
    else
        echo -e "${RED}无法识别的包管理器，请手动安装依赖${NC}"
        log "无法识别包管理器，退出"
        exit 1
    fi
    echo -e "${BLUE}检测到发行版: $DISTRO${NC}"
}

# 添加 ELRepo 仓库（仅 CentOS）
add_elrepo_repo() {
    if [ "$DISTRO" = "CentOS 7" ] || [ "$DISTRO" = "CentOS 8+" ]; then
        echo -e "${YELLOW}添加 ELRepo 仓库...${NC}"
        log "开始添加 ELRepo 仓库"
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null || { echo -e "${RED}导入 ELRepo GPG 密钥失败${NC}"; log "导入 ELRepo GPG 密钥失败"; return 1; }
        if [ "$DISTRO" = "CentOS 7" ]; then
            $INSTALL_CMD https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm || { echo -e "${RED}安装 ELRepo 仓库失败${NC}"; log "安装 ELRepo 仓库失败"; return 1; }
        else
            $INSTALL_CMD https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm || { echo -e "${RED}安装 ELRepo 仓库失败${NC}"; log "安装 ELRepo 仓库失败"; return 1; }
        fi
        echo -e "${GREEN}ELRepo 仓库添加成功！${NC}"
        log "ELRepo 仓库添加成功"
    else
        echo -e "${YELLOW}$DISTRO 不需要 ELRepo 仓库${NC}"
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}安装依赖...${NC}"
    log "开始安装依赖"

    # 更新包索引
    $UPDATE_CMD || { echo -e "${RED}更新包索引失败${NC}"; log "更新包索引失败"; exit 1; }

    # 安装 procps 和 systemd
    for pkg in procps systemd; do
        if ! command -v ps >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1; then
            $INSTALL_CMD $pkg || { echo -e "${RED}安装 $pkg 失败${NC}"; log "安装 $pkg 失败"; exit 1; }
        fi
    done

    # 安装 CPU 频率管理工具
    if [ -d /sys/devices/system/cpu ]; then
        if [ "$DISTRO" = "Ubuntu" ]; then
            CPUFREQ_PKG="cpufrequtils"
        else
            CPUFREQ_PKG="cpupowerutils"
        fi
        if ! command -v cpufreq-info >/dev/null 2>&1 && ! command -v cpupower >/dev/null 2>&1; then
            echo -e "${BLUE}安装 $CPUFREQ_PKG...${NC}"
            $INSTALL_CMD $CPUFREQ_PKG || { echo -e "${RED}安装 $CPUFREQ_PKG 失败${NC}"; log "安装 $CPUFREQ_PKG 失败"; exit 1; }
        else
            echo -e "${GREEN}CPU 频率管理工具已安装${NC}"
        fi
    fi

    # 安装 grub2-tools（CentOS）
    if [ "$DISTRO" = "CentOS 7" ] || [ "$DISTRO" = "CentOS 8+" ]; then
        $INSTALL_CMD grub2-tools || { echo -e "${RED}安装 grub2-tools 失败${NC}"; log "安装 grub2-tools 失败"; exit 1; }
    fi
}

# 检查内核是否支持 CPU 频率管理
check_kernel_cpufreq_support() {
    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        echo "yes"
    else
        echo "no"
    fi
}

# 升级内核（如果不支持 CPU 频率管理）
upgrade_kernel() {
    if [ "$DISTRO" = "CentOS 7" ] || [ "$DISTRO" = "CentOS 8+" ]; then
        echo -e "${YELLOW}升级内核以支持 CPU 频率管理...${NC}"
        log "开始升级内核"
        $INSTALL_CMD --enablerepo=elrepo-kernel kernel-ml || { echo -e "${RED}安装新内核失败${NC}"; log "安装新内核失败"; exit 1; }
        grub2-set-default 0
        echo -e "${GREEN}内核升级完成，请重启系统${NC}"
        log "内核升级完成"
    elif [ "$DISTRO" = "Ubuntu" ]; then
        echo -e "${YELLOW}安装 HWE 内核...${NC}"
        $INSTALL_CMD linux-generic-hwe-$(lsb_release -sr) || { echo -e "${RED}安装 HWE 内核失败${NC}"; log "安装 HWE 内核失败"; exit 1; }
        echo -e "${GREEN}内核升级完成，请重启系统${NC}"
        log "内核升级完成"
    else
        echo -e "${RED}不支持的发行版，无法自动升级内核${NC}"
        log "不支持的发行版，无法升级内核"
        exit 1
    fi
}

# 应用系统优化
apply_optimizations() {
    echo -e "${YELLOW}应用系统优化...${NC}"
    log "开始应用优化"

    # 备份当前设置
    echo -e "${BLUE}备份当前设置到 $BACKUP_FILE${NC}"
    touch "$BACKUP_FILE" || { echo -e "${RED}无法创建备份文件${NC}"; log "备份文件创建失败"; exit 1; }
    sysctl -a > "$BACKUP_FILE" 2>/dev/null

    # 应用 sysctl 优化
    echo -e "${BLUE}应用 sysctl 优化...${NC}"
    cat <<EOF > "$SYSCTL_CONF"
vm.swappiness = 10
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
EOF
    sysctl -p "$SYSCTL_CONF" || { echo -e "${RED}应用 sysctl 优化失败${NC}"; log "应用 sysctl 优化失败"; exit 1; }

    # 设置 CPU 频率管理为 performance
    if [ -d /sys/devices/system/cpu ]; then
        echo -e "${BLUE}设置 CPU 频率管理模式为 performance${NC}"
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || { echo -e "${YELLOW}设置 CPU 频率失败${NC}"; log "设置 CPU 频率失败"; }
        echo -e "${BLUE}创建 CPU 优化服务...${NC}"
        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=CPU Optimizer Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable cpu-optimizer.service && systemctl start cpu-optimizer.service || { echo -e "${YELLOW}启用 CPU 服务失败${NC}"; log "启用 CPU 服务失败"; }
    fi

    echo -e "${GREEN}优化已应用！${NC}"
    log "优化应用完成"
}

# 取消优化
revert_optimizations() {
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}未找到备份文件，无法恢复${NC}"
        log "未找到备份文件"
        exit 1
    fi

    echo -e "${YELLOW}恢复系统设置...${NC}"
    log "开始恢复设置"

    # 恢复 sysctl 设置
    while IFS=' = ' read -r key value; do
        sysctl -w "$key=$value" >/dev/null 2>&1
    done < "$BACKUP_FILE"

    # 移除 CPU 优化服务
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable cpu-optimizer.service
        systemctl stop cpu-optimizer.service
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    echo -e "${GREEN}系统已恢复到优化前状态${NC}"
    log "恢复完成"
}

# 主程序
detect_distro
add_elrepo_repo
install_dependencies

# 检查内核支持
if [ "$(check_kernel_cpufreq_support)" = "no" ]; then
    upgrade_kernel
    echo -e "${RED}请重启系统后再次运行脚本以应用优化${NC}"
    exit 0
fi

while true; do
    echo -e "${BLUE}----------------${NC}"
    echo -e "${YELLOW}Linux 系统优化工具${NC}"
    echo -e "${GREEN}1. 应用优化${NC}"
    echo -e "${GREEN}2. 取消优化${NC}"
    echo -e "${GREEN}3. 退出${NC}"
    echo -e "${BLUE}----------------${NC}"
    read -p "请选择选项 (1-3): " choice

    case $choice in
        1) apply_optimizations ;;
        2) revert_optimizations ;;
        3) echo -e "${GREEN}退出脚本${NC}"; log "脚本退出"; exit 0 ;;
        *) echo -e "${RED}无效选项，请输入 1-3${NC}" ;;
    esac
done