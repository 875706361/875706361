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
    if [ "${VERSION_ID%%.*}" -ge 8 ]; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="dnf update -y"
        INSTALL_CMD="dnf install -y"
    fi
    echo -e "${BLUE}检测到系统: $DISTRO $VERSION_ID${NC}"
    log "检测到系统: $DISTRO $VERSION_ID"
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}安装依赖...${NC}"
    log "开始安装依赖"

    $UPDATE_CMD || { echo -e "${RED}更新包索引失败${NC}"; log "更新包索引失败"; exit 1; }
    $INSTALL_CMD procps systemd cpupowerutils grub2-tools || { echo -e "${RED}安装依赖失败${NC}"; log "安装依赖失败"; exit 1; }

    echo -e "${GREEN}依赖安装完成${NC}"
    log "依赖安装完成"
}

# 添加 ELRepo 仓库
add_elrepo_repo() {
    echo -e "${YELLOW}添加 ELRepo 仓库...${NC}"
    log "开始添加 ELRepo 仓库"

    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org || { echo -e "${RED}导入 ELRepo GPG 密钥失败${NC}"; log "导入 ELRepo GPG 密钥失败"; exit 1; }

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
    [ $? -ne 0 ] && { echo -e "${RED}安装 ELRepo 仓库失败${NC}"; log "安装 ELRepo 仓库失败"; exit 1; }
    echo -e "${GREEN}ELRepo 仓库添加成功${NC}"
    log "ELRepo 仓库添加成功"
}

# 检查内核是否支持 CPU 频率管理
check_kernel_cpufreq_support() {
    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        echo "yes"
    else
        echo "no"
    fi
}

# 检查当前内核版本是否为最新
check_kernel_version() {
    CURRENT_KERNEL=$(uname -r)
    LATEST_KERNEL=$(rpm -qa | grep kernel-ml | sort -V | tail -n 1 | sed 's/kernel-ml-//')
    if [ -z "$LATEST_KERNEL" ]; then
        echo -e "${YELLOW}未检测到已安装的新内核${NC}"
        log "未检测到已安装的新内核"
        return 1
    fi
    if [ "$CURRENT_KERNEL" != "$LATEST_KERNEL" ]; then
        echo -e "${RED}当前运行内核 ($CURRENT_KERNEL) 与最新安装内核 ($LATEST_KERNEL) 不一致${NC}"
        log "当前运行内核与最新安装内核不一致"
        return 1
    else
        echo -e "${GREEN}当前运行内核 ($CURRENT_KERNEL) 为最新版本${NC}"
        log "当前运行内核为最新版本"
        return 0
    fi
}

# 升级内核
upgrade_kernel() {
    echo -e "${YELLOW}升级内核以支持 CPU 频率管理...${NC}"
    log "开始升级内核"

    $INSTALL_CMD --enablerepo=elrepo-kernel kernel-ml || { echo -e "${RED}安装新内核失败${NC}"; log "安装新内核失败"; exit 1; }
    grub2-set-default 0 || { echo -e "${RED}设置默认内核失败${NC}"; log "设置默认内核失败"; exit 1; }
    grub2-mkconfig -o /boot/grub2/grub.cfg || { echo -e "${RED}更新 GRUB 配置文件失败${NC}"; log "更新 GRUB 配置文件失败"; exit 1; }

    echo -e "${GREEN}内核升级完成，请重启系统${NC}"
    log "内核升级完成"
}

# 应用系统优化
apply_optimizations() {
    echo -e "${YELLOW}应用系统优化...${NC}"
    log "开始应用优化"

    # 备份 sysctl 设置
    sysctl -a > "$BACKUP_FILE" || { echo -e "${RED}备份 sysctl 设置失败${NC}"; log "备份 sysctl 设置失败"; exit 1; }

    # 应用 sysctl 优化
    cat <<EOF > "$SYSCTL_CONF"
vm.swappiness = 10
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
EOF
    sysctl -p "$SYSCTL_CONF" || { echo -e "${RED}应用 sysctl 优化失败${NC}"; log "应用 sysctl 优化失败"; exit 1; }

    # 设置 CPU 频率管理为 performance
    if [ -d /sys/devices/system/cpu ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo performance > "$cpu" 2>/dev/null
        done
        [ $? -ne 0 ] && { echo -e "${YELLOW}设置 CPU 频率失败${NC}"; log "设置 CPU 频率失败"; }

        # 创建 systemd 服务
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
        systemctl enable cpu-optimizer.service
        systemctl start cpu-optimizer.service
        [ $? -ne 0 ] && { echo -e "${YELLOW}启用 CPU 服务失败${NC}"; log "启用 CPU 服务失败"; } || { echo -e "${GREEN}CPU 服务启用成功${NC}"; log "CPU 服务启用成功"; }
    fi
    echo -e "${GREEN}优化已应用${NC}"
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

    while IFS=' = ' read -r key value; do
        sysctl -w "$key=$value" >/dev/null 2>&1
    done < "$BACKUP_FILE"

    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable cpu-optimizer.service
        systemctl stop cpu-optimizer.service
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    rm -f "$SYSCTL_CONF"
    echo -e "${GREEN}系统已恢复到优化前状态${NC}"
    log "恢复完成"
}

# 检查优化状态
check_optimizations() {
    echo -e "${YELLOW}检查优化状态...${NC}"
    log "开始检查优化状态"

    check_kernel_version
    echo -e "${BLUE}CPU 频率支持:${NC}"
    if [ "$(check_kernel_cpufreq_support)" = "yes" ]; then
        echo -e "${GREEN}当前内核支持 CPU 频率管理${NC}"
    else
        echo -e "${RED}当前内核不支持 CPU 频率管理${NC}"
    fi

    echo -e "${BLUE}sysctl 设置:${NC}"
    [ -f "$SYSCTL_CONF" ] && echo -e "${GREEN}sysctl 优化已应用${NC}" || echo -e "${RED}sysctl 优化未应用${NC}"

    if [ -d /sys/devices/system/cpu ]; then
        governors=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort | uniq)
        [ "$governors" = "performance" ] && echo -e "${GREEN}CPU 频率管理已设置为 performance${NC}" || echo -e "${RED}CPU 频率管理未设置为 performance，当前为: $governors${NC}"
    fi

    systemctl is-enabled cpu-optimizer.service >/dev/null 2>&1 && echo -e "${GREEN}CPU 优化服务已启用${NC}" || echo -e "${RED}CPU 优化服务未启用${NC}"
}

# 主程序
detect_distro
install_dependencies
add_elrepo_repo

check_kernel_version
if [ $? -ne 0 ]; then
    echo -e "${RED}请确保新内核已设置为默认启动项并重启系统${NC}"
    echo -e "${YELLOW}运行以下命令更新 GRUB 并重启:${NC}"
    echo "grub2-set-default 0 && grub2-mkconfig -o /boot/grub2/grub.cfg && reboot"
    exit 1
fi

if [ "$(check_kernel_cpufreq_support)" = "no" ]; then
    upgrade_kernel
    echo -e "${RED}请重启系统后再次运行脚本以应用优化${NC}"
    exit 0
fi

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