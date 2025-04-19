#!/bin/bash

# 如果没有被cpulimit限制，则用cpulimit重新调用本脚本
if [ -z "$CPULIMIT_STARTED" ]; then
    if ! command -v cpulimit >/dev/null 2>&1; then
        echo "正在安装cpulimit..."
        # 检测操作系统并安装 cpulimit
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS_ID_TEMP=$ID
            OS_LIKE_TEMP=$ID_LIKE
            PKG_MANAGER_TEMP=""
            if command -v dnf &>/dev/null; then PKG_MANAGER_TEMP="dnf";
            elif command -v yum &>/dev/null; then PKG_MANAGER_TEMP="yum";
            elif command -v apt-get &>/dev/null; then PKG_MANAGER_TEMP="apt-get";
            else echo "无法检测到 apt, yum 或 dnf 包管理器，请手动安装 cpulimit。"; exit 1; fi

            case "$OS_ID_TEMP" in
                ubuntu|debian) echo "检测到 Debian/Ubuntu 系统..."; apt-get update -y && apt-get install -y cpulimit ;;
                centos|almalinux|rocky|rhel)
                    echo "检测到 RHEL/CentOS 系列系统..."
                    if ! rpm -q epel-release &>/dev/null; then
                        echo "安装 EPEL release..."; $PKG_MANAGER_TEMP install -y epel-release
                        if ! rpm -q epel-release &>/dev/null; then echo "EPEL release 安装失败，请检查网络或手动安装后再试。"; exit 1; fi
                    fi
                    echo "安装 cpulimit..."; $PKG_MANAGER_TEMP install -y cpulimit ;;
                *)
                    if [[ "$OS_LIKE_TEMP" =~ "debian" ]]; then echo "检测到类 Debian 系统..."; apt-get update -y && apt-get install -y cpulimit
                    elif [[ "$OS_LIKE_TEMP" =~ "rhel" ]]; then
                        echo "检测到类 RHEL 系统...";
                        if ! rpm -q epel-release &>/dev/null; then
                            echo "安装 EPEL release..."; $PKG_MANAGER_TEMP install -y epel-release
                            if ! rpm -q epel-release &>/dev/null; then echo "EPEL release 安装失败，请检查网络或手动安装后再试。"; exit 1; fi
                        fi
                        echo "安装 cpulimit..."; $PKG_MANAGER_TEMP install -y cpulimit
                    else echo "无法自动识别的 Linux 发行版 ($OS_ID_TEMP / $OS_LIKE_TEMP)。请手动安装 cpulimit。"; exit 1; fi ;;
            esac
            if ! command -v cpulimit >/dev/null 2>&1; then echo "cpulimit 安装失败，请检查之前的错误信息或手动安装。"; exit 1; fi
        else echo "无法找到 /etc/os-release 文件。请手动安装 cpulimit。"; exit 1; fi
         echo "cpulimit 安装完成。"
    fi
    echo -e "\033[33m[INFO]\033[0m 本脚本将以最大CPU 80%限制方式运行..."
    export CPULIMIT_STARTED=1
    exec cpulimit -l 80 -- bash "$0" "$@"
    exit 1
fi

# 彩色定义
GREEN="\033[32m"; RED="\033[31m"; YELLOW="\033[33m"; BLUE="\033[36m"; RESET="\033[0m"; BOLD="\033[1m"
LOG_FILE="/var/log/secure_env_setup.log"; CPU_LIMIT_SCRIPT="/usr/local/bin/cpu_limit.sh"; CPU_LIMIT_SERVICE="/etc/systemd/system/cpu_limit.service"
export DEBIAN_FRONTEND=noninteractive

# 日志记录函数
log() { echo -e "$(date '+%F %T') - $1" | tee -a "$LOG_FILE"; }

# 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then . /etc/os-release; OS_ID=$ID; OS_LIKE=$ID_LIKE;
    else echo -e "${RED}无法识别的系统...${RESET}"; log "错误：无法识别的系统..."; exit 1; fi
    log "检测到操作系统: ID=$OS_ID, ID_LIKE=$OS_LIKE"
}

# 统一的包安装函数
inst() {
    for pkg in "$@"; do
        cmd_to_check_pre="$pkg"; if [ "$pkg" == "fail2ban" ]; then cmd_to_check_pre="fail2ban-client"; fi
        if command -v "$cmd_to_check_pre" &>/dev/null; then echo -e "${GREEN}$pkg (命令: $cmd_to_check_pre) 已安装${RESET}"; log "$pkg 已安装"; continue; fi

        echo -e "${YELLOW}正在安装 $pkg ...${RESET}"; log "正在安装 $pkg ..."
        PKG_MANAGER=""; if command -v dnf &>/dev/null; then PKG_MANAGER="dnf"; elif command -v yum &>/dev/null; then PKG_MANAGER="yum"; elif command -v apt-get &>/dev/null; then PKG_MANAGER="apt-get"; else echo -e "${RED}错误：无法找到包管理器！${RESET}"; log "错误：无法找到包管理器"; exit 1; fi
        log "使用包管理器: $PKG_MANAGER"; echo -e "${BLUE}使用包管理器: $PKG_MANAGER${RESET}"; INSTALL_LOG=""

        case "$OS_ID" in
            ubuntu|debian) INSTALL_LOG="/tmp/apt-install-$pkg.log"; echo -e "${BLUE}>>> $PKG_MANAGER update${RESET}"; $PKG_MANAGER update -y > /tmp/apt-update.log 2>&1; echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"; $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1 ;;
            centos|almalinux|rocky|rhel)
                INSTALL_LOG="/tmp/$PKG_MANAGER-install-$pkg.log"
                if ! rpm -q epel-release &>/dev/null; then echo -e "${BLUE}>>> $PKG_MANAGER install -y epel-release${RESET}"; $PKG_MANAGER install -y epel-release > /tmp/$PKG_MANAGER-epel.log 2>&1; if ! rpm -q epel-release &>/dev/null; then echo -e "${RED}!!! EPEL 安装失败...${RESET}"; log "错误：EPEL 安装失败"; exit 1; else echo -e "${GREEN}EPEL 已安装${RESET}"; log "EPEL 已安装"; echo -e "${BLUE}>>> $PKG_MANAGER makecache${RESET}"; $PKG_MANAGER makecache > /tmp/$PKG_MANAGER-makecache.log 2>&1; fi
                else echo -e "${GREEN}EPEL 已存在${RESET}"; log "EPEL 已存在"; fi; echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"; $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1 ;;
            *)
                if [[ "$OS_LIKE" =~ "debian" ]]; then PKG_MANAGER="apt-get"; INSTALL_LOG="/tmp/apt-install-$pkg.log"; log "类 Debian 系统"; echo -e "${BLUE}>>> $PKG_MANAGER update${RESET}"; $PKG_MANAGER update -y > /tmp/apt-update.log 2>&1; echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"; $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1
                elif [[ "$OS_LIKE" =~ "rhel" ]]; then INSTALL_LOG="/tmp/$PKG_MANAGER-install-$pkg.log"; log "类 RHEL 系统"; if ! rpm -q epel-release &>/dev/null; then echo -e "${BLUE}>>> $PKG_MANAGER install -y epel-release${RESET}"; $PKG_MANAGER install -y epel-release > /tmp/$PKG_MANAGER-epel.log 2>&1; if ! rpm -q epel-release &>/dev/null; then echo -e "${RED}!!! EPEL 安装失败...${RESET}"; log "错误：EPEL 安装失败"; exit 1; else echo -e "${GREEN}EPEL 已安装${RESET}"; log "EPEL 已安装"; echo -e "${BLUE}>>> $PKG_MANAGER makecache${RESET}"; $PKG_MANAGER makecache > /tmp/$PKG_MANAGER-makecache.log 2>&1; fi else echo -e "${GREEN}EPEL 已存在${RESET}"; log "EPEL 已存在"; fi; echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"; $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1
                else echo -e "${RED}警告：无法自动安装 $pkg...${RESET}"; log "警告：无法自动安装 $pkg"; continue; fi ;;
        esac

        hash -r; log "执行 hash -r"; cmd_to_check="$pkg"; if [ "$pkg" == "fail2ban" ]; then cmd_to_check="fail2ban-client"; log "检查命令: $cmd_to_check"; fi; log "验证命令: $cmd_to_check"

        if ! command -v "$cmd_to_check" &>/dev/null; then
            pm_success_likely=false; if [ -f "$INSTALL_LOG" ] && [ -s "$INSTALL_LOG" ] && tail "$INSTALL_LOG" | grep -Eiq "complete|installed|已安装"; then pm_success_likely=true; log "日志 $INSTALL_LOG 显示可能成功"; fi
            if $pm_success_likely; then echo -e "${RED}!!! 警告：$pkg 可能已安装，但命令 '$cmd_to_check' 未找到。请手动确认。脚本继续...${RESET}"; log "警告：$pkg 可能已安装但命令 '$cmd_to_check' 未找到。继续..."
            else echo -e "${RED}!!! $pkg 安装失败。无法找到命令 '$cmd_to_check'。日志: $INSTALL_LOG ${RESET}"; log "错误: $pkg 安装失败。日志: $INSTALL_LOG"; exit 1; fi
        else echo -e "${GREEN}$pkg (命令: $cmd_to_check) 安装验证成功！${RESET}"; log "$pkg 安装验证成功"; fi
    done
}

# 配置防火墙，开放所有端口 (已修改 firewalld 逻辑)
setup_firewall_openall() {
    echo -e "${YELLOW}配置防火墙为全部端口开放...${RESET}"; log "配置防火墙(全部端口开放)"
    FW_CONFIGURED=false
    case "$OS_ID" in
        ubuntu|debian)
            inst ufw; echo -e "${BLUE}重置并开放所有端口(UFW)...${RESET}"; ufw --force reset; ufw default allow incoming; ufw default allow outgoing; ufw --force enable; log "UFW 已重置并设置为允许所有连接"; FW_CONFIGURED=true ;;
        centos|almalinux|rocky|rhel)
            inst firewalld # 确保 firewalld 已安装
            # 启用并立即启动 firewalld 服务
            systemctl enable firewalld --now
            echo -e "${BLUE}将 firewalld 默认区域设置为 trusted...${RESET}"
            # 设置默认区域为 trusted (对将来未分配的接口生效)
            firewall-cmd --set-default-zone=trusted --permanent
            log "firewalld 默认区域已永久设置为 trusted"

            echo -e "${BLUE}将当前活动的网络接口移动到 trusted 区域...${RESET}"
            # 获取当前所有活动的非 trusted 区域及其接口列表 (排除 lo)
            for zone in $(firewall-cmd --get-active-zones | grep -v '^\s*trusted$' | grep -v '^\s*$'); do
                interfaces=$(firewall-cmd --zone=$zone --list-interfaces)
                for iface in $interfaces; do
                    if [[ "$iface" != "lo" ]]; then
                        echo -e "${YELLOW}  - 正在将接口 '$iface' 从区域 '$zone' 移动到 'trusted' 区域...${RESET}"
                        log "将接口 '$iface' 从区域 '$zone' 移动到 'trusted' 区域 (运行时和永久)"
                        # 使用 change-interface 同时处理运行时和永久配置
                        firewall-cmd --zone=trusted --change-interface=$iface --permanent
                        # 为确保运行时立即生效（有时reload后网络管理器会干扰），再加一次运行时命令
                        firewall-cmd --zone=trusted --add-interface=$iface 2>/dev/null || true # 忽略可能已存在的错误
                    fi
                done
            done

            echo -e "${BLUE}重新加载 firewalld 配置使其生效...${RESET}"
            firewall-cmd --reload
            log "执行 firewall-cmd --reload"

            # 验证活动区域 (可选，用于调试)
            echo -e "${BLUE}验证：当前活动的区域和接口：${RESET}"
            firewall-cmd --get-active-zones
            log "当前活动的区域和接口："
            firewall-cmd --get-active-zones | while IFS= read -r line; do log "  $line"; done
            FW_CONFIGURED=true
            ;;
        *)
            # 尝试根据 OS_LIKE 处理 (简化版，未包含接口移动逻辑)
            if [[ "$OS_LIKE" =~ "debian" ]]; then inst ufw; ufw --force reset; ufw default allow incoming; ufw default allow outgoing; ufw --force enable; log "UFW (类Debian) 已重置并设置为允许所有连接"; FW_CONFIGURED=true
            elif [[ "$OS_LIKE" =~ "rhel" ]]; then inst firewalld; systemctl enable firewalld --now; firewall-cmd --set-default-zone=trusted --permanent; firewall-cmd --reload; log "firewalld (类RHEL) 默认区域已设置为 trusted (未移动活动接口)"; FW_CONFIGURED=true # 注意：这里的 fallback 可能不如主 case 完善
            else echo -e "${RED}警告：无法为此系统自动配置防火墙。${RESET}"; log "警告：无法自动配置防火墙 ($OS_ID / $OS_LIKE)"; fi ;;
    esac

    if $FW_CONFIGURED; then echo -e "${GREEN}防火墙配置完成！${RESET}"; else echo -e "${YELLOW}防火墙未自动配置。${RESET}"; fi
    echo -e "${YELLOW}提示：为了让 Fail2ban 的端口扫描防护生效，您可能需要配置防火墙记录被拒绝的连接。${RESET}"
    echo -e "${YELLOW}      例如: sudo firewall-cmd --set-log-denied=all (请注意日志量!) ${RESET}"
    log "提示用户需手动配置防火墙日志以启用portscan检测"
}


# 安装并配置 fail2ban (自动开启 SSH/系统登录/Apache/端口扫描 防护)
install_full_fail2ban() {
    echo -e "${YELLOW}安装并配置 fail2ban ...${RESET}"; log "安装并配置 fail2ban"
    inst fail2ban

    FJB_CONF="/etc/fail2ban/jail.local"; echo -e "${BLUE}生成 fail2ban 配置文件: $FJB_CONF ...${RESET}"; log "生成 $FJB_CONF"
    cat > "$FJB_CONF" <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1; bantime = 3600; findtime = 600; maxretry = 5; backend = systemd
destemail = root@localhost; sender = fail2ban@$(hostname -f || echo 'localhost'); mta = sendmail; action = %(action_mwl)s
[sshd]
enabled = true; port = ssh; logpath = %(sshd_log)s
[systemd-logind]
enabled = true
[vsftpd]
enabled = false; port = ftp,ftp-data,ftps,ftps-data; logpath = /var/log/vsftpd.log
[proftpd]
enabled = false; port = ftp,ftp-data,ftps,ftps-data; logpath = /var/log/proftpd/proftpd.log
[postfix]
enabled = false; port = smtp,465,submission; logpath = /var/log/mail.log
[dovecot]
enabled = false; port = pop3,pop3s,imap,imaps; logpath = /var/log/mail.log
[nginx-http-auth]
enabled = false; port = http,https; logpath = /var/log/nginx/error.log
[apache-auth]
enabled = false; port = http,https; logpath = /var/log/apache*/error.log
[apache-badbots]
enabled = true; port = http,https; logpath = /var/log/apache*/access.log; maxretry = 2 # Assume Apache used
[apache-noscript]
enabled = false; port = http,https; logpath = /var/log/apache*/error.log; maxretry = 2
[apache-overflows]
enabled = false; port = http,https; logpath = /var/log/apache*/error.log; maxretry = 2
[portscan]
# !! 重要: 依赖防火墙日志记录 (如 firewalld --set-log-denied=all).
enabled = true; filter = portscan; maxretry = 2; findtime = 600; bantime = 86400 # logpath omitted for journald
EOF
    log "$FJB_CONF 已生成 (SSH, systemd-logind, apache-badbots, portscan 默认启用)。"

    if [ ! -f /etc/fail2ban/filter.d/nginx-http-auth.conf ]; then echo -e "${BLUE}创建 Nginx HTTP Auth 过滤器...${RESET}"; log "创建 Nginx 过滤器"; cat > /etc/fail2ban/filter.d/nginx-http-auth.conf <<'EOL'
[Definition]
failregex = ^ \[error\] \d+#\d+: \*\d+ user "\S+":? password mismatch, client: <HOST>,.*$
            ^ \[error\] \d+#\d+: \*\d+ no user/password was provided.*client: <HOST>,.*$
            ^ \[error\] \d+#\d+: \*\d+ user "\S+" was not found.*client: <HOST>,.*$
ignoreregex =
EOL
    fi

    PORTSCAN_FILTER="/etc/fail2ban/filter.d/portscan.conf"
    if [ ! -f "$PORTSCAN_FILTER" ]; then echo -e "${BLUE}创建 portscan 过滤器 ($PORTSCAN_FILTER)...${RESET}"; log "创建 portscan 过滤器"; cat > "$PORTSCAN_FILTER" <<'EOL'
# /etc/fail2ban/filter.d/portscan.conf
[INCLUDES]
before = common.conf
[Definition]
failregex = %%s(?:firewalld|kernel):\s+.*(?:REJECT|DROP)\s+.*SRC=<HOST>\s+.*DPT=\d+.*%%s
ignoreregex =
[Init]
journalmatch = _SYSTEMD_UNIT=firewalld.service + _COMM=firewalld
# journalmatch = _TRANSPORT=kernel
EOL
    else echo -e "${GREEN}Portscan 过滤器 $PORTSCAN_FILTER 已存在。${RESET}"; log "$PORTSCAN_FILTER 已存在。"; fi

    echo -e "${BLUE}启用并重启 fail2ban 服务...${RESET}"; systemctl enable fail2ban --now; sleep 1; systemctl restart fail2ban; log "尝试启用并重启 fail2ban。"
    echo -e "${BLUE}等待 fail2ban 服务启动...${RESET}"; sleep 3
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}fail2ban 已成功配置并启动。${RESET}"; echo -e "${BLUE}已默认启用 SSH、系统登录、Apache爬虫、端口扫描 防护。${RESET}"
        echo -e "${YELLOW}警告：端口扫描防护依赖于防火墙正确记录被拒绝的连接。${RESET}"; echo -e "${YELLOW}      您可能需要手动配置防火墙日志 (如 sudo firewall-cmd --set-log-denied=all)。${RESET}"
        echo -e "${BLUE}如需调整, 请编辑 $FJB_CONF, 然后运行 'systemctl restart fail2ban'。${RESET}"; log "Fail2ban 配置完成 (portscan 依赖日志)。"
    else echo -e "${RED}Fail2ban 服务启动失败！请检查日志... ${RESET}"; log "错误：Fail2ban 启动失败！"; fi
}

# 安装 cpulimit
install_cpulimit() { echo -e "${YELLOW}检查并安装 cpulimit...${RESET}"; inst cpulimit; }

# 创建 CPU 限制监控脚本
create_cpu_limit_script() {
    echo -e "${YELLOW}创建CPU限制监控脚本...${RESET}"; log "创建CPU限制监控脚本..."
    cat > "$CPU_LIMIT_SCRIPT" <<'EOF'
#!/bin/bash
LOG_FILE="/var/log/cpu_limit.log"; CPU_THRESHOLD=80; LIMIT_RATE=80; XRAY_LIMIT=80; CHECK_INTERVAL=5
log() { echo "$(date '+%F %T') - $1" >> "$LOG_FILE"; }
log "===== 启动 CPU 限制监控守护进程 (v2) ====="
while true; do
    ps -eo pid,%cpu,args --no-headers --sort=-%cpu | awk -v ct="$CPU_THRESHOLD" -v lr="$LIMIT_RATE" -v xl="$XRAY_LIMIT" -v log_file="$LOG_FILE" 'function log_msg(l,m){printf "%s - [%s] %s\n",strftime("%F %T"),l,m>>log_file;fflush(log_file)}{pid=$1;cpu=int($2);cmd=$3;fc="";for(i=3;i<=NF;i++)fc=fc $i" ";if(cmd~/^\[.+\]$/||cmd=="awk"||cmd=="cpulimit"||fc~/cpu_limit\.sh/)next;if(cpu>=ct){lt=lr;pt="常规高CPU";if(fc~/xray|x-ui/){lt=xl;pt="xray/x-ui"}check="pgrep -f \"cpulimit .* -p "pid"\" > /dev/null";if(system(check)!=0){log_msg("INFO",sprintf("检测%s:PID=%d(%s),CPU=%d%%>=%d%%.限制%d%%",pt,pid,cmd,cpu,ct,lt));lc=sprintf("cpulimit -p %d -l %d -b",pid,lt);ret=system(lc);if(ret!=0)log_msg("WARN",sprintf("启动cpulimit失败 PID=%d(%s),Ret:%d",pid,cmd,ret))}}}'
    sleep "$CHECK_INTERVAL"
done
EOF
    chmod +x "$CPU_LIMIT_SCRIPT"; echo -e "${GREEN}CPU限制监控脚本已创建：$CPU_LIMIT_SCRIPT ${RESET}"; log "CPU限制监控脚本已创建"
}

# 创建 CPU 限制的 systemd 服务单元
create_cpu_limit_service() {
    echo -e "${YELLOW}创建CPU限制systemd服务...${RESET}"; log "创建CPU限制systemd服务..."
    cat > "$CPU_LIMIT_SERVICE" <<EOF
[Unit]
Description=CPU Usage Limiter Service; After=network.target
[Service]
ExecStart=$CPU_LIMIT_SCRIPT; Restart=always; RestartSec=5; User=root; StandardOutput=null; StandardError=null
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable cpu_limit.service; systemctl restart cpu_limit.service; log "CPU限制服务配置文件已创建"
    echo -e "${BLUE}等待 CPU 限制服务启动...${RESET}"; sleep 3
    if systemctl is-active --quiet cpu_limit.service; then echo -e "${GREEN}CPU限制服务已成功启用并启动！${RESET}"; log "CPU限制服务已启动";
    else echo -e "${RED}CPU限制服务启动失败！检查日志...${RESET}"; log "错误：CPU限制服务启动失败！"; fi
}

# 卸载 CPU 限制功能
remove_cpu_limit() {
    echo -e "${YELLOW}正在卸载CPU限制服务和脚本...${RESET}"; log "卸载CPU限制..."
    systemctl stop cpu_limit.service 2>/dev/null; systemctl disable cpu_limit.service 2>/dev/null
    echo -e "${BLUE}删除 $CPU_LIMIT_SERVICE ${RESET}"; rm -f "$CPU_LIMIT_SERVICE"
    echo -e "${BLUE}删除 $CPU_LIMIT_SCRIPT ${RESET}"; rm -f "$CPU_LIMIT_SCRIPT"; systemctl daemon-reload
    echo -e "${BLUE}停止残留 cpulimit 进程...${RESET}"; pkill -f "cpulimit .* -p"; log "尝试停止残留cpulimit"
    echo -e "${GREEN}CPU限制服务与脚本已卸载完成。${RESET}"; log "CPU限制卸载完成。"
}

# 主菜单函数
main_menu() {
    detect_os
    while true; do
        clear; echo -e "${BOLD}${BLUE}=============================="; echo -e "  VPS安全环境 & CPU限制管理器"; echo -e "==============================${RESET}"
        echo -e "${YELLOW}1. 安装并配置 fail2ban（自动开启SSH/系统登录/Apache/端口扫描基础防护）${RESET}"
        echo -e "${YELLOW}2. 配置防火墙（设置为全部端口开放 - ${RED}不建议用于生产环境${RESET}${YELLOW}）${RESET}"
        echo -e "${YELLOW}3. 部署并启用CPU限制服务（监控并限制高CPU进程）${RESET}"
        echo -e "${YELLOW}4. 卸载CPU限制服务和脚本${RESET}"
        echo -e "${YELLOW}5. 退出脚本${RESET}"; echo -e "${BLUE}------------------------------${RESET}"
        read -p "$(echo -e "${BOLD}请选择操作 [1-5]：${RESET}")" choice
        case "$choice" in
            1) install_full_fail2ban; echo -e "\n${GREEN}操作完成，按 Enter 继续...${RESET}"; read -r ;;
            2) setup_firewall_openall; echo -e "\n${GREEN}操作完成，按 Enter 继续...${RESET}"; read -r ;;
            3) install_cpulimit; create_cpu_limit_script; create_cpu_limit_service; echo -e "\n${GREEN}操作完成，按 Enter 继续...${RESET}"; read -r ;;
            4) remove_cpu_limit; echo -e "\n${GREEN}操作完成，按 Enter 继续...${RESET}"; read -r ;;
            5) echo -e "\n${BOLD}${BLUE}脚本已退出。日志: $LOG_FILE${RESET}"; exit 0 ;;
            *) echo -e "\n${RED}输入错误！请输入 1-5。${RESET}"; sleep 2 ;;
        esac
    done
}

# --- 脚本主入口 ---
main_menu
