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

# 检查内核是否支持 CPU 频率管理
check_kernel_cpufreq_support() {
    local support="yes"
    # 检查是否加载了频率管理模块
    if ! lsmod | grep -q -E "intel_pstate|acpi-cpufreq|amd_freq_sensitivity"; then
        modprobe intel_pstate 2>/dev/null || modprobe acpi-cpufreq 2>/dev/null || modprobe amd_freq_sensitivity 2>/dev/null
        if ! lsmod | grep -q -E "intel_pstate|acpi-cpufreq|amd_freq_sensitivity"; then
            support="no"
        fi
    fi
    # 检查 cpufreq 目录是否存在
    if [ ! -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        support="no"
    fi
    echo $support
}

# 升级内核以支持 CPU 频率管理
upgrade_kernel() {
    echo -e "${YELLOW}当前内核不支持 CPU 频率管理，正在升级内核...${NC}"
    log "开始升级内核以支持 CPU 频率管理"

    case $PKG_MANAGER in
        "yum")
            # CentOS 7: 使用 ELRepo 仓库升级内核
            echo -e "${BLUE}导入 ELRepo GPG 密钥和仓库...${NC}"
            rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null
            yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm || { echo -e "${RED}添加 ELRepo 仓库失败${NC}"; log "添加 ELRepo 仓库失败"; exit 1; }
            echo -e "${BLUE}安装最新主线内核...${NC}"
            yum --enablerepo=elrepo-kernel install -y kernel-ml || { echo -e "${RED}安装新内核失败${NC}"; log "安装新内核失败"; exit 1; }
            # 设置默认启动内核
            grub2-set-default 0
            echo -e "${GREEN}内核升级完成，请重启系统以应用新内核${NC}"
            log "CentOS 内核升级完成"
            NEED_REBOOT="yes"
            ;;
        "dnf")
            # CentOS 8+: 使用 ELRepo 升级内核
            echo -e "${BLUE}导入 ELRepo GPG 密钥和仓库...${NC}"
            rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null
            dnf install -y https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm || { echo -e "${RED}添加 ELRepo 仓库失败${NC}"; log "添加 ELRepo 仓库失败"; exit 1; }
            echo -e "${BLUE}安装最新主线内核...${NC}"
            dnf --enablerepo=elrepo-kernel install -y kernel-ml || { echo -e "${RED}安装新内核失败${NC}"; log "安装新内核失败"; exit 1; }
            grub2-set-default 0
            echo -e "${GREEN}内核升级完成，请重启系统以应用新内核${NC}"
            log "CentOS 8+ 内核升级完成"
            NEED_REBOOT="yes"
            ;;
        "apt-get")
            # Ubuntu: 安装 HWE 内核
            echo -e "${BLUE}安装 Ubuntu HWE 内核...${NC}"
            $INSTALL_CMD linux-generic-hwe-$(lsb_release -sr) || { echo -e "${RED}安装 HWE 内核失败${NC}"; log "安装 HWE 内核失败"; exit 1; }
            echo -e "${GREEN}内核升级完成，请重启系统以应用新内核${NC}"
            log "Ubuntu 内核升级完成"
            NEED_REBOOT="yes"
            ;;
        *)
            echo -e "${RED}不支持的包管理器，无法自动升级内核${NC}"
            log "不支持的包管理器，无法升级内核"
            exit 1
            ;;
    esac
}

# 检测发行版并安装依赖
install_dependencies() {
    echo -e "${YELLOW}检测并安装所需依赖...${NC}"
    log "开始安装依赖"

    # 检测包管理器（针对 CentOS 和 Ubuntu）
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
    for pkg in procps systemd grub2-tools; do
        if ! command -v ps >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1 || ! command -v grub2-mkconfig >/dev/null 2>&1; then
            echo -e "${BLUE}安装 $pkg...${NC}"
            $INSTALL_CMD $pkg || { echo -e "${RED}安装 $pkg 失败${NC}"; log "安装 $pkg 失败"; exit 1; }
        fi
    done

    # 检查并安装 CPU 频率管理工具
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

        # 检查内核支持并升级
        if [ "$(check_kernel_cpufreq_support)" = "no" ]; then
            upgrade_kernel
        else
            # 加载 CPU 频率模块
            echo -e "${BLUE}加载 CPU 频率模块...${NC}"
            for module in intel_pstate acpi-cpufreq amd_freq_sensitivity; do
                if modprobe $module 2>/dev/null; then
                    echo -e "${GREEN}成功加载模块: $module${NC}"
                    log "加载 CPU 频率模块: $module"
                fi
            done
            # 持久化模块加载
            for module in intel_pstate acpi-cpufreq amd_freq_sensitivity; do
                if lsmod | grep -q $module; then
                    echo $module >> /etc/modules-load.d/cpufreq.conf 2>/dev/null || echo $module >> /etc/modules
                fi
            done
        fi
    else
        echo -e "${YELLOW}未检测到 CPU 控制目录，可能为虚拟化环境${NC}"
        log "未检测到 CPU 控制目录"
        CPU_TOOL="无需安装"
    fi

    # 检查并启用 TCP BBR
    BBR_STATUS="未启用"
    if ! lsmod | grep -q tcp_bbr; then
        echo -e "${BLUE}检查并加载 TCP BBR 模块...${NC}"
        modprobe tcp_bbr 2>/dev/null
        if lsmod | grep -q tcp_bbr; then
            echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf 2>/dev/null || echo "tcp_bbr" >> /etc/modules
            BBR_STATUS="已启用"
        else
            echo -e "${YELLOW}当前内核不支持 BBR 或需手动启用${NC}"
            BBR_STATUS="不支持"
        fi
    else
        BBR_STATUS="已启用"
    fi

    echo -e "${GREEN}依赖安装完成！${NC}"
    log "依赖安装完成"
    echo -e "${BLUE}系统信息:${NC}"
    echo -e "  发行版: $DISTRO"
    echo -e "  包管理器: $PKG_MANAGER"
    echo -e "  已安装工具: procps, systemd, $CPU_TOOL"
    echo -e "  当前内核版本: $(uname -r)"
    echo -e "  CPU 核心数: $(nproc)"
    echo -e "  TCP BBR 状态: $BBR_STATUS"
    [ "$NEED_REBOOT" = "yes" ] && echo -e "${RED}请重启系统以应用新内核！${NC}"
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

    # 检查 CPU 配置并诊断原因
    if [ -d /sys/devices/system/cpu ]; then
        GOVERNOR_FILES=$(ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null)
        if [ -n "$GOVERNOR_FILES" ]; then
            CURRENT_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "不可用")
            [ "$CURRENT_GOVERNOR" = "performance" ] && echo -e "${GREEN}CPU 频率管理模式: $CURRENT_GOVERNOR (已优化)${NC}" || echo -e "${RED}CPU 频率管理模式: $CURRENT_GOVERNOR (未优化)${NC}"
        else
            echo -e "${YELLOW}CPU 频率管理模式: 不可用${NC}"
            echo -e "${BLUE}诊断:${NC}"
            if lsmod | grep -q -E "intel_pstate|acpi-cpufreq|amd_freq_sensitivity"; then
                echo -e "  - CPU 频率模块已加载，但 governor 文件不可用，可能为虚拟化限制"
            else
                echo -e "  - 未加载 CPU 频率模块，已尝试升级内核"
            fi
            log "CPU 频率管理模式不可用"
        fi
    else
        echo -e "${YELLOW}CPU 频率管理模式: 不可用 (未检测到 CPU 控制目录)${NC}"
        log "未检测到 CPU 控制目录"
    fi

    # 检查系统参数
    total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    rmem_max=$((total_mem * 1024 / 4))
    check_param "vm.swappiness" "10" "vm.swappiness"
    check_param "net.core.rmem_max" "$rmem_max" "net.core.rmem_max"
    check_param "net.core.wmem_max" "$rmem_max" "net.core.wmem_max"

    # 检查 TCP 拥塞控制
    if [ -f /proc/sys/net/ipv4/tcp_congestion_control ]; then
        CURRENT_CONGESTION=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "不可用")
        if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            [ "$CURRENT_CONGESTION" = "bbr" ] && echo -e "${GREEN}TCP 拥塞控制: $CURRENT_CONGESTION (已优化)${NC}" || echo -e "${RED}TCP 拥塞控制: $CURRENT_CONGESTION (未优化, BBR 可用但未启用)${NC}"
        else
            echo -e "${YELLOW}TCP 拥塞控制: $CURRENT_CONGESTION (BBR 不支持)${NC}"
        fi
    else
        echo -e "${YELLOW}TCP 拥塞控制: 不可用${NC}"
    fi

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
        if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
            governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
            echo "cpu_governor=$governor"
        fi
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

    # 检查并启用 BBR
    if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYSCTL_CONF"
    fi
    sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1 || { echo -e "${RED}应用 sysctl 设置失败${NC}"; log "应用 sysctl 设置失败"; exit 1; }

    # 设置 CPU 频率管理为 performance
    if [ -d /sys/devices/system/cpu ]; then
        GOVERNOR_FILES=$(ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null)
        if [ -n "$GOVERNOR_FILES" ]; then
            echo -e "${BLUE}设置 CPU 频率管理模式为 performance${NC}"
            echo performance | tee $GOVERNOR_FILES >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${YELLOW}设置 CPU 频率失败，可能权限不足或硬件不支持${NC}"
                log "设置 CPU 频率失败"
            else
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
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl daemon-reload 2>/dev/null
                    systemctl enable cpu-optimizer.service 2>/dev/null && systemctl start cpu-optimizer.service 2>/dev/null
                    if [ $? -ne 0 ]; then
                        echo -e "${YELLOW}启用 CPU 服务失败，请检查 systemd 配置${NC}"
                        log "启用 CPU 服务失败"
                    fi
                else
                    echo -e "${YELLOW}系统不支持 systemd，CPU 频率设置将不持久${NC}"
                    log "无 systemd 支持"
                fi
            fi
        else
            echo -e "${YELLOW}CPU 频率管理文件不可用，已尝试升级内核${NC}"
            log "CPU 频率管理文件不可用"
        fi
    fi

    echo -e "${GREEN}优化已应用并设置为永久生效！${NC}"
    log "优化应用完成"
    [ "$NEED_REBOOT" = "yes" ] && echo -e "${RED}请重启系统以应用新内核！${NC}"
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

    # 恢复 sysctl 设置
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

    # 删除持久化文件
    [ -f "$SYSCTL_CONF" ] && rm -f "$SYSCTL_CONF"
    if [ -f "$SERVICE_FILE" ]; then
        systemctl disable cpu-optimizer.service >/dev/null 2>&1
        systemctl stop cpu-optimizer.service >/dev/null 2>&1
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload 2>/dev/null
    fi

    # 清理备份文件
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