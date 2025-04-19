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

# 统一的包安装函数 (已修正)
inst() {
    for pkg in "$@"; do
        # 检查包是否已经安装 (通过检查命令是否存在)
        if command -v $pkg &>/dev/null; then
            echo -e "${GREEN}$pkg 已安装${RESET}"
            log "$pkg 已安装"
            continue # 如果已安装，跳过当前包，处理下一个
        fi

        echo -e "${YELLOW}正在安装 $pkg ...${RESET}"
        log "正在安装 $pkg ..."
        PKG_MANAGER=""
        # 检测使用 dnf 还是 yum
        if command -v dnf &>/dev/null; then
            PKG_MANAGER="dnf"
        elif command -v yum &>/dev/null; then
            PKG_MANAGER="yum"
        elif command -v apt-get &>/dev/null; then
            PKG_MANAGER="apt-get" # 增加对apt的识别
        else
             echo -e "${RED}错误：无法找到 apt, yum 或 dnf 包管理器！${RESET}"
             log "错误：无法找到 apt, yum 或 dnf 包管理器！"
             exit 1 # 关键依赖缺失，退出
        fi
        log "使用包管理器: $PKG_MANAGER"
        echo -e "${BLUE}使用包管理器: $PKG_MANAGER${RESET}"

        case "$OS_ID" in
            ubuntu|debian)
                echo -e "${BLUE}>>> $PKG_MANAGER update${RESET}"
                # 更新包列表，并将输出重定向到日志，忽略错误 (-qq 表示安静模式，减少输出)
                $PKG_MANAGER update -y > /tmp/apt-update.log 2>&1
                echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"
                # 安装包，并将输出重定向到日志
                $PKG_MANAGER install -y $pkg > "/tmp/apt-install-$pkg.log" 2>&1
                ;;
            centos|almalinux|rocky|rhel)
                # 检查并安装 EPEL (Extra Packages for Enterprise Linux)
                if ! rpm -q epel-release &>/dev/null; then
                    echo -e "${BLUE}>>> $PKG_MANAGER install -y epel-release${RESET}"
                    # 安装 EPEL release，并将输出重定向到日志
                    $PKG_MANAGER install -y epel-release > /tmp/$PKG_MANAGER-epel.log 2>&1
                    # 验证EPEL是否真的安装成功
                    if ! rpm -q epel-release &>/dev/null; then
                        echo -e "${RED}!!! EPEL Repository 安装失败，请检查网络或查看日志 /tmp/$PKG_MANAGER-epel.log ${RESET}"
                        log "错误：EPEL Repository 安装失败"
                        exit 1 # EPEL是很多包的前提，安装失败则退出
                    else
                         echo -e "${GREEN}EPEL Repository 已成功安装${RESET}"
                         log "EPEL Repository 已成功安装"
                         # EPEL刚装上，最好刷新一下缓存
                         echo -e "${BLUE}>>> $PKG_MANAGER makecache${RESET}"
                         $PKG_MANAGER makecache > /tmp/$PKG_MANAGER-makecache.log 2>&1
                    fi
                else
                    echo -e "${GREEN}EPEL Repository 已存在${RESET}"
                    log "EPEL Repository 已存在"
                fi

                # 安装目标包
                echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"
                # 安装目标包，并将输出重定向到日志
                $PKG_MANAGER install -y $pkg > "/tmp/$PKG_MANAGER-install-$pkg.log" 2>&1
                ;;
            *)
                # 如果 OS_ID 不直接匹配，尝试根据 OS_LIKE 来判断
                if [[ "$OS_LIKE" =~ "debian" ]]; then
                    # 类 Debian 系统 (如 Deepin, UOS) 使用 apt
                    PKG_MANAGER="apt-get" # 确认使用 apt-get
                    log "检测到类 Debian 系统，使用 apt-get"
                    echo -e "${BLUE}>>> $PKG_MANAGER update${RESET}"
                    $PKG_MANAGER update -y > /tmp/apt-update.log 2>&1
                    echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"
                    $PKG_MANAGER install -y $pkg > "/tmp/apt-install-$pkg.log" 2>&1
                elif [[ "$OS_LIKE" =~ "rhel" ]]; then
                    # 类 RHEL 系统 (如 Fedora, Oracle Linux) 使用 dnf/yum
                    log "检测到类 RHEL 系统，使用 $PKG_MANAGER"
                     # 同样需要检查并安装 EPEL
                    if ! rpm -q epel-release &>/dev/null; then
                        echo -e "${BLUE}>>> $PKG_MANAGER install -y epel-release${RESET}"
                        $PKG_MANAGER install -y epel-release > /tmp/$PKG_MANAGER-epel.log 2>&1
                        if ! rpm -q epel-release &>/dev/null; then
                            echo -e "${RED}!!! EPEL Repository 安装失败，请检查网络或查看日志 /tmp/$PKG_MANAGER-epel.log ${RESET}"
                            log "错误：EPEL Repository 安装失败"
                            exit 1
                        else
                            echo -e "${GREEN}EPEL Repository 已成功安装${RESET}"
                            log "EPEL Repository 已成功安装"
                            echo -e "${BLUE}>>> $PKG_MANAGER makecache${RESET}"
                            $PKG_MANAGER makecache > /tmp/$PKG_MANAGER-makecache.log 2>&1
                        fi
                    else
                        echo -e "${GREEN}EPEL Repository 已存在${RESET}"
                        log "EPEL Repository 已存在"
                    fi
                    # 安装目标包
                    echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"
                    $PKG_MANAGER install -y $pkg > "/tmp/$PKG_MANAGER-install-$pkg.log" 2>&1
                else
                    # 实在无法判断，提示用户手动安装
                    echo -e "${RED}警告：无法为 $OS_ID ($OS_LIKE) 自动安装 $pkg，请手动安装。${RESET}"
                    log "警告：无法为 $OS_ID ($OS_LIKE) 自动安装 $pkg，请手动安装。"
                    # 这里选择 continue 而不是 exit，也许其他包可以安装
                    continue
                fi
                ;;
        esac

        # 安装命令执行后，再次验证包 (命令) 是否可用
        if ! command -v $pkg &>/dev/null; then
            INSTALL_LOG=""
            # 确定刚才使用的是哪个包管理器，以找到正确的日志文件
            case "$OS_ID" in
                 ubuntu|debian) INSTALL_LOG="/tmp/apt-install-$pkg.log";;
                 centos|almalinux|rocky|rhel) INSTALL_LOG="/tmp/$PKG_MANAGER-install-$pkg.log";;
                 *)
                    if [[ "$OS_LIKE" =~ "debian" ]]; then INSTALL_LOG="/tmp/apt-install-$pkg.log"; fi
                    if [[ "$OS_LIKE" =~ "rhel" ]]; then INSTALL_LOG="/tmp/$PKG_MANAGER-install-$pkg.log"; fi
                    ;;
            esac
            # 提供具体的失败信息和日志文件路径
            echo -e "${RED}!!! $pkg 安装失败。请检查安装日志: $INSTALL_LOG ${RESET}"
            log "错误: $pkg 安装失败。日志: $INSTALL_LOG"
            exit 1 # 重要的依赖安装失败，退出脚本
        else
            echo -e "${GREEN}$pkg 安装成功！${RESET}"
            log "$pkg 安装成功！"
        fi
    done
}


# 配置防火墙，开放所有端口
setup_firewall_openall() {
    echo -e "${YELLOW}配置防火墙为全部端口开放...${RESET}"
    log "配置防火墙(全部端口开放)"
    case "$OS_ID" in
        ubuntu|debian)
            inst ufw # 确保 ufw 已安装
            echo -e "${BLUE}重置并开放所有端口(UFW)...${RESET}"
            # 强制重置 UFW 规则
            ufw --force reset
            # 设置默认策略：允许所有入站和出站连接
            ufw default allow incoming
            ufw default allow outgoing
            # 强制启用 UFW
            ufw --force enable
            log "UFW 已重置并设置为允许所有连接"
            ;;
        centos|almalinux|rocky|rhel)
            inst firewalld # 确保 firewalld 已安装
            # 启用并立即启动 firewalld 服务
            systemctl enable firewalld --now
            echo -e "${BLUE}firewalld切换到trusted区域（全部端口开放）...${RESET}"
            # 将默认区域设置为 trusted，该区域默认允许所有连接
            firewalld-cmd --set-default-zone=trusted --permanent
            # 重新加载防火墙规则使设置生效
            firewalld-cmd --reload
            log "firewalld 默认区域已设置为 trusted"
            ;;
        *)
            # 尝试根据 OS_LIKE 处理
            if [[ "$OS_LIKE" =~ "debian" ]]; then
                inst ufw
                ufw --force reset
                ufw default allow incoming
                ufw default allow outgoing
                ufw --force enable
                log "UFW (类Debian) 已重置并设置为允许所有连接"
            elif [[ "$OS_LIKE" =~ "rhel" ]]; then
                inst firewalld
                systemctl enable firewalld --now
                firewalld-cmd --set-default-zone=trusted --permanent
                firewalld-cmd --reload
                log "firewalld (类RHEL) 默认区域已设置为 trusted"
            else
                echo -e "${RED}警告：无法为此系统自动配置防火墙。${RESET}"
                log "警告：无法为此系统自动配置防火墙 ($OS_ID / $OS_LIKE)"
            fi
            ;;
    esac
    echo -e "${GREEN}防火墙已配置为全部开放！${RESET}"
}

# 安装并全面配置 fail2ban
install_full_fail2ban() {
    echo -e "${YELLOW}安装并全面配置fail2ban各类安全防御...${RESET}"
    log "安装并全面配置fail2ban"

    inst fail2ban # 使用我们修正过的 inst 函数安装 fail2ban

    # 生成全功能的 jail.local 配置文件
    # 使用 .local 文件是推荐做法，避免升级时覆盖 jail.conf
    FJB_CONF="/etc/fail2ban/jail.local"
    echo -e "${BLUE}生成 fail2ban 配置文件: $FJB_CONF ${RESET}"
    log "生成 fail2ban 配置文件: $FJB_CONF"
    cat > "$FJB_CONF" <<EOF
# /etc/fail2ban/jail.local
# Fail2ban 本地配置文件 - 在此文件中覆盖 jail.conf 的默认设置

[DEFAULT]
# 忽略的 IP 地址列表，用空格分隔。本地回环地址和私有地址通常应加入。
# ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
ignoreip = 127.0.0.1/8 ::1

# 封禁时间（秒），默认1小时
bantime  = 3600

# 查找失败尝试的时间窗口（秒），默认10分钟
findtime  = 600

# 在 findtime 时间内允许的最大失败次数
maxretry = 5

# 后端日志监控方式，'auto' 通常能工作，'systemd' 在使用 systemd 日志的系统上更优
backend = systemd

# 接收通知邮件的地址
destemail = root@localhost

# 发件人地址
sender = fail2ban@$(hostname -f || echo 'localhost')

# 使用的邮件发送程序
mta = sendmail

# 默认的封禁动作。 %(action_mwl)s 表示：封禁 + 发邮件通知（包含whois信息和日志行）
# 其他选项如 %(action_mw)s (无日志行), %(action_)s (仅封禁)
action = %(action_mwl)s

# --- 以下为各服务的具体配置段 ---
# 你需要根据服务器上实际运行的服务来启用 (enabled = true) 或禁用 (enabled = false)

[sshd]
# 保护 SSH 登录
enabled = true
port    = ssh  # 可以是端口号或服务名 (如 /etc/services 中定义)
logpath = %(sshd_log)s # 通常自动检测, 如 /var/log/auth.log 或 journald

# [sshd-ddos]
# # 防御 SSH 的 DoS 攻击 (更严格的规则)
# enabled = false # 按需启用
# port    = ssh
# logpath = %(sshd_log)s

[systemd-logind]
# 监控 systemd 的登录失败日志
enabled = true
# logpath = /var/log/auth.log # Debian/Ubuntu
# logpath = /var/log/secure # CentOS/RHEL (或使用 journalctl)

# --- FTP 服务 ---
[vsftpd]
# 保护 vsftpd 服务器
enabled = false # 如果你不用 vsftpd，保持 false
port    = ftp,ftp-data,ftps,ftps-data
logpath = /var/log/vsftpd.log

[proftpd]
# 保护 proftpd 服务器
enabled = false # 如果你不用 proftpd，保持 false
port    = ftp,ftp-data,ftps,ftps-data
logpath = /var/log/proftpd/proftpd.log

# --- 邮件服务 ---
[postfix]
# 保护 Postfix SMTP 服务器
enabled = false # 如果你不用 Postfix，保持 false
port    = smtp,465,submission # 25, 465, 587
logpath = /var/log/mail.log # 或 journalctl

[dovecot]
# 保护 Dovecot IMAP/POP3 服务器
enabled = false # 如果你不用 Dovecot，保持 false
port    = pop3,pop3s,imap,imaps
logpath = /var/log/mail.log # 或 journalctl

# --- Web 服务器 ---
# 注意：Web 服务器的日志路径可能需要根据你的配置修改

[nginx-http-auth]
# 保护 Nginx 的 basic auth 认证
enabled = false # 如果你不用 Nginx basic auth，保持 false
# filter = nginx-http-auth # 使用内置或自定义的过滤器
port    = http,https
logpath = /var/log/nginx/error.log # 检查你的 Nginx 配置

[nginx-badbots]
# # 过滤 Nginx 的恶意爬虫 (需要相应 filter)
# enabled = false
# port    = http,https
# logpath = /var/log/nginx/access.log

[apache-auth]
# 保护 Apache 的 basic auth 认证
enabled = false # 如果你不用 Apache basic auth，保持 false
port    = http,https
logpath = /var/log/apache*/error.log # 使用通配符匹配可能的日志文件

[apache-badbots]
# 过滤 Apache 的恶意爬虫 (使用内置 filter)
enabled  = false # 按需启用
port     = http,https
logpath  = /var/log/apache*/access.log
maxretry = 2 # 对爬虫可以更严格

[apache-noscript]
# 阻止 Apache 尝试访问脚本但服务器上不存在的请求 (通常是扫描)
enabled = false # 按需启用
port    = http,https
logpath = /var/log/apache*/error.log
maxretry = 2

[apache-overflows]
# 阻止 Apache 的长 URL 或溢出尝试
enabled = false # 按需启用
port    = http,https
logpath = /var/log/apache*/error.log
maxretry = 2

# --- 其他 ---
# [mysqld-auth]
# # 保护 MySQL/MariaDB 登录 (需要配置log-warnings=2)
# enabled = false
# port    = 3306
# logpath = /var/log/mysql/error.log # 或 /var/log/mariadb/mariadb.log

# [pam-generic]
# # 通用的 PAM 登录失败监控 (如 su, login)
# enabled = false # 可能与 sshd 重叠，按需启用
# logpath = /var/log/auth.log # Debian/Ubuntu
# logpath = /var/log/secure # CentOS/RHEL

# [portscan]
# # 检测端口扫描 (可能误报，谨慎使用)
# # 需要额外的 iptables 规则或 firewalld 配置来记录日志
# enabled = false
# filter   = portscan # filter 需要能识别扫描日志
# logpath  = /var/log/syslog # 或其他记录防火墙日志的地方
# maxretry = 1
# bantime  = 86400 # 扫描行为可以封禁更长时间

EOF
    log "Fail2ban 配置文件 $FJB_CONF 已生成。"

    # fail2ban 可能自带一些常用过滤器，但我们确保 nginx-http-auth 存在
    # （注意：如果你没用Nginx Basic Auth，这一步不是必须的）
    if [ ! -f /etc/fail2ban/filter.d/nginx-http-auth.conf ]; then
        echo -e "${BLUE}创建 Nginx HTTP Auth 过滤器...${RESET}"
        log "创建 Nginx HTTP Auth 过滤器..."
        cat > /etc/fail2ban/filter.d/nginx-http-auth.conf <<'EOL'
# Fail2Ban filter for nginx basic auth failures
[Definition]
failregex = ^ \[error\] \d+#\d+: \*\d+ user "\S+":? password mismatch, client: <HOST>, server: \S+, request: "\S+ \S+ HTTP/\d+\.\d+", host: "\S+"$
            ^ \[error\] \d+#\d+: \*\d+ no user/password was provided for basic authentication, client: <HOST>, server: \S+, request: "\S+ \S+ HTTP/\d+\.\d+", host: "\S+"$
            ^ \[error\] \d+#\d+: \*\d+ user "\S+" was not found in ".+", client: <HOST>, server: \S+, request: "\S+ \S+ HTTP/\d+\.\d+", host: "\S+"$

ignoreregex =
EOL
    fi

    # 确保 fail2ban 服务开机自启并立即启动/重启
    echo -e "${BLUE}启用并重启 fail2ban 服务...${RESET}"
    systemctl enable fail2ban --now
    systemctl restart fail2ban
    log "Fail2ban 服务已启用并重启。"

    # 检查服务状态
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}fail2ban 已成功配置并启动。${RESET}"
        echo -e "${BLUE}已启用 SSH 防护。其他服务（如Web、FTP、Mail）默认未启用。${RESET}"
        echo -e "${BLUE}请根据你的实际需求，编辑 ${FJB_CONF} 文件，将需要保护的服务对应的 'enabled' 设置为 'true'，然后运行 'systemctl restart fail2ban'。${RESET}"
        log "Fail2ban 配置完成。SSH 默认启用，其他服务需手动在 $FJB_CONF 中启用。"
    else
        echo -e "${RED}Fail2ban 服务启动失败！请检查日志：'journalctl -u fail2ban' 或 /var/log/fail2ban.log ${RESET}"
        log "错误：Fail2ban 服务启动失败！"
    fi
}

# 安装 cpulimit (如果需要被下面的函数调用)
install_cpulimit() {
    echo -e "${YELLOW}检查并安装 cpulimit...${RESET}"
    inst cpulimit # 使用我们的通用安装函数
}

# 创建 CPU 限制监控脚本
create_cpu_limit_script() {
    echo -e "${YELLOW}创建CPU限制监控脚本...${RESET}"
    log "创建CPU限制监控脚本..."
    # 创建脚本文件，写入内容
    cat > "$CPU_LIMIT_SCRIPT" <<'EOF'
#!/bin/bash

# 日志文件路径
LOG_FILE="/var/log/cpu_limit.log"
# CPU 使用率阈值，超过这个值的进程会被限制
CPU_THRESHOLD=80
# 限制到的 CPU 使用率百分比
LIMIT_RATE=80
# 针对 xray/x-ui 进程的特定限制率 (如果你用这些)
XRAY_LIMIT=80
# 检查间隔时间（秒）
CHECK_INTERVAL=5

# 简易日志函数
log() {
    echo "$(date '+%F %T') - $1" >> "$LOG_FILE"
}

log "===== 启动 CPU 限制监控守护进程 ====="

# 无限循环，持续监控
while true; do
    # --- 针对特定进程 (如 xray/x-ui) 的特殊限制 ---
    # 找到所有 xray 或 x-ui 相关的进程 PID
    # 使用 pgrep 的 -f 选项来匹配完整命令行
    for xpid in $(pgrep -f "xray|x-ui" || echo ""); do
        # 检查是否已经有一个 cpulimit 进程在限制这个 PID
        # -f 再次用于匹配包含 "-p $xpid" 的 cpulimit 命令行
        if ! pgrep -f "cpulimit.*-p $xpid" > /dev/null; then
            # 如果没有被限制，则启动 cpulimit
            log "检测到 xray/x-ui 进程 [PID=$xpid]，应用限制 ${XRAY_LIMIT}%"
            # -p 指定 PID, -l 指定百分比, -b 让 cpulimit 在后台运行
            cpulimit -p "$xpid" -l "$XRAY_LIMIT" -b
            # 检查 cpulimit 是否成功启动 (可选，但有助于调试)
            if [ $? -ne 0 ]; then
                 log "警告：为 PID=$xpid 启动 cpulimit 失败"
            fi
        fi
    done

    # --- 针对所有其他高 CPU 进程的通用限制 ---
    # 使用 ps 命令获取所有进程的 PID, CPU使用率(%CPU), 命令名(comm)
    # --no-headers 不显示标题行
    # --sort=-%cpu 按 CPU 使用率降序排序
    # awk: 如果第二列 (%CPU) 大于阈值 (th)，则打印 "PID,命令名"
    high_cpu_pids=$(ps -eo pid,%cpu,comm --no-headers --sort=-%cpu | awk -v th=$CPU_THRESHOLD '$2 >= th {printf "%s,%s\n", $1, $3}')

    # 遍历找到的高 CPU 进程列表
    for entry in $high_cpu_pids; do
        # 从 "PID,命令名" 中提取 PID 和 命令名
        pid="${entry%%,*}"
        name="${entry##*,}"

        # 跳过 xray/x-ui 进程，因为上面已经单独处理了
        # 也跳过 cpulimit 自身和脚本自身，防止自我限制
        if [[ "$name" =~ ^(xray|x-ui|cpulimit|cpu_limit\.sh)$ ]]; then
            continue
        fi

        # 再次检查该 PID 是否已被 cpulimit 限制
        if ! pgrep -f "cpulimit.*-p $pid" > /dev/null; then
            # 检查进程是否仍然存在 (避免在进程消失的瞬间尝试限制)
            if [ -d "/proc/$pid" ]; then
                # 获取该进程当前的 CPU 使用率 (整数部分)
                current_cpu=$(ps -p "$pid" -o %cpu --no-headers | awk '{print int($1)}')
                log "检测到高 CPU 进程: PID=$pid ($name), CPU=${current_cpu}%, 超过阈值 ${CPU_THRESHOLD}%. 应用限制 ${LIMIT_RATE}%"
                # 启动 cpulimit 进行限制
                cpulimit -p "$pid" -l "$LIMIT_RATE" -b
                 if [ $? -ne 0 ]; then
                    log "警告：为 PID=$pid ($name) 启动 cpulimit 失败"
                 fi
            fi
        fi
    done

    # --- 检测可能的 "隐藏" 或短时高 CPU 进程 (可选，实验性) ---
    # 这个部分尝试找到那些在 `ps` 输出中可能被隐藏（例如通过修改进程名）
    # 或者运行时间极短但 CPU 占用很高，难以被上面常规方法捕捉的进程
    # 注意：这可能产生误报或开销较大，可以按需注释掉
    # ps_pids=$(ps -e -o pid=) # 获取所有当前 ps 能看到的 PID
    # proc_pids=$(ls /proc | grep -E '^[0-9]+$') # 获取 /proc 下所有数字目录 (代表进程)
    # for proc_pid in $proc_pids; do
    #     # 检查 /proc 下的 PID 是否不在 ps 的输出中
    #     if ! echo "$ps_pids" | grep -qw "$proc_pid"; then
    #         # 尝试读取 cmdline 判断是否是内核线程等 (内核线程通常 cmdline 为空)
    #         if [ -r "/proc/$proc_pid/cmdline" ] && [ -n "$(cat /proc/$proc_pid/cmdline)" ]; then
    #             # 尝试获取这个 "隐藏" 进程的 CPU
    #             cpu=$(ps -p $proc_pid -o %cpu= 2>/dev/null | awk '{print int($1)}')
    #             # 如果能获取到 CPU 且大于阈值
    #             if [ ! -z "$cpu" ] && [ "$cpu" -gt "$CPU_THRESHOLD" ]; then
    #                 # 并且没有被 cpulimit 限制
    #                 if ! pgrep -f "cpulimit.*-p $proc_pid" > /dev/null; then
    #                     log "检测到可能的隐藏/短时高CPU进程 PID=$proc_pid (CPU=$cpu%), 尝试限制到 ${LIMIT_RATE}%"
    #                     cpulimit -p "$proc_pid" -l $LIMIT_RATE -b
    #                     if [ $? -ne 0 ]; then
    #                         log "警告：为隐藏进程 PID=$proc_pid 启动 cpulimit 失败"
    #                     fi
    #                 fi
    #             fi
    #         fi
    #     fi
    # done

    # 等待指定间隔时间后再次检查
    sleep $CHECK_INTERVAL
done
EOF

    # 赋予脚本执行权限
    chmod +x "$CPU_LIMIT_SCRIPT"
    echo -e "${GREEN}CPU限制监控脚本已创建：$CPU_LIMIT_SCRIPT ${RESET}"
    log "CPU限制监控脚本已创建：$CPU_LIMIT_SCRIPT"
}

# 创建 CPU 限制的 systemd 服务单元
create_cpu_limit_service() {
    echo -e "${YELLOW}创建CPU限制systemd服务...${RESET}"
    log "创建CPU限制systemd服务..."
    # 创建 systemd service 文件
    cat > "$CPU_LIMIT_SERVICE" <<EOF
[Unit]
Description=CPU Usage Limiter Service (Monitors and limits high CPU processes)
# 在网络服务之后启动
After=network.target

[Service]
# 指定要执行的脚本
ExecStart=$CPU_LIMIT_SCRIPT
# 设置服务在失败时总是自动重启
Restart=always
# 重启间隔时间（秒）
RestartSec=5
# 以 root 用户运行
User=root
# 将标准输出和标准错误都追加到日志文件
StandardOutput=append:/var/log/cpu_limit.log
StandardError=append:/var/log/cpu_limit.log

[Install]
# 定义服务应该在哪个 target 下启用 (multi-user.target 是标准的文本模式运行级别)
WantedBy=multi-user.target
EOF

    # 让 systemd 重新加载配置文件
    systemctl daemon-reload
    # 设置服务开机自启
    systemctl enable cpu_limit.service
    # 立即启动（或重启）服务
    systemctl restart cpu_limit.service
    log "CPU限制systemd服务配置文件已创建：$CPU_LIMIT_SERVICE"

    # 检查服务状态
    if systemctl is-active --quiet cpu_limit.service; then
        echo -e "${GREEN}CPU限制服务已成功启用并启动！${RESET}"
        log "CPU限制服务已成功启用并启动"
    else
        echo -e "${RED}CPU限制服务启动失败！请检查日志：'journalctl -u cpu_limit.service' 或 /var/log/cpu_limit.log ${RESET}"
        log "错误：CPU限制服务启动失败！"
    fi
}

# 卸载 CPU 限制功能
remove_cpu_limit() {
    echo -e "${YELLOW}正在卸载CPU限制服务和脚本...${RESET}"
    log "开始卸载CPU限制服务和脚本..."
    # 停止服务 (忽略可能的错误，比如服务已停止)
    systemctl stop cpu_limit.service 2>/dev/null
    log "尝试停止 cpu_limit.service"
    # 禁用服务开机自启 (忽略可能的错误)
    systemctl disable cpu_limit.service 2>/dev/null
    log "尝试禁用 cpu_limit.service"
    # 删除 systemd 服务文件
    echo -e "${BLUE}删除 $CPU_LIMIT_SERVICE ${RESET}"
    rm -f "$CPU_LIMIT_SERVICE"
    # 删除监控脚本文件
    echo -e "${BLUE}删除 $CPU_LIMIT_SCRIPT ${RESET}"
    rm -f "$CPU_LIMIT_SCRIPT"
    # 重新加载 systemd 配置，让更改生效
    systemctl daemon-reload
    # 杀掉所有可能还在运行的 cpulimit 进程
    echo -e "${BLUE}停止所有残留的 cpulimit 进程...${RESET}"
    pkill -f "cpulimit.*-p" # 查找由脚本启动的 cpulimit 进程并杀掉
    log "尝试停止所有由监控脚本启动的 cpulimit 进程"
    echo -e "${GREEN}CPU限制服务与脚本已卸载完成。相关的 cpulimit 进程已被尝试停止。${RESET}"
    log "CPU限制服务与脚本已卸载完成。"
}

# 主菜单函数
main_menu() {
    detect_os # 首先检测操作系统
    while true; do
        # 清屏，显示菜单
        clear
        echo -e "${BOLD}${BLUE}=============================="
        echo -e "  VPS安全环境 & CPU限制管理器"
        echo -e "==============================${RESET}"
        echo -e "${YELLOW}1. 安装并全面配置fail2ban（SSH及可选服务防护）${RESET}"
        echo -e "${YELLOW}2. 配置防火墙（设置为全部端口开放）${RESET}"
        echo -e "${YELLOW}3. 部署并启用CPU限制服务（监控并限制高CPU进程）${RESET}"
        echo -e "${YELLOW}4. 卸载CPU限制服务和脚本${RESET}"
        echo -e "${YELLOW}5. 退出脚本${RESET}"
        echo -e "${BLUE}------------------------------${RESET}"
        # 读取用户输入
        read -p "$(echo -e "${BOLD}请选择操作 [1-5]：${RESET}")" choice
        case "$choice" in
            1)
                install_full_fail2ban
                echo -e "\n${GREEN}操作完成，按 Enter键 返回主菜单...${RESET}" ; read -r
                ;;
            2)
                setup_firewall_openall
                echo -e "\n${GREEN}操作完成，按 Enter键 返回主菜单...${RESET}" ; read -r
                ;;
            3)
                install_cpulimit # 确保 cpulimit 已安装
                create_cpu_limit_script
                create_cpu_limit_service
                echo -e "\n${GREEN}操作完成，按 Enter键 返回主菜单...${RESET}" ; read -r
                ;;
            4)
                remove_cpu_limit
                echo -e "\n${GREEN}操作完成，按 Enter键 返回主菜单...${RESET}" ; read -r
                ;;
            5)
                # 退出脚本
                echo -e "\n${BOLD}${BLUE}脚本已退出。操作日志记录在：$LOG_FILE${RESET}"
                exit 0
                ;;
            *)
                # 无效输入处理
                echo -e "\n${RED}输入错误！请输入 1 到 5 之间的数字。${RESET}"
                sleep 2 # 暂停2秒让用户看到提示
                ;;
        esac
    done
}

# --- 脚本主入口 ---
# 调用主菜单函数开始执行
main_menu
