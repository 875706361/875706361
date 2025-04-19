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
        # 针对特定包，检查其主要命令
        cmd_to_check_pre="$pkg"
        if [ "$pkg" == "fail2ban" ]; then
            cmd_to_check_pre="fail2ban-client"
        fi
        if command -v "$cmd_to_check_pre" &>/dev/null; then
            echo -e "${GREEN}$pkg (命令: $cmd_to_check_pre) 已安装${RESET}"
            log "$pkg (命令: $cmd_to_check_pre) 已安装"
            continue # 如果已安装，跳过当前包，处理下一个
        fi

        echo -e "${YELLOW}正在安装 $pkg ...${RESET}"
        log "正在安装 $pkg ..."
        PKG_MANAGER=""
        # 检测使用 dnf, yum 或 apt-get
        if command -v dnf &>/dev/null; then
            PKG_MANAGER="dnf"
        elif command -v yum &>/dev/null; then
            PKG_MANAGER="yum"
        elif command -v apt-get &>/dev/null; then
            PKG_MANAGER="apt-get"
        else
             echo -e "${RED}错误：无法找到 apt, yum 或 dnf 包管理器！${RESET}"
             log "错误：无法找到 apt, yum 或 dnf 包管理器！"
             exit 1
        fi
        log "使用包管理器: $PKG_MANAGER"
        echo -e "${BLUE}使用包管理器: $PKG_MANAGER${RESET}"

        INSTALL_LOG="" # 初始化日志文件路径变量

        case "$OS_ID" in
            ubuntu|debian)
                INSTALL_LOG="/tmp/apt-install-$pkg.log"
                echo -e "${BLUE}>>> $PKG_MANAGER update${RESET}"
                $PKG_MANAGER update -y > /tmp/apt-update.log 2>&1
                echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"
                $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1
                ;;
            centos|almalinux|rocky|rhel)
                INSTALL_LOG="/tmp/$PKG_MANAGER-install-$pkg.log"
                # 检查并安装 EPEL
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
                $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1
                ;;
            *)
                # 根据 OS_LIKE 处理
                if [[ "$OS_LIKE" =~ "debian" ]]; then
                    PKG_MANAGER="apt-get"
                    INSTALL_LOG="/tmp/apt-install-$pkg.log"
                    log "检测到类 Debian 系统，使用 $PKG_MANAGER"
                    echo -e "${BLUE}>>> $PKG_MANAGER update${RESET}"
                    $PKG_MANAGER update -y > /tmp/apt-update.log 2>&1
                    echo -e "${BLUE}>>> $PKG_MANAGER install -y $pkg${RESET}"
                    $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1
                elif [[ "$OS_LIKE" =~ "rhel" ]]; then
                    INSTALL_LOG="/tmp/$PKG_MANAGER-install-$pkg.log"
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
                    $PKG_MANAGER install -y $pkg > "$INSTALL_LOG" 2>&1
                else
                    echo -e "${RED}警告：无法为 $OS_ID ($OS_LIKE) 自动安装 $pkg，请手动安装。${RESET}"
                    log "警告：无法为 $OS_ID ($OS_LIKE) 自动安装 $pkg，请手动安装。"
                    continue
                fi
                ;;
        esac

        # 清除命令路径哈希缓存，强制shell重新查找命令
        hash -r
        log "执行 hash -r 清除命令路径缓存"

        # 确定用于验证的命令
        cmd_to_check="$pkg"
        if [ "$pkg" == "fail2ban" ]; then
            cmd_to_check="fail2ban-client"
            log "为 fail2ban 包特别检查命令: $cmd_to_check"
        # 可以为其他包添加类似的 elif 判断
        # elif [ "$pkg" == "some-other-package" ]; then
        #    cmd_to_check="actual-command-name"
        fi
        log "用于验证 $pkg 安装的命令是: $cmd_to_check"

        # 最终验证安装是否成功 (检查命令是否存在)
        if ! command -v "$cmd_to_check" &>/dev/null; then
            pm_success_likely=false
            # 尝试判断包管理器是否报告成功 (简单判断：日志文件存在且不为空)
            # 注意：更精确的判断需要解析具体包管理器的成功标识，如 "Complete!"
            if [ -f "$INSTALL_LOG" ] && [ -s "$INSTALL_LOG" ] && tail "$INSTALL_LOG" | grep -qi "complete\|installed"; then
                pm_success_likely=true
                log "包管理器日志 $INSTALL_LOG 存在且包含成功指示符。"
            elif [ -f "$INSTALL_LOG" ]; then
                 log "包管理器日志 $INSTALL_LOG 存在，但未检测到明确成功指示符。"
            else
                 log "未找到包管理器日志 $INSTALL_LOG。"
            fi

            # 如果包管理器日志显示可能成功了，但命令找不到
            if $pm_success_likely; then
                echo -e "${RED}!!! 警告：包管理器日志 $INSTALL_LOG 显示 $pkg 可能已安装，但命令 '$cmd_to_check' 未在 PATH 中找到或无法执行。${RESET}"
                echo -e "${RED}!!! 请手动运行 'command -v $cmd_to_check' 或检查服务状态确认。脚本将继续执行，但 $pkg 可能无法正常工作。${RESET}"
                log "警告：包管理器日志 $INSTALL_LOG 显示 $pkg 可能已安装，但命令 '$cmd_to_check' 未在 PATH 中找到。脚本将继续。"
                # 这里选择不退出(continue)，但给用户足够警告
                # 如果希望严格一点，可以在这里 exit 1
            else
                # 如果包管理器本身就可能失败了（日志不存在或没有成功标记）
                echo -e "${RED}!!! $pkg 安装失败。无法找到命令 '$cmd_to_check'。请检查安装日志: $INSTALL_LOG ${RESET}"
                log "错误: $pkg 安装失败。无法找到命令 '$cmd_to_check'。日志: $INSTALL_LOG"
                exit 1 # 如果安装过程本身就可能有问题，则退出
            fi
        else
            # 如果命令找到了，报告成功
            echo -e "${GREEN}$pkg (验证命令: $cmd_to_check) 安装验证成功！${RESET}"
            log "$pkg (验证命令: $cmd_to_check) 安装验证成功！"
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
            firewall-cmd --set-default-zone=trusted --permanent
            # 重新加载防火墙规则使设置生效
            firewall-cmd --reload
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
                firewall-cmd --set-default-zone=trusted --permanent
                firewall-cmd --reload
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
        # 使用更健壮的 Nginx basic auth 正则表达式
        cat > /etc/fail2ban/filter.d/nginx-http-auth.conf <<'EOL'
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
    # 重启前稍微等待一下，确保配置文件写入完成，特别是在慢速系统上
    sleep 1
    systemctl restart fail2ban
    log "Fail2ban 服务已尝试启用并重启。"

    # 检查服务状态
    # 等待几秒让服务有时间启动
    echo -e "${BLUE}等待 fail2ban 服务启动...${RESET}"
    sleep 3
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}fail2ban 已成功配置并启动。${RESET}"
        echo -e "${BLUE}已启用 SSH 防护。其他服务（如Web、FTP、Mail）默认未启用。${RESET}"
        echo -e "${BLUE}请根据你的实际需求，编辑 ${FJB_CONF} 文件，将需要保护的服务对应的 'enabled' 设置为 'true'，然后运行 'systemctl restart fail2ban'。${RESET}"
        log "Fail2ban 配置完成。SSH 默认启用，其他服务需手动在 $FJB_CONF 中启用。"
    else
        echo -e "${RED}Fail2ban 服务启动失败！请检查日志：'journalctl -u fail2ban' 或 /var/log/fail2ban.log ${RESET}"
        log "错误：Fail2ban 服务启动失败！"
        # 这里可以选择是否因为 fail2ban 启动失败而退出脚本
        # exit 1
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
    # 追加写入日志
    echo "$(date '+%F %T') - $1" >> "$LOG_FILE"
}

# ----- 主循环 -----
log "===== 启动 CPU 限制监控守护进程 (v2) ====="
while true; do
    # --- 查找并限制高 CPU 进程 ---
    # 使用 ps 获取 PID, CPU%, 完整命令行 (args)
    # --no-headers 不显示标题
    # --sort=-%cpu 按 CPU 降序排序
    # awk: 过滤掉内核线程([kthreadd]), awk自身, cpulimit, 本脚本; 并且 CPU > 阈值
    ps -eo pid,%cpu,args --no-headers --sort=-%cpu | \
    awk -v ct="$CPU_THRESHOLD" -v lr="$LIMIT_RATE" -v xl="$XRAY_LIMIT" -v log_file="$LOG_FILE" '
    function log_msg(level, message) {
        printf "%s - [%s] %s\n", strftime("%F %T"), level, message >> log_file;
        fflush(log_file); # 确保日志立即写入
    }
    {
        pid = $1;
        cpu = int($2); # 取整比较
        cmd = $3;
        full_cmd = ""; for(i=3; i<=NF; i++) full_cmd = full_cmd $i " "; # 拼接完整命令行

        # 跳过内核线程, awk, cpulimit, 和本脚本自身
        if (cmd ~ /^\[.+\]$/ || cmd == "awk" || cmd == "cpulimit" || full_cmd ~ /cpu_limit\.sh/) {
            next;
        }

        # 检查 CPU 是否超过阈值
        if (cpu >= ct) {
            limit_to = lr; # 默认限制率
            process_type = "常规高CPU进程";

            # 对 xray/x-ui 应用特殊限制率
            if (full_cmd ~ /xray|x-ui/) {
                limit_to = xl;
                process_type = "xray/x-ui进程";
            }

            # 检查是否已被限制 (通过检查是否有 cpulimit -p $pid 在运行)
            # 使用 system() 调用 pgrep，注意引号和转义
            check_cmd = "pgrep -f \"cpulimit .* -p " pid "\" > /dev/null";
            if (system(check_cmd) != 0) {
                # 如果没有被限制，则应用限制
                log_msg("INFO", sprintf("检测到%s: PID=%d (%s), CPU=%d%% >= %d%%. 应用限制 %d%%", process_type, pid, cmd, cpu, ct, limit_to));
                limit_cmd = sprintf("cpulimit -p %d -l %d -b", pid, limit_to);
                ret = system(limit_cmd);
                if (ret != 0) {
                    log_msg("WARN", sprintf("为 PID=%d (%s) 启动 cpulimit 失败，返回码: %d", pid, cmd, ret));
                }
            }
            # else { log_msg("DEBUG", sprintf("进程 PID=%d (%s) 已被限制，跳过", pid, cmd)); } # 可选的调试日志
        }
    }' # awk 脚本结束

    # 等待下一个检查周期
    sleep "$CHECK_INTERVAL"

done # while true 结束
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
# 将标准输出和标准错误都追加到日志文件 (注意: awk脚本内部已重定向日志)
# StandardOutput=append:/var/log/cpu_limit.log
# StandardError=append:/var/log/cpu_limit.log
# 或者直接丢弃脚本的标准输出/错误，因为日志由脚本内部处理
StandardOutput=null
StandardError=null

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
    echo -e "${BLUE}等待 CPU 限制服务启动...${RESET}"
    sleep 3
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
    pkill -f "cpulimit .* -p" # 查找由脚本启动的 cpulimit 进程并杀掉
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
