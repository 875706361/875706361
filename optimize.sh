#!/bin/bash
# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # 无颜色

# 日志文件
LOG_FILE="/var/log/optimizer.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本 (sudo)${NC}"
    exit 1
fi

# 配置文件和标识文件路径
SYSCTL_CONF="/etc/sysctl.d/99-optimizer.conf"
SERVICE_FILE="/etc/systemd/system/cpu-optimizer.service"
FLAG_FILE="/var/run/optimizer_kernel_update_pending"

# 检测系统类型和版本（仅支持 CentOS）
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

    # 根据 CentOS 版本选择包管理器及命令
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

# 安装所需依赖
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

# 检查并更新内核
update_kernel() {
    local current_kernel installed_new_kernel latest_kernel
    current_kernel=$(uname -r)
    installed_new_kernel=$(rpm -qa | grep kernel-ml)

    # 如果未安装 kernel-ml，新内核还不存在，则进行安装
    if [ -z "$installed_new_kernel" ]; then
        echo -e "${YELLOW}未检测到 kernel-ml 新内核，正在安装...${NC}"
        log "未检测到 kernel-ml，新内核安装开始"
        $INSTALL_CMD --enablerepo=elrepo-kernel kernel-ml || { echo -e "${RED}安装新内核失败${NC}"; log "安装新内核失败"; exit 1; }
        # 安装完成后更新 GRUB
        echo -e "${GREEN}新内核安装成功，更新 GRUB 配置...${NC}"
        grub2-set-default 0
        grub2-mkconfig -o /boot/grub2/grub.cfg
        # 创建标识文件并提示重启
        touch "$FLAG_FILE"
        log "新内核安装成功，创建重启标识"
        read -p "$(echo -e ${YELLOW}"请重启系统以使用新内核，是否立即重启？ (y/N): "${NC})" answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}系统即将重启...${NC}"
            log "用户选择立即重启"
            reboot
        else
            echo -e "${YELLOW}请重启系统后再次运行脚本以继续其他操作${NC}"
            log "用户未选择重启，退出脚本"
            exit 0
        fi
    else
        # 如果已安装 kernel-ml，则获取最新版本号（去除前缀）
        latest_kernel=$(rpm -qa | grep kernel-ml | sed 's/kernel-ml-//' | sort -V | tail -n 1)
        log "当前运行内核: $current_kernel"
        log "最新安装内核: $latest_kernel"
        # 如果当前运行内核与最新内核不一致，则说明还未重启
        if [[ "$current_kernel" != "$latest_kernel" ]]; then
            echo -e "${RED}当前运行内核 ($current_kernel) 与最新安装内核 ($latest_kernel) 不一致${NC}"
            log "当前运行内核与最新安装内核不一致"
            # 如果标识文件不存在，则执行卸载旧内核和更新 GRUB操作
            if [ ! -f "$FLAG_FILE" ]; then
                echo -e "${YELLOW}正在清理旧内核，仅保留最新内核 ($latest_kernel)${NC}"
                for kernel in $(rpm -qa | grep kernel-ml | sed 's/kernel-ml-//'); do
                    if [[ "$kernel" != "$latest_kernel" ]]; then
                        echo -e "${RED}卸载旧内核: $kernel${NC}"
                        $REMOVE_CMD "kernel-ml-$kernel"
                    fi
                done
                echo -e "${GREEN}更新 GRUB 配置...${NC}"
                grub2-set-default 0
                grub2-mkconfig -o /boot/grub2/grub.cfg
                # 创建标识文件，并提示重启
                touch "$FLAG_FILE"
                log "更新 GRUB 完成，等待重启"
                read -p "$(echo -e ${YELLOW}"请重启系统以应用新内核，是否立即重启？ (y/N): "${NC})" answer
                if [[ "$answer" =~ ^[Yy]$ ]]; then
                    echo -e "${GREEN}系统即将重启...${NC}"
                    log "用户选择立即重启"
                    reboot
                else
                    echo -e "${YELLOW}请重启系统后再次运行脚本以继续其他操作${NC}"
                    log "用户未选择重启，退出脚本"
                    exit 0
                fi
            else
                echo -e "${YELLOW}内核更新已应用，但系统尚未重启。请重启后再运行脚本。${NC}"
                log "标识文件存在，等待系统重启"
                exit 0
            fi
        else
            echo -e "${GREEN}当前运行内核 ($current_kernel) 已是最新，无需更新内核${NC}"
            log "当前运行内核已是最新"
            [ -f "$FLAG_FILE" ] && rm -f "$FLAG_FILE"
        fi
    fi
}

# 应用系统优化
apply_optimizations() {
    echo -e "${YELLOW}应用系统优化...${NC}"
    log "开始应用优化"

    # 应用 sysctl 优化设置
    cat <<EOF > "$SYSCTL_CONF"
vm.swappiness = 10
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
EOF
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1

    # 设置 CPU 频率管理为 performance
    if [ -d /sys/devices/system/cpu ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo performance > "$cpu" 2>/dev/null
        done
        # 创建 systemd 服务，保证重启后设置生效
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
    log "优化应用完成"
}

# 取消优化（恢复默认设置）
revert_optimizations() {
    echo -e "${YELLOW}恢复系统设置...${NC}"
    log "开始恢复设置"
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
    echo -e "${GREEN}系统已恢复到优化前状态${NC}"
    log "恢复完成"
}

# 检查优化状态
check_optimizations() {
    echo -e "${YELLOW}检查优化状态...${NC}"
    log "开始检查优化状态"

    local current_kernel installed_new_kernel latest_kernel
    current_kernel=$(uname -r)
    installed_new_kernel=$(rpm -qa | grep kernel-ml | sed 's/kernel-ml-//')
    latest_kernel=$(echo "$installed_new_kernel" | sort -V | tail -n 1)

    echo -e "${BLUE}当前运行内核:${NC} $current_kernel"
    echo -e "${BLUE}最新安装内核:${NC} ${latest_kernel:-"未安装新内核"}"

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
add_elrepo_repo
update_kernel

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