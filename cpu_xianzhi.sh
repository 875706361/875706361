#!/bin/bash

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[36m"
RESET="\033[0m"
BOLD="\033[1m"

LOG_FILE="/var/log/secure_env_setup.log"
CPU_LIMIT_SCRIPT="/usr/local/bin/cpu_limit.sh"
CPU_LIMIT_SERVICE="/etc/systemd/system/cpu_limit.service"
export DEBIAN_FRONTEND=noninteractive

log() {
    echo -e "$(date '+%F %T') - $1" | tee -a "$LOG_FILE"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_LIKE=$ID_LIKE
    else
        echo -e "${RED}无法识别的系统，不支持自动安全配置${RESET}"
        exit 1
    fi
}

inst() {
    for pkg in "$@"; do
        if ! command -v $pkg &>/dev/null; then
            echo -e "${YELLOW}正在安装 $pkg ...${RESET}"
            log "正在安装 $pkg ..."
            case "$OS_ID" in
                ubuntu|debian)
                    apt-get update && apt-get install -y $pkg
                    ;;
                centos|almalinux|rocky|rhel)
                    yum install -y epel-release
                    yum install -y $pkg
                    ;;
                *)
                    if [[ "$OS_LIKE" =~ "debian" ]]; then
                        apt-get update && apt-get install -y $pkg
                    elif [[ "$OS_LIKE" =~ "rhel" ]]; then
                        yum install -y epel-release
                        yum install -y $pkg
                    else
                        echo -e "${RED}未知系统：请手动安装 $pkg${RESET}"
                        log "未知系统：请手动安装 $pkg"
                    fi
                ;;
            esac
        else
            echo -e "${GREEN}$pkg 已安装${RESET}"
            log "$pkg 已安装"
        fi
    done
}

setup_firewall_openall() {
    echo -e "${YELLOW}配置防火墙为全部端口开放...${RESET}"
    log "配置防火墙(全部端口开放)"
    case "$OS_ID" in
        ubuntu|debian)
            inst ufw
            echo -e "${BLUE}重置并开放所有端口(UFW)...${RESET}"
            ufw --force reset
            ufw default allow incoming
            ufw default allow outgoing
            ufw --force enable
            ;;
        centos|almalinux|rocky|rhel)
            inst firewalld
            systemctl enable firewalld --now
            echo -e "${BLUE}firewalld切换到trusted（全部端口开放）...${RESET}"
            firewall-cmd --set-default-zone=trusted
            firewall-cmd --reload
            ;;
        *)
            if [[ "$OS_LIKE" =~ "debian" ]]; then
                inst ufw
                ufw --force reset
                ufw default allow incoming
                ufw default allow outgoing
                ufw --force enable
            elif [[ "$OS_LIKE" =~ "rhel" ]]; then
                inst firewalld
                systemctl enable firewalld --now
                firewall-cmd --set-default-zone=trusted
                firewall-cmd --reload
            fi
            ;;
    esac
    echo -e "${GREEN}防火墙已全部开放！${RESET}"
}

install_security_tools() {
    echo -e "${YELLOW}安装安全工具...${RESET}"
    log "安装安全工具"
    inst fail2ban
    inst rkhunter
    inst chkrootkit
    inst auditd
    inst clamav

    if systemctl list-unit-files | grep -q fail2ban; then
        systemctl enable fail2ban --now
        echo -e "${GREEN}fail2ban 已启动${RESET}"
        log "fail2ban 已启动"
    fi

    if command -v freshclam &>/dev/null; then
        freshclam
        echo -e "${GREEN}ClamAV 病毒库已更新${RESET}"
        log "ClamAV 病毒库已更新"
    fi

    if systemctl list-unit-files | grep -q auditd; then
        systemctl enable auditd --now
        echo -e "${GREEN}auditd 已启动${RESET}"
        log "auditd 已启动"
    fi
    echo -e "${GREEN}安全工具安装完成！${RESET}"
}

install_cpulimit() {
    echo -e "${YELLOW}安装cpulimit...${RESET}"
    inst cpulimit
}

create_cpu_limit_script() {
    echo -e "${YELLOW}创建CPU限制监控脚本...${RESET}"
    log "创建CPU限制监控脚本..."
    cat > "$CPU_LIMIT_SCRIPT" <<'EOF'
#!/bin/bash

LOG_FILE="/var/log/cpu_limit.log"
CPU_THRESHOLD=90
LIMIT_RATE=90
XRAY_LIMIT=50
CHECK_INTERVAL=5

log() {
    echo "$(date '+%F %T') - $1" >> "$LOG_FILE"
}

log "===== 启动 CPU 限制进程 ====="

while true; do
    # 针对xray/x-ui进程专用限制
    for xpid in $(pgrep -f "xray|x-ui"); do
        if ! pgrep -f "cpulimit.*-p $xpid" > /dev/null; then
            log "限制xray/x-ui进程 PID=$xpid CPU到${XRAY_LIMIT}%"
            cpulimit -p $xpid -l $XRAY_LIMIT -b
        fi
    done

    # 检查所有高CPU进程(非xray/x-ui)
    high_cpu_pids=$(ps -eo pid,%cpu,comm --no-headers --sort=-%cpu | awk -v th=$CPU_THRESHOLD '$2>th{print $1","$3}')
    for entry in $high_cpu_pids; do
        pid="${entry%%,*}"
        name="${entry##*,}"
        [[ "$name" =~ ^xray$|^x-ui$ ]] && continue
        if ! pgrep -f "cpulimit.*-p $pid" > /dev/null; then
            if [ -d "/proc/$pid" ]; then
                log "限制进程 $pid ($name) CPU占用>${CPU_THRESHOLD}%，限制到${LIMIT_RATE}%"
                cpulimit -p "$pid" -l $LIMIT_RATE -b
            fi
        fi
    done

    # 检测“隐藏”进程
    ps_pids=$(ps -e -o pid=)
    proc_pids=$(ls /proc | grep -E '^[0-9]+$')
    for proc_pid in $proc_pids; do
        if ! echo "$ps_pids" | grep -qw "$proc_pid"; then
            if [ -r "/proc/$proc_pid/cmdline" ]; then
                cpu=$(ps -p $proc_pid -o %cpu= 2>/dev/null | awk '{print int($1)}')
                if [ ! -z "$cpu" ] && [ "$cpu" -gt "$CPU_THRESHOLD" ]; then
                    if ! pgrep -f "cpulimit.*-p $proc_pid" > /dev/null; then
                        log "检测到隐藏高CPU进程 $proc_pid (CPU=$cpu%)，尝试限制"
                        cpulimit -p "$proc_pid" -l $LIMIT_RATE -b
                    fi
                fi
            fi
        fi
    done

    sleep $CHECK_INTERVAL
done
EOF

    chmod +x "$CPU_LIMIT_SCRIPT"
    echo -e "${GREEN}CPU限制脚本已创建：$CPU_LIMIT_SCRIPT${RESET}"
    log "CPU限制脚本已创建：$CPU_LIMIT_SCRIPT"
}

create_cpu_limit_service() {
    echo -e "${YELLOW}创建CPU限制systemd服务...${RESET}"
    log "创建CPU限制systemd服务..."
    cat > "$CPU_LIMIT_SERVICE" <<EOF
[Unit]
Description=CPU 限制进程守护
After=network.target

[Service]
ExecStart=$CPU_LIMIT_SCRIPT
Restart=always
RestartSec=5
User=root
StandardOutput=append:/var/log/cpu_limit.log
StandardError=append:/var/log/cpu_limit.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable cpu_limit.service
    systemctl restart cpu_limit.service
    echo -e "${GREEN}CPU限制服务已启用并自启！${RESET}"
    log "CPU限制服务已启用并自启"
}

remove_cpu_limit() {
    echo -e "${YELLOW}正在卸载CPU限制服务和脚本...${RESET}"
    systemctl stop cpu_limit.service 2>/dev/null
    systemctl disable cpu_limit.service 2>/dev/null
    rm -f "$CPU_LIMIT_SERVICE"
    rm -f "$CPU_LIMIT_SCRIPT"
    systemctl daemon-reload
    echo -e "${GREEN}CPU限制服务与脚本已卸载${RESET}"
    log "CPU限制服务与脚本已卸载"
}

main_menu() {
    detect_os
    while true; do
        clear
        echo -e "${BOLD}${BLUE}=============================="
        echo -e "  VPS安全环境 & CPU限制管理器"
        echo -e "==============================${RESET}"
        echo -e "${YELLOW}1. 安装常用安全工具${RESET}"
        echo -e "${YELLOW}2. 配置防火墙（全部端口开放）${RESET}"
        echo -e "${YELLOW}3. 部署并启用CPU限制服务${RESET}"
        echo -e "${YELLOW}4. 卸载CPU限制服务${RESET}"
        echo -e "${YELLOW}5. 退出${RESET}"
        echo -e "${BLUE}------------------------------${RESET}"
        read -p "$(echo -e "${BOLD}请选择操作 [1-5]：${RESET}")" choice
        case "$choice" in
            1)
                install_security_tools
                echo -e "${GREEN}已完成，按回车继续...${RESET}" ; read
                ;;
            2)
                setup_firewall_openall
                echo -e "${GREEN}已完成，按回车继续...${RESET}" ; read
                ;;
            3)
                install_cpulimit
                create_cpu_limit_script
                create_cpu_limit_service
                echo -e "${GREEN}已完成，按回车继续...${RESET}" ; read
                ;;
            4)
                remove_cpu_limit
                echo -e "${GREEN}已完成，按回车继续...${RESET}" ; read
                ;;
            5)
                echo -e "${BOLD}${BLUE}退出。日志见：$LOG_FILE${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}请输入1-5之间的数字！${RESET}"
                sleep 1
                ;;
        esac
    done
}

main_menu
