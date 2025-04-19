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
            if command -v dnf &>/dev/null; then
                PKG_MANAGER_TEMP="dnf"
            elif command -v yum &>/dev/null; then
                PKG_MANAGER_TEMP="yum"
            elif command -v apt-get &>/dev/null; then
                 PKG_MANAGER_TEMP="apt-get"
            else
                 echo "无法检测到 apt, yum 或 dnf 包管理器，请手动安装 cpulimit。"
                 exit 1
            fi

            case "$OS_ID_TEMP" in
                ubuntu|debian)
                    echo "检测到 Debian/Ubuntu 系统..."
                    apt-get update -y && apt-get install -y cpulimit
                    ;;
                centos|almalinux|rocky|rhel)
                    echo "检测到 RHEL/CentOS 系列系统..."
                    if ! rpm -q epel-release &>/dev/null; then
                        echo "安装 EPEL release..."
                        $PKG_MANAGER_TEMP install -y epel-release
                        if ! rpm -q epel-release &>/dev/null; then
                           echo "EPEL release 安装失败，请检查网络或手动安装后再试。"
                           exit 1
                        fi
                    fi
                    echo "安装 cpulimit..."
                    $PKG_MANAGER_TEMP install -y cpulimit
                    ;;
                *)
                    # 尝试基于 ID_LIKE 判断
                    if [[ "$OS_LIKE_TEMP" =~ "debian" ]]; then
                        echo "检测到类 Debian 系统..."
                        apt-get update -y && apt-get install -y cpulimit
                    elif [[ "$OS_LIKE_TEMP" =~ "rhel" ]]; then
                        echo "检测到类 RHEL 系统..."
                        if ! rpm -q epel-release &>/dev/null; then
                            echo "安装 EPEL release..."
                            $PKG_MANAGER_TEMP install -y epel-release
                           if ! rpm -q epel-release &>/dev/null; then
                               echo "EPEL release 安装失败，请检查网络或手动安装后再试。"
                               exit 1
                            fi
                        fi
                        echo "安装 cpulimit..."
                        $PKG_MANAGER_TEMP install -y cpulimit
                    else
                        echo "无法自动识别的 Linux 发行版 ($OS_ID_TEMP / $OS_LIKE_TEMP)。请手动安装 cpulimit。"
                        exit 1
                    fi
                    ;;
            esac
            # 再次检查 cpulimit 是否安装成功
            if ! command -v cpulimit >/dev/null 2>&1; then
                 echo "cpulimit 安装失败，请检查之前的错误信息或手动安装。"
                 exit 1
            fi
        else
            echo "无法找到 /etc/os-release 文件。请手动安装 cpulimit。"
            exit 1
        fi
         echo "cpulimit 安装完成。"
    fi
    echo -e "\033[33m[INFO]\033[0m 本脚本将以最大CPU 80%限制方式运行..."
    export CPULIMIT_STARTED=1
    # 使用 exec 来替换当前进程，避免留下僵尸父进程
    exec cpulimit -l 80 -- bash "$0" "$@"
    # 如果 exec 失败，则退出
    exit 1
fi

# 彩色定义
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

# 日志记录函数
log() {
    # 将时间和消息追加写入日志文件，并在控制台也显示出来
    echo -e "$(date '+%F %T') - $1" | tee -a "$LOG_FILE"
}

# 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID        # 如 ubuntu, centos
        OS_LIKE=$ID_LIKE # 如 debian, rhel fedora
    else
        echo -e "${RED}无法识别的系统，不支持自动安全配置${RESET}"
        log "错误：无法识别的系统，找不到 /etc/os-release"
        exit 1
    fi
    log "检测到操作系统: ID=$OS_ID, ID_LIKE=$OS_LIKE"
}

# 统一的包安装函数 (已修正并优化验证逻辑)
inst() {
    for pkg in "$@"; do
        # 检查包是否已经安装 (通过检查命令是否存在)
        cmd_to_check_pre="$pkg"
        if [ "$pkg" == "fail2ban" ]; then
            cmd_to_check_pre="fail2ban-client"
        fi
        if command -v "$cmd_to_check_pre" &>/dev/null; then
            echo -e "${GREEN}$pkg (命令: $cmd_to_check_pre) 已安装${RESET}"
            log "$pkg (命令: $cmd_to_check_pre) 已安装"
            continue
        fi

        echo -e "${YELLOW}正在安装 $pkg ...${RESET}"
        log "正在安装 $pkg ..."
        PKG_MANAGER=""
        if command -v dnf &>/dev/null; then PKG_MANAGER="dnf";
        elif command -v yum &>/dev/null; then PKG_MANAGER="yum";
        elif command -v apt-get &>/dev/null; then PKG_MANAGER="apt-get";
        else echo -e "${RED}错误：无法找到 apt, yum 或 dnf 包管理器！${RESET}"; log "错误：无法找到 apt, yum 或 dnf 包管理器！"; exit 1; fi
        log "使用包管理器: $PKG_MANAGER"; echo -e "${BLUE}使用包管理器: $PKG_MANAGER${RESET}"
        INSTALL_LOG=""

        case "$OS_ID" in
            ubuntu|debian)
                INSTALL_LOG="/tmp/apt-install-$pkg.log"
                echo -e "${BLUE}>>> $PKG_MANAGER update${RESET}"; $PKG_MANAGER update -y > /tmp/apt-update.log 2>&1
                echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"; $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1 ;;
            centos|almalinux|rocky|rhel)
                INSTALL_LOG="/tmp/$PKG_MANAGER-install-$pkg.log"
                if ! rpm -q epel-release &>/dev/null; then
                    echo -e "${BLUE}>>> $PKG_MANAGER install -y epel-release${RESET}"; $PKG_MANAGER install -y epel-release > /tmp/$PKG_MANAGER-epel.log 2>&1
                    if ! rpm -q epel-release &>/dev/null; then echo -e "${RED}!!! EPEL Repository 安装失败...${RESET}"; log "错误：EPEL Repository 安装失败"; exit 1;
                    else echo -e "${GREEN}EPEL Repository 已成功安装${RESET}"; log "EPEL Repository 已成功安装"; echo -e "${BLUE}>>> $PKG_MANAGER makecache${RESET}"; $PKG_MANAGER makecache > /tmp/$PKG_MANAGER-makecache.log 2>&1; fi
                else echo -e "${GREEN}EPEL Repository 已存在${RESET}"; log "EPEL Repository 已存在"; fi
                echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"; $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1 ;;
            *)
                if [[ "$OS_LIKE" =~ "debian" ]]; then
                    PKG_MANAGER="apt-get"; INSTALL_LOG="/tmp/apt-install-$pkg.log"; log "检测到类 Debian 系统，使用 $PKG_MANAGER"
                    echo -e "${BLUE}>>> $PKG_MANAGER update${RESET}"; $PKG_MANAGER update -y > /tmp/apt-update.log 2>&1
                    echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"; $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1
                elif [[ "$OS_LIKE" =~ "rhel" ]]; then
                    INSTALL_LOG="/tmp/$PKG_MANAGER-install-$pkg.log"; log "检测到类 RHEL 系统，使用 $PKG_MANAGER"
                    if ! rpm -q epel-release &>/dev/null; then
                        echo -e "${BLUE}>>> $PKG_MANAGER install -y epel-release${RESET}"; $PKG_MANAGER install -y epel-release > /tmp/$PKG_MANAGER-epel.log 2>&1
                        if ! rpm -q epel-release &>/dev/null; then echo -e "${RED}!!! EPEL Repository 安装失败...${RESET}"; log "错误：EPEL Repository 安装失败"; exit 1;
                        else echo -e "${GREEN}EPEL Repository 已成功安装${RESET}"; log "EPEL Repository 已成功安装"; echo -e "${BLUE}>>> $PKG_MANAGER makecache${RESET}"; $PKG_MANAGER makecache > /tmp/$PKG_MANAGER-makecache.log 2>&1; fi
                    else echo -e "${GREEN}EPEL Repository 已存在${RESET}"; log "EPEL Repository 已存在"; fi
                    echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"; $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1
                else echo -e "${RED}警告：无法为 $OS_ID ($OS_LIKE) 自动安装 $pkg...${RESET}"; log "警告：无法为 $OS_ID ($OS_LIKE) 自动安装 $pkg"; continue; fi ;;
        esac

        hash -r; log "执行 hash -r 清除命令路径缓存"
        cmd_to_check="$pkg"
        if [ "$pkg" == "fail2ban" ]; then cmd_to_check="fail2ban-client"; log "为 fail2ban 包特别检查命令: $cmd_to_check"; fi
        log "用于验证 $pkg 安装的命令是: $cmd_to_check"

        if ! command -v "$cmd_to_check" &>/dev/null; then
            pm_success_likely=false
            if [ -f "$INSTALL_LOG" ] && [ -s "$INSTALL_LOG" ] && tail "$INSTALL_LOG" | grep -Eiq "complete|installed|已安装"; then pm_success_likely=true; log "包管理器日志 $INSTALL_LOG 存在且包含成功指示符。";
            elif [ -f "$INSTALL_LOG" ]; then log "包管理器日志 $INSTALL_LOG 存在，但未检测到明确成功指示符。"; else log "未找到包管理器日志 $INSTALL_LOG。"; fi

            if $pm_success_likely; then
                echo -e "${RED}!!! 警告：包管理器日志 $INSTALL_LOG 显示 $pkg 可能已安装，但命令 '$cmd_to_check' 未在 PATH 中找到或无法执行。${RESET}"
                echo -e "${RED}!!! 请手动确认。脚本将继续，但 $pkg 可能无法正常工作。${RESET}"; log "警告：包管理器日志显示 $pkg 可能已安装，但命令 '$cmd_to_check' 未找到。脚本继续。"
            else
                echo -e "${RED}!!! $pkg 安装失败。无法找到命令 '$cmd_to_check'。请检查安装日志: $INSTALL_LOG ${RESET}"; log "错误: $pkg 安装失败。无法找到命令 '$cmd_to_check'。日志: $INSTALL_LOG"; exit 1
            fi
        else echo -e "${GREEN}$pkg (验证命令: $cmd_to_check) 安装验证成功！${RESET}"; log "$pkg (验证命令: $cmd_to_check) 安装验证成功！"; fi
    done
}

# 配置防火墙，开放所有端口
setup_firewall_openall() {
    echo -e "${YELLOW}配置防火墙为全部端口开放...${RESET}"; log "配置防火墙(全部端口开放)"
    FW_CONFIGURED=false
    case "$OS_ID" in
        ubuntu|debian)
            inst ufw; echo -e "${BLUE}重置并开放所有端口(UFW)...${RESET}"; ufw --force reset; ufw default allow incoming; ufw default allow outgoing; ufw --force enable; log "UFW 已重置并设置为允许所有连接"; FW_CONFIGURED=true ;;
        centos|almalinux|rocky|rhel)
            inst firewalld; systemctl enable firewalld --now; echo -e "${BLUE}firewalld切换到trusted区域（全部端口开放）...${RESET}"; firewall-cmd --set-default-zone=trusted --permanent; firewall-cmd --reload; log "firewalld 默认区域已设置为 trusted"; FW_CONFIGURED=true ;;
        *)
            if [[ "$OS_LIKE" =~ "debian" ]]; then inst ufw; ufw --force reset; ufw default allow incoming; ufw default allow outgoing; ufw --force enable; log "UFW (类Debian) 已重置并设置为允许所有连接"; FW_CONFIGURED=true
            elif [[ "$OS_LIKE" =~ "rhel" ]]; then inst firewalld; systemctl enable firewalld --now; firewall-cmd --set-default-zone=trusted --permanent; firewall-cmd --reload; log "firewalld (类RHEL) 默认区域已设置为 trusted"; FW_CONFIGURED=true
            else echo -e "${RED}警告：无法为此系统自动配置防火墙。${RESET}"; log "警告：无法为此系统自动配置防火墙 ($OS_ID / $OS_LIKE)"; fi ;;
    esac
    if $FW_CONFIGURED; then echo -e "${GREEN}防火墙已配置为全部开放！${RESET}"; else echo -e "${YELLOW}防火墙未自动配置。${RESET}"; fi
    # 提示用户开启防火墙日志记录以配合 fail2ban portscan
    sudo yum remove firewalld
    echo -e "${YELLOW}提示：为了让 Fail2ban 的端口扫描防护生效，您需要确保防火墙记录了被拒绝的连接。${RESET}"
    echo -e "${YELLOW}例如，对于 firewalld, 可以尝试运行: sudo firewall-cmd --set-log-denied=all ${RESET}"
    echo -e "${YELLOW}(这会产生大量日志，请注意监控!) ${RESET}"
    log "提示用户需手动配置防火墙日志以启用portscan检测"
}

# 安装并配置 fail2ban (自动开启 SSH/系统登录/Apache/端口扫描 防护)
install_full_fail2ban() {
    echo -e "${YELLOW}安装并配置 fail2ban (自动开启SSH/系统登录/Apache/端口扫描防护)...${RESET}"
    log "安装并配置 fail2ban (自动开启SSH/系统登录/Apache/端口扫描防护)"
    inst fail2ban

    FJB_CONF="/etc/fail2ban/jail.local"
    echo -e "${BLUE}生成 fail2ban 配置文件: $FJB_CONF (已启用部分防护) ${RESET}"
    log "生成 fail2ban 配置文件: $FJB_CONF (已启用部分防护)"
    cat > "$FJB_CONF" <<EOF
# /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime  = 3600
findtime = 600
maxretry = 5
backend = systemd
destemail = root@localhost
sender = fail2ban@$(hostname -f || echo 'localhost')
mta = sendmail
action = %(action_mwl)s

[sshd]
enabled = true # SSH防护 (默认开启)
port    = ssh
logpath = %(sshd_log)s

[systemd-logind]
enabled = true # 系统登录防护 (systemd, 默认开启)

# --- FTP 服务 ---
[vsftpd]
enabled = false # FTP防护 (vsftpd, 默认关闭)
port    = ftp,ftp-data,ftps,ftps-data
logpath = /var/log/vsftpd.log
[proftpd]
enabled = false # FTP防护 (proftpd, 默认关闭)
port    = ftp,ftp-data,ftps,ftps-data
logpath = /var/log/proftpd/proftpd.log

# --- 邮件服务 ---
[postfix]
enabled = false # 邮件防护 (Postfix, 默认关闭)
port    = smtp,465,submission
logpath = /var/log/mail.log
[dovecot]
enabled = false # 邮件防护 (Dovecot, 默认关闭)
port    = pop3,pop3s,imap,imaps
logpath = /var/log/mail.log

# --- Web 服务器 ---
[nginx-http-auth]
enabled = false # Web防护 (Nginx Basic Auth, 默认关闭)
port    = http,https
logpath = /var/log/nginx/error.log
[apache-auth]
enabled = false # Web防护 (Apache Basic Auth, 默认关闭)
port    = http,https
logpath = /var/log/apache*/error.log
[apache-badbots]
# !! 注意: 假设使用 Apache 且日志在 /var/log/apache*/access.log
enabled  = true # Web防护 (Apache 恶意爬虫过滤, 默认开启)
port     = http,https
logpath  = /var/log/apache*/access.log
maxretry = 2
[apache-noscript]
enabled = false # Web防护 (Apache 脚本扫描过滤, 默认关闭)
port    = http,https
logpath = /var/log/apache*/error.log
maxretry = 2
[apache-overflows]
enabled = false # Web防护 (Apache 溢出尝试过滤, 默认关闭)
port    = http,https
logpath = /var/log/apache*/error.log
maxretry = 2

# --- 全端口扫描防护 ---
[portscan]
# !! 重要: 依赖防火墙记录被拒绝/丢弃的连接到 systemd journal。
# !! 可能需要手动配置防火墙日志记录 (如 firewalld --set-log-denied=all)。
# !! 如果无效，需根据实际日志调整 filter.d/portscan.conf 文件。
enabled   = true # 端口扫描防护 (默认开启, 依赖防火墙日志)
filter    = portscan # 使用下面的 portscan.conf 过滤器
# logpath 省略，使用 backend = systemd 和 filter 中的 journalmatch
maxretry  = 10     # 10次可疑尝试就触发 (可适当调高减少误报, 如 5-10)
findtime  = 600    # 在10分钟内
bantime   = 86400  # 封禁 1 天 (可适当缩短减少误伤, 如 3600)

# --- 其他 ---
# [pam-generic]
# enabled = false
EOF
    log "Fail2ban 配置文件 $FJB_CONF 已生成 (SSH, systemd-logind, apache-badbots, portscan 默认启用)。"

    # Nginx HTTP Auth 过滤器 (按需创建)
    if [ ! -f /etc/fail2ban/filter.d/nginx-http-auth.conf ]; then
        echo -e "${BLUE}创建 Nginx HTTP Auth 过滤器...${RESET}"; log "创建 Nginx HTTP Auth 过滤器..."
        cat > /etc/fail2ban/filter.d/nginx-http-auth.conf <<'EOL'
[Definition]
failregex = ^ \[error\] \d+#\d+: \*\d+ user "\S+":? password mismatch, client: <HOST>,.*$
            ^ \[error\] \d+#\d+: \*\d+ no user/password was provided.*client: <HOST>,.*$
            ^ \[error\] \d+#\d+: \*\d+ user "\S+" was not found.*client: <HOST>,.*$
ignoreregex =
EOL
    fi

    # 创建 portscan 过滤器 (如果不存在) - 适配 systemd journal
    PORTSCAN_FILTER="/etc/fail2ban/filter.d/portscan.conf"
    if [ ! -f "$PORTSCAN_FILTER" ]; then
        echo -e "${BLUE}创建 portscan 过滤器 ($PORTSCAN_FILTER)...${RESET}"
        log "创建 portscan 过滤器 ($PORTSCAN_FILTER) - 适配 systemd journal"
        cat > "$PORTSCAN_FILTER" <<'EOL'
# /etc/fail2ban/filter.d/portscan.conf
# Filter potentially matching port scan attempts logged to systemd-journal by firewalld/iptables.
# WARNING: Requires appropriate firewall logging (e.g., firewalld --set-log-denied=all) to be effective.
# Inspect your logs via 'journalctl | grep -E "SRC=.* DPT=" ' and adjust failregex if needed.

[INCLUDES]
before = common.conf

[Definition]
# Regex attempts to match common reject/drop messages (case-insensitive) from firewalld/kernel logs.
# Looks for "reject" or "drop", "SRC=<HOST>", and "DPT=<port>".
# The leading %%s matches optional journalctl prefixes.
failregex = %%s(?:firewalld|kernel):\s+.*(?:REJECT|DROP)\s+.*SRC=<HOST>\s+.*DPT=\d+.*%%s
            # Consider adding variations if your logs look different

ignoreregex =

[Init]
# Tells fail2ban to read from the systemd journal.
# Matches messages from firewalld.service OR kernel messages. Adjust if needed.
journalmatch = _SYSTEMD_UNIT=firewalld.service + _COMM=firewalld
# journalmatch = _TRANSPORT=kernel # Alternative/additional match

# Notes:
# - This filter relies on the 'backend = systemd' setting in jail.conf/jail.local.
# - 'logpath' should NOT be set in jail.local for the [portscan] jail when using journalmatch.
EOL
    else
        echo -e "${GREEN}Portscan 过滤器 $PORTSCAN_FILTER 已存在，未覆盖。${RESET}"
        log "Portscan 过滤器 $PORTSCAN_FILTER 已存在。"
    fi

    echo -e "${BLUE}启用并重启 fail2ban 服务...${RESET}"
    systemctl enable fail2ban --now; sleep 1; systemctl restart fail2ban
    log "Fail2ban 服务已尝试启用并重启。"

    echo -e "${BLUE}等待 fail2ban 服务启动...${RESET}"; sleep 3
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}fail2ban 已成功配置并启动。${RESET}"
        echo -e "${BLUE}已默认启用 SSH、系统登录、Apache恶意爬虫、端口扫描 防护。${RESET}"
        echo -e "${YELLOW}警告：端口扫描防护依赖于防火墙正确记录被拒绝的连接到系统日志(journald)。${RESET}"
        echo -e "${YELLOW}      您可能需要手动配置防火墙日志记录 (如 sudo firewall-cmd --set-log-denied=all) 才能使其生效。${RESET}"
        echo -e "${BLUE}如需调整或禁用某项防护, 请编辑 ${FJB_CONF} 和相应的过滤器, 然后运行 'systemctl restart fail2ban'。${RESET}"
        log "Fail2ban 配置完成。SSH, systemd-logind, apache-badbots, portscan 默认启用 (portscan 依赖防火墙日志)。"
    else
        echo -e "${RED}Fail2ban 服务启动失败！请检查日志：'journalctl -u fail2ban' 或 /var/log/fail2ban.log ${RESET}"
        log "错误：Fail2ban 服务启动失败！"
    fi
}

# 安装 cpulimit
install_cpulimit() {
    echo -e "${YELLOW}检查并安装 cpulimit...${RESET}"; inst cpulimit
}

# 创建 CPU 限制监控脚本
create_cpu_limit_script() {
    echo -e "${YELLOW}创建CPU限制监控脚本...${RESET}"; log "创建CPU限制监控脚本..."
    cat > "$CPU_LIMIT_SCRIPT" <<'EOF'
#!/bin/bash
LOG_FILE="/var/log/cpu_limit.log"; CPU_THRESHOLD=80; LIMIT_RATE=80; XRAY_LIMIT=80; CHECK_INTERVAL=5
log() { echo "$(date '+%F %T') - $1" >> "$LOG_FILE"; }
log "===== 启动 CPU 限制监控守护进程 (v2) ====="
while true; do
    ps -eo pid,%cpu,args --no-headers --sort=-%cpu | \
    awk -v ct="$CPU_THRESHOLD" -v lr="$LIMIT_RATE" -v xl="$XRAY_LIMIT" -v log_file="$LOG_FILE" '
    function log_msg(level, message) { printf "%s - [%s] %s\n", strftime("%F %T"), level, message >> log_file; fflush(log_file); }
    {
        pid = $1; cpu = int($2); cmd = $3; full_cmd = ""; for(i=3; i<=NF; i++) full_cmd = full_cmd $i " ";
        if (cmd ~ /^\[.+\]$/ || cmd == "awk" || cmd == "cpulimit" || full_cmd ~ /cpu_limit\.sh/) next;
        if (cpu >= ct) {
            limit_to = lr; process_type = "常规高CPU进程";
            if (full_cmd ~ /xray|x-ui/) { limit_to = xl; process_type = "xray/x-ui进程"; }
            check_cmd = "pgrep -f \"cpulimit .* -p " pid "\" > /dev/null";
            if (system(check_cmd) != 0) {
                log_msg("INFO", sprintf("检测到%s: PID=%d (%s), CPU=%d%% >= %d%%. 应用限制 %d%%", process_type, pid, cmd, cpu, ct, limit_to));
                limit_cmd = sprintf("cpulimit -p %d -l %d -b", pid, limit_to);
                ret = system(limit_cmd);
                if (ret != 0) log_msg("WARN", sprintf("为 PID=%d (%s) 启动 cpulimit 失败，返回码: %d", pid, cmd, ret));
            }
        }
    }'
    sleep "$CHECK_INTERVAL"
done
EOF
    chmod +x "$CPU_LIMIT_SCRIPT"; echo -e "${GREEN}CPU限制监控脚本已创建：$CPU_LIMIT_SCRIPT ${RESET}"; log "CPU限制监控脚本已创建：$CPU_LIMIT_SCRIPT"
}

# 创建 CPU 限制的 systemd 服务单元
create_cpu_limit_service() {
    echo -e "${YELLOW}创建CPU限制systemd服务...${RESET}"; log "创建CPU限制systemd服务..."
    cat > "$CPU_LIMIT_SERVICE" <<EOF
[Unit]
Description=CPU Usage Limiter Service
After=network.target
[Service]
ExecStart=$CPU_LIMIT_SCRIPT
Restart=always; RestartSec=5; User=root; StandardOutput=null; StandardError=null
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable cpu_limit.service; systemctl restart cpu_limit.service
    log "CPU限制systemd服务配置文件已创建：$CPU_LIMIT_SERVICE"
    echo -e "${BLUE}等待 CPU 限制服务启动...${RESET}"; sleep 3
    if systemctl is-active --quiet cpu_limit.service; then echo -e "${GREEN}CPU限制服务已成功启用并启动！${RESET}"; log "CPU限制服务已成功启用并启动";
    else echo -e "${RED}CPU限制服务启动失败！请检查日志：'journalctl -u cpu_limit.service' 或 /var/log/cpu_limit.log ${RESET}"; log "错误：CPU限制服务启动失败！"; fi
}

# 卸载 CPU 限制功能
remove_cpu_limit() {
    echo -e "${YELLOW}正在卸载CPU限制服务和脚本...${RESET}"; log "开始卸载CPU限制服务和脚本..."
    systemctl stop cpu_limit.service 2>/dev/null; log "尝试停止 cpu_limit.service"
    systemctl disable cpu_limit.service 2>/dev/null; log "尝试禁用 cpu_limit.service"
    echo -e "${BLUE}删除 $CPU_LIMIT_SERVICE ${RESET}"; rm -f "$CPU_LIMIT_SERVICE"
    echo -e "${BLUE}删除 $CPU_LIMIT_SCRIPT ${RESET}"; rm -f "$CPU_LIMIT_SCRIPT"
    systemctl daemon-reload
    echo -e "${BLUE}停止所有残留的 cpulimit 进程...${RESET}"; pkill -f "cpulimit .* -p"; log "尝试停止所有由监控脚本启动的 cpulimit 进程"
    echo -e "${GREEN}CPU限制服务与脚本已卸载完成。${RESET}"; log "CPU限制服务与脚本已卸载完成。"
}

# 主菜单函数
main_menu() {
    detect_os
    while true; do
        clear
        echo -e "${BOLD}${BLUE}=============================="; echo -e "  VPS安全环境 & CPU限制管理器"; echo -e "==============================${RESET}"
        echo -e "${YELLOW}1. 安装并配置 fail2ban（自动开启SSH/系统登录/Apache/端口扫描基础防护）${RESET}"
        echo -e "${YELLOW}2. 配置防火墙（设置为全部端口开放 - ${RED}不建议用于生产环境${RESET}${YELLOW}）${RESET}"
        echo -e "${YELLOW}3. 部署并启用CPU限制服务（监控并限制高CPU进程）${RESET}"
        echo -e "${YELLOW}4. 卸载CPU限制服务和脚本${RESET}"
        echo -e "${YELLOW}5. 退出脚本${RESET}"
        echo -e "${BLUE}------------------------------${RESET}"
        read -p "$(echo -e "${BOLD}请选择操作 [1-5]：${RESET}")" choice
        case "$choice" in
            1) install_full_fail2ban; echo -e "\n${GREEN}操作完成，按 Enter键 返回主菜单...${RESET}"; read -r ;;
            2) setup_firewall_openall; echo -e "\n${GREEN}操作完成，按 Enter键 返回主菜单...${RESET}"; read -r ;;
            3) install_cpulimit; create_cpu_limit_script; create_cpu_limit_service; echo -e "\n${GREEN}操作完成，按 Enter键 返回主菜单...${RESET}"; read -r ;;
            4) remove_cpu_limit; echo -e "\n${GREEN}操作完成，按 Enter键 返回主菜单...${RESET}"; read -r ;;
            5) echo -e "\n${BOLD}${BLUE}脚本已退出。操作日志记录在：$LOG_FILE${RESET}"; exit 0 ;;
            *) echo -e "\n${RED}输入错误！请输入 1 到 5 之间的数字。${RESET}"; sleep 2 ;;
        esac
    done
}

# --- 脚本主入口 ---
main_menu
