#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本 (sudo)${NC}"
    exit 1
fi

# 定义备份和配置文件路径
BACKUP_FILE="/etc/optimizer_backup"
SYSCTL_CONF="/etc/sysctl.d/99-optimizer.conf"
SERVICE_FILE="/etc/systemd/system/cpu-optimizer.service"

# 检测发行版并安装依赖
install_dependencies() {
    echo -e "${YELLOW}检测并安装所需依赖...${NC}"

    # 检测包管理器
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
        UPDATE_CMD="apt-get update -y"
        INSTALL_CMD="apt-get install -y"
        DISTRO="Debian/Ubuntu"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        UPDATE_CMD="yum update -y"
        INSTALL_CMD="yum install -y"
        DISTRO="RHEL/CentOS"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="dnf update -y"
        INSTALL_CMD="dnf install -y"
        DISTRO="Fedora"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        UPDATE_CMD="pacman -Sy"
        INSTALL_CMD="pacman -S --noconfirm"
        DISTRO="Arch Linux"
    else
        echo -e "${RED}无法识别的包管理器，请手动安装以下依赖：procps, systemd${NC}"
        exit 1
    fi

    # 检查并安装必要工具
    for pkg in procps systemd; do
        if ! dpkg -l "$pkg" >/dev/null 2>&1 && ! rpm -q "$pkg" >/dev/null 2>&1 && ! pacman -Qs "$pkg" >/dev/null 2>&1; then
            echo -e "${BLUE}安装 $pkg...${NC}"
            $UPDATE_CMD
            $INSTALL_CMD "$pkg"
        fi
    done

    # 检查并安装 CPU 频率管理工具
    if [ -d /sys/devices/system/cpu ] && ! command -v cpufreq-info >/dev/null 2>&1; then
        echo -e "${BLUE}安装 CPU 频率管理工具...${NC}"
        if [ "$PKG_MANAGER" = "apt-get" ]; then
            $INSTALL_CMD cpufrequtils
            CPU_TOOL="cpufrequtils"
        elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
            $INSTALL_CMD cpupowerutils || $INSTALL_CMD cpufreq-utils
            CPU_TOOL="cpupowerutils 或 cpufreq-utils"
        elif [ "$PKG_MANAGER" = "pacman" ]; then
            $INSTALL_CMD cpupower
            CPU_TOOL="cpupower"
        fi
    else
        CPU_TOOL="已安装或无需安装"
    fi

    # 检查并启用 TCP BBR 模块（若内核支持）
    BBR_STATUS="未启用"
    if ! lsmod | grep -q tcp_bbr; then
        echo -e "${BLUE}检查并加载 TCP BBR 模块...${NC}"
        modprobe tcp_bbr 2>/dev/null
        if lsmod | grep -q tcp_bbr; then
            echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf
            BBR_STATUS="已启用"
        else
            echo -e "${YELLOW}当前内核不支持 BBR 或需要手动启用${NC}"
            BBR_STATUS="不支持"
        fi
    else
        BBR_STATUS="已启用"
    fi

    # 输出安装完成信息
    echo -e "${GREEN}依赖安装完成！${NC}"
    echo -e "${BLUE}系统信息:${NC}"
    echo -e "  发行版: $DISTRO"
    echo -e "  包管理器: $PKG_MANAGER"
    echo -e "  已安装工具: procps, systemd, $CPU_TOOL"
    echo -e "  当前内核版本: $(uname -r)"
    echo -e "  CPU 核心数: $(nproc)"
    echo -e "  TCP BBR 状态: $BBR_STATUS"
}

# 检查当前优化状态（自动分析服务器配置及网络线路）
check_optimizations() {
    echo -e "${YELLOW}当前系统优化状态：${NC}"
    echo -e "${BLUE}----------------${NC}"

    # 检查 CPU 配置
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        CURRENT_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
        if [ "$CURRENT_GOVERNOR" = "performance" ]; then
            echo -e "${GREEN}CPU 频率管理模式: $CURRENT_GOVERNOR (已优化)${NC}"
        else
            echo -e "${RED}CPU 频率管理模式: $CURRENT_GOVERNOR (未优化)${NC}"
        fi
    else
        echo -e "${YELLOW}CPU 频率管理模式: 不可用${NC}"
    fi

    # 检查系统参数
    SWAPPINESS=$(sysctl -n vm.swappiness 2>/dev/null || echo "不可用")
    if [ "$SWAPPINESS" = "10" ]; then
        echo -e "${GREEN}vm.swappiness: $SWAPPINESS (已优化)${NC}"
    else
        echo -e "${RED}vm.swappiness: $SWAPPINESS (未优化)${NC}"
    fi

    RMEM_MAX=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "不可用")
    if [ "$RMEM_MAX" = "26214400" ]; then
        echo -e "${GREEN}net.core.rmem_max: $RMEM_MAX (已优化)${NC}"
    else
        echo -e "${RED}net.core.rmem_max: $RMEM_MAX (未优化)${NC}"
    fi

    WMEM_MAX=$(sysctl -n net.core.wmem_max 2>/dev/null || echo "不可用")
    if [ "$WMEM_MAX" = "26214400" ]; then
        echo -e "${GREEN}net.core.wmem_max: $WMEM_MAX (已优化)${NC}"
    else
        echo -e "${RED}net.core.wmem_max: $WMEM_MAX (未优化)${NC}"
    fi

    # 检查 TCP 拥塞控制
    if [ -f /proc/sys/net/ipv4/tcp_congestion_control ]; then
        CURRENT_CONGESTION=$(cat /proc/sys/net/ipv4/tcp_congestion_control)
        if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            if [ "$CURRENT_CONGESTION" = "bbr" ]; then
                echo -e "${GREEN}TCP 拥塞控制: $CURRENT_CONGESTION (已优化)${NC}"
            else
                echo -e "${RED}TCP 拥塞控制: $CURRENT_CONGESTION (未优化, BBR 可用但未启用)${NC}"
            fi
        else
            echo -e "${YELLOW}TCP 拥塞控制: $CURRENT_CONGESTION (BBR 不支持)${NC}"
        fi
    else
        echo -e "${YELLOW}TCP 拥塞控制: 不可用${NC}"
    fi

    # 检查网络线路
    DEFAULT_GATEWAY=$(ip route show default | awk '{print $3}' | head -n 1)
    if [ -n "$DEFAULT_GATEWAY" ]; then
        echo -e "${GREEN}默认网关: $DEFAULT_GATEWAY (已配置)${NC}"
    else
        echo -e "${RED}默认网关: 未配置${NC}"
    fi

    DNS_SERVERS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ', ' | sed 's/, $//')
    if [ -n "$DNS_SERVERS" ]; then
        echo -e "${GREEN}DNS 解析器: $DNS_SERVERS (已配置)${NC}"
    else
        echo -e "${RED}DNS 解析器: 未配置${NC}"
    fi

    echo -e "${BLUE}----------------${NC}"
}

# 应用优化（永久生效）
apply_optimizations() {
    echo -e "${YELLOW}应用优化设置...${NC}"

    # 备份当前设置
    echo -e "${BLUE}备份当前设置到 $BACKUP_FILE${NC}"
    {
        sysctl -a 2>/dev/null | grep -E "vm.swappiness|net.core.rmem_max|net.core.wmem_max|vm.dirty_ratio|vm.dirty_background_ratio|net.ipv4.tcp_congestion_control|net.core.netdev_max_backlog|net.core.somaxconn|net.ipv4.tcp_max_syn_backlog|net.ipv4.tcp_syncookies|net.ipv4.tcp_fin_timeout|net.ipv4.tcp_tw_reuse"
        if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
            echo "cpu_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
        fi
    } > "$BACKUP_FILE"

    # 应用 sysctl 优化，包括 TCP 网络调优
    cat <<EOF > "$SYSCTL_CONF"
# 系统优化
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# TCP 网络优化
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
EOF

    # 检查并启用 BBR
    if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYSCTL_CONF"
    fi

    # 应用 sysctl 设置
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1

    # 设置 CPU 频率管理为 performance 并持久化
    if [ -d /sys/devices/system/cpu ]; then
        echo -e "${BLUE}设置 CPU 频率管理模式为 performance${NC}"
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1

        # 创建 systemd 服务
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
        systemctl enable cpu-optimizer.service
        systemctl start cpu-optimizer.service
    fi

    echo -e "${GREEN}优化已应用并设置为永久生效！${NC}"
}

# 取消优化（恢复备份并移除持久化设置）
revert_optimizations() {
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}未找到备份文件，无法恢复优化！${NC}"
        return
    }

    echo -e "${YELLOW}取消优化并恢复原始设置...${NC}"

    # 恢复 sysctl 设置
    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        if [[ "$key" == cpu_governor ]]; then
            if [ -d /sys/devices/system/cpu ]; then
                echo "$value" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
            fi
        else
            sysctl -w "$key=$value" >/dev/null 2>&1
        fi
    done < "$BACKUP_FILE"

    # 删除持久化文件
    rm -f "$SYSCTL_CONF"
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable cpu-optimizer.service
        systemctl stop cpu-optimizer.service
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    # 清理备份文件
    rm -f "$BACKUP_FILE"

    echo -e "${GREEN}优化已取消，系统已恢复到原始状态！${NC}"
}

# 主程序：安装依赖并进入交互菜单
install_dependencies

while true; do
    echo -e "${BLUE}----------------${NC}"
    echo -e "${YELLOW}Linux 系统优化工具${NC}"
    echo -e "${GREEN}1. 检查当前优化状态${NC}"
    echo -e "${GREEN}2. 应用优化（永久生效）${NC}"
    echo -e "${GREEN}3. 取消优化（恢复原始设置）${NC}"
    echo -e "${GREEN}4. 退出${NC}"
    echo -e "${BLUE}----------------${NC}"
    read -p "$(echo -e ${YELLOW}请选择选项 \(1-4\): ${NC})" choice

    case $choice in
        1)
            check_optimizations
            ;;
        2)
            apply_optimizations
            ;;
        3)
            revert_optimizations
            ;;
        4)
            echo -e "${GREEN}退出脚本${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 1-4${NC}"
            ;;
    esac
done
