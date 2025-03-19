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

# 添加 ELRepo 仓库
add_elrepo_repo() {
    echo -e "${YELLOW}添加 ELRepo 仓库...${NC}"
    log "开始添加 ELRepo 仓库"

    case $PKG_MANAGER in
        "yum")
            # CentOS 7
            echo -e "${BLUE}导入 ELRepo GPG 密钥...${NC}"
            rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null || { echo -e "${RED}导入 ELRepo GPG 密钥失败，请检查网络${NC}"; log "导入 ELRepo GPG 密钥失败"; return 1; }
            echo -e "${BLUE}安装 ELRepo 仓库 RPM...${NC}"
            yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm || { echo -e "${RED}安装 ELRepo 仓库失败${NC}"; log "安装 ELRepo 仓库失败"; return 1; }
            ;;
        "dnf")
            # CentOS 8+
            echo -e "${BLUE}导入 ELRepo GPG 密钥...${NC}"
            rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null || { echo -e "${RED}导入 ELRepo GPG 密钥失败，请检查网络${NC}"; log "导入 ELRepo GPG 密钥失败"; return 1; }
            echo -e "${BLUE}安装 ELRepo 仓库 RPM...${NC}"
            dnf install -y https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm || { echo -e "${RED}安装 ELRepo 仓库失败${NC}"; log "安装 ELRepo 仓库失败"; return 1; }
            ;;
        "apt-get")
            # Ubuntu 不直接支持 ELRepo，提示用户
            echo -e "${YELLOW}Ubuntu 不支持 ELRepo 仓库，跳过添加${NC}"
            log "Ubuntu 不支持 ELRepo 仓库"
            return 0
            ;;
        *)
            echo -e "${RED}不支持的包管理器，无法添加 ELRepo 仓库${NC}"
            log "不支持的包管理器，无法添加 ELRepo 仓库"
            return 1
            ;;
    esac

    # 验证 ELRepo 仓库是否添加成功
    if [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
        yum repolist | grep -q elrepo || dnf repolist | grep -q elrepo
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}ELRepo 仓库添加成功！${NC}"
            log "ELRepo 仓库添加成功"
        else
            echo -e "${RED}ELRepo 仓库添加失败，请检查配置${NC}"
            log "ELRepo 仓库添加失败"
            return 1
        fi
    fi
    return 0
}

# 检测发行版并安装依赖
install_dependencies() {
    echo -e "${YELLOW}检测并安装所需依赖...${NC}"
    log "开始安装依赖"

    # 检测包管理器
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
        echo -e "${RED}无法识别的包管理器，请手动安装依赖：procps, systemd${NC}"
        log "无法识别包管理器，退出"
        exit 1
    fi

    # 更新包索引
    echo -e "${BLUE}更新包索引...${NC}"
    $UPDATE_CMD || { echo -e "${RED}更新包索引失败${NC}"; log "更新包索引失败"; exit 1; }

    # 安装必要工具
    for pkg in procps systemd; do
        if ! command -v ps >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1; then
            echo -e "${BLUE}安装 $pkg...${NC}"
            $INSTALL_CMD $pkg || { echo -e "${RED}安装 $pkg 失败${NC}"; log "安装 $pkg 失败"; exit 1; }
        fi
    done

    # 添加 ELRepo 仓库（仅 CentOS）
    add_elrepo_repo || { echo -e "${RED}添加 ELRepo 仓库失败，退出${NC}"; exit 1; }

    # 安装 CPU 频率管理工具
    if [ -d /sys/devices/system/cpu ]; then
        echo -e "${BLUE}检查并安装 CPU 频率管理工具...${NC}"
        if ! command -v cpufreq-info >/dev/null 2>&1 && ! command -v cpupower >/dev/null 2>&1; then
            case $PKG_MANAGER in
                "apt-get") $INSTALL_CMD cpufrequtils && CPU_TOOL="cpufrequtils" ;;
                "yum"|"dnf") $INSTALL_CMD cpupower || $INSTALL_CMD cpufreq-utils && CPU_TOOL="cpupower 或 cpufreq-utils" ;;
            esac
        else
            CPU_TOOL="已安装"
        fi
    else
        CPU_TOOL="无需安装"
    fi

    echo -e "${GREEN}依赖安装完成！${NC}"
    log "依赖安装完成"
    echo -e "${BLUE}系统信息:${NC}"
    echo -e "  发行版: $DISTRO"
    echo -e "  包管理器: $PKG_MANAGER"
    echo -e "  已安装工具: procps, systemd, $CPU_TOOL"
    echo -e "  当前内核版本: $(uname -r)"
    echo -e "  CPU 核心数: $(nproc)"
}

# 检查参数状态的辅助函数
check_param() {
    local param=$1 expected=$2 desc=$3
    local value=$(sysctl -n "$param" 2>/dev/null || echo "不可用")
    [ "$value" = "$expected" ] && echo -e "${GREEN}$desc: $value (已优化)${NC}" || echo -e "${RED}$desc: $value (未优化)${NC}"
}

# 检查当前优化状态
check_optimizations() {
    echo -e "${YELLOW}当前系统优化状态：${NC}"
    echo -e "${BLUE}----------------${NC}"

    # 检查 CPU 配置
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        CURRENT_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "不可用")
        [ "$CURRENT_GOVERNOR" = "performance" ] && echo -e "${GREEN}CPU 频率管理模式: $CURRENT_GOVERNOR (已优化)${NC}" || echo -e "${RED}CPU 频率管理模式: $CURRENT_GOVERNOR (未优化)${NC}"
    else
        echo -e "${YELLOW}CPU 频率管理模式: 不可用${NC}"
    fi

    # 检查系统参数
    total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    rmem_max=$((total_mem * 1024 / 4))
    check_param "vm.swappiness" "10" "vm.swappiness"
    check_param "net.core.rmem_max" "$rmem_max" "net.core.rmem_max"
    check_param "net.core.wmem_max" "$rmem_max" "net.core.wmem_max"

    echo -e "${BLUE}----------------${NC}"
}

# 应用优化（永久生效）
apply_optimizations() {
    echo -e "${YELLOW}开始应用优化${NC}"
    log "开始应用优化"

    # 动态计算网络缓冲区大小
    total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')  # 单位 KB
    rmem_max=$((total_mem * 1024 / 4))  # 内存的 1/4，单位字节
    wmem_max=$rmem_max

    # 备份当前设置
    echo -e "${BLUE}备份当前设置到 $BACKUP_FILE${NC}"
    touch "$BACKUP_FILE" 2>/dev/null || { echo -e "${RED}无法创建备份文件，请检查权限或磁盘空间${NC}"; log "备份文件创建失败"; exit 1; }
    chmod 600 "$BACKUP_FILE"
    {
        sysctl -a 2>/dev/null | grep -E "vm.swappiness|net.core.rmem_max|net.core.wmem_max|vm.dirty_ratio|vm.dirty_background_ratio|net.ipv4.tcp_congestion_control|net.core.netdev_max_backlog|net.core.somaxconn|net.ipv4.tcp_max_syn_backlog|net.ipv4.tcp_syncookies|net.ipv4.tcp_fin_timeout|net.ipv4.tcp_tw_reuse" || echo "# 部分 sysctl 参数不可用"
        [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ] && echo "cpu_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'unknown')"
    } > "$BACKUP_FILE" || { echo -e "${RED}备份失败，请检查磁盘空间或权限${NC}"; log "备份失败"; exit 1; }

    # 应用 sysctl 优化
    echo -e "${BLUE}生成 sysctl 配置文件...${NC}"
    mkdir -p /etc/sysctl.d 2>/dev/null
    cat <<EOF > "$SYSCTL_CONF"
# 系统优化
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# TCP 网络优化
net.core.rmem_max = $rmem_max
net.core.wmem_max = $wmem_max
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
EOF
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1 || { echo -e "${RED}应用 sysctl 设置失败${NC}"; log "应用 sysctl 设置失败"; exit 1; }

    # 设置 CPU 频率管理为 performance
    if [ -d /sys/devices/system/cpu ]; then
        echo -e "${BLUE}设置 CPU 频率管理模式为 performance${NC}"
        GOVERNOR_FILES=$(ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null)
        if [ -n "$GOVERNOR_FILES" ]; then
            echo performance | tee $GOVERNOR_FILES >/dev/null 2>&1 || { echo -e "${YELLOW}设置 CPU 频率失败，可能不支持${NC}"; log "设置 CPU 频率失败"; }
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
            systemctl daemon-reload 2>/dev/null
            systemctl enable cpu-optimizer.service 2>/dev/null && systemctl start cpu-optimizer.service 2>/dev/null || { echo -e "${YELLOW}启用 CPU 服务失败，可能无 systemd${NC}"; log "启用 CPU 服务失败"; }
        fi
    fi

    echo -e "${GREEN}优化已应用并设置为永久生效！${NC}"
    log "优化应用完成"
}

# 取消优化（恢复备份并移除持久化设置）
revert_optimizations() {
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}未找到备份文件，无法恢复优化！${NC}"
        log "未找到备份文件"
        return 1
    fi

    echo -e "${YELLOW}取消优化并恢复原始设置...${NC}"
    log "开始恢复原始设置"

    while IFS=' = ' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        if [ -n "$key" ] && [ -n "$value" ]; then
            if [ "$key" = "cpu_governor" ]; then
                [ -d /sys/devices/system/cpu ] && echo "$value" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1
            else
                sysctl -w "$key=$value" >/dev/null 2>&1 || echo -e "${YELLOW}恢复 $key=$value 失败${NC}"
            fi
        fi
    done < "$BACKUP_FILE"

    [ -f "$SYSCTL_CONF" ] && rm -f "$SYSCTL_CONF"
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable cpu-optimizer.service >/dev/null 2>&1
        systemctl stop cpu-optimizer.service >/dev/null 2>&1
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload 2>/dev/null
    fi
    [ -f "$BACKUP_FILE" ] && rm -f "$BACKUP_FILE"

    echo -e "${GREEN}优化已取消，系统已恢复到原始状态！${NC}"
    log "恢复完成"
}

# 主程序
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
        1) check_optimizations ;;
        2) apply_optimizations ;;
        3) revert_optimizations ;;
        4) echo -e "${GREEN}退出脚本${NC}"; log "脚本退出"; exit 0 ;;
        *) echo -e "${RED}无效选项，请输入 1-4${NC}" ;;
    esac
done