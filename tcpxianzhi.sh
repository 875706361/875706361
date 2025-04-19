#!/bin/bash

# === 配置 ===
# 设置为 true 以启用 IPv6 支持 (脚本会自动检查 ip6 是否可用)
ENABLE_IPV6=true
# 基础防火墙策略 ('ACCEPT' 或 'DROP')
# 'ACCEPT': 默认允许所有流量，仅拒绝超限连接 (类似原始脚本) - 安全性较低
# 'DROP':   默认拒绝所有流量，需要手动允许所需服务 - 安全性较高
# 推荐使用 'DROP'，但为匹配原始脚本意图，此处暂用 'ACCEPT'
DEFAULT_POLICY="ACCEPT"
# 如果使用 DROP 策略，你可能需要允许 SSH (默认 22 端口)
# ALLOW_SSH_PORT=22 # 设置为端口号或 "" 来禁用 (当 DEFAULT_POLICY=DROP 时生效)
# === 配置结束 ===


# 定义颜色 (高亮显示)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# --- 全局变量 ---
OS_ID=""          # e.g., "ubuntu", "centos", "arch", "opensuse-leap"
OS_ID_LIKE=""     # e.g., "debian", "rhel fedora", "arch", "suse opensuse"
PKG_MANAGER=""    # e.g., "apt", "dnf", "yum", "pacman", "zypper"
INSTALL_CMD=""
NFT_CONFIG_PATH=""
NFT_SERVICE_NAME="nftables.service" # 默认服务名
SYSCTL_CMD=""     # systemctl command path

# --- Helper 函数 ---

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：请以 root 权限运行此脚本${NC}"
        exit 1
    fi
    # 检查并缓存 systemctl 命令路径
    if command -v systemctl > /dev/null 2>&1; then
        SYSCTL_CMD=$(command -v systemctl)
    else
        echo -e "${YELLOW}警告: 未找到 systemctl 命令。服务管理和持久化可能受限。${NC}"
    fi
}

# 获取操作系统信息和包管理器
get_os_info() {
    echo -e "${BLUE}正在检测操作系统和包管理器...${NC}"
    if [ -f /etc/os-release ]; then
        # 使用 /etc/os-release (现代标准)
        source /etc/os-release
        OS_ID=$ID
        OS_ID_LIKE=$ID_LIKE
        echo -e "${BLUE}检测到 OS ID: ${OS_ID}, ID_LIKE: ${OS_ID_LIKE}${NC}"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="rhel-legacy" # 标记为旧版 RHEL/CentOS
        OS_ID_LIKE="rhel"
         echo -e "${BLUE}检测到旧版 RHEL/CentOS 系统${NC}"
    elif [ -f /etc/debian_version ]; then
         OS_ID="debian-legacy" # 标记为旧版 Debian
         OS_ID_LIKE="debian"
         echo -e "${BLUE}检测到旧版 Debian 系统${NC}"
    else
        echo -e "${RED}错误：无法识别的操作系统。此脚本可能不兼容。${NC}"
        exit 1
    fi

    # 根据 OS ID 或 ID_LIKE 判断包管理器
    if [[ " $OS_ID_LIKE " == *" debian "* ]] || [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        PKG_MANAGER="apt"
        INSTALL_CMD="apt-get update -y && apt-get install -y"
        NFT_CONFIG_PATH="/etc/nftables.conf"
    elif [[ " $OS_ID_LIKE " == *" rhel "* ]] || [[ " $OS_ID_LIKE " == *" fedora "* ]] || [[ "$OS_ID" == "centos" ]] || [[ "$OS_ID" == "rhel" ]] || [[ "$OS_ID" == "fedora" ]]; then
        if command -v dnf > /dev/null 2>&1; then
            PKG_MANAGER="dnf"
            INSTALL_CMD="dnf install -y"
        elif command -v yum > /dev/null 2>&1; then
             PKG_MANAGER="yum"
             INSTALL_CMD="yum install -y"
        else
            echo -e "${RED}错误：在 RHEL 类系统上未找到 dnf 或 yum。${NC}"
            exit 1
        fi
        # RHEL/CentOS 8+ 使用 /etc/nftables.conf，旧版可能用 /etc/sysconfig/nftables.conf
        if [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" ]] && grep -q -E 'release 7|release 6' /etc/redhat-release 2>/dev/null; then
            NFT_CONFIG_PATH="/etc/sysconfig/nftables.conf" # 旧版路径
             echo -e "${YELLOW}警告：检测到 RHEL/CentOS 7 或更早版本。nftables 支持可能有限，请确保已安装且内核支持。${NC}"
        else
             NFT_CONFIG_PATH="/etc/nftables.conf" # 现代路径
        fi
    elif [[ " $OS_ID_LIKE " == *" arch "* ]] || [[ "$OS_ID" == "arch" ]]; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -Sy --noconfirm" # -S install, -y refresh db
        NFT_CONFIG_PATH="/etc/nftables.conf"
    elif [[ " $OS_ID_LIKE " == *" suse "* ]] || [[ "$OS_ID" == *"opensuse"* ]]; then
         PKG_MANAGER="zypper"
         INSTALL_CMD="zypper install -y"
         NFT_CONFIG_PATH="/etc/nftables.conf"
    else
         echo -e "${RED}错误：无法确定包管理器或不受支持的操作系统 (${OS_ID})。${NC}"
         exit 1
    fi
     echo -e "${GREEN}使用包管理器: ${PKG_MANAGER}, 配置文件路径: ${NFT_CONFIG_PATH}${NC}"
}

# 检查并安装必要的软件包 (nftables, iproute2 等)
install_dependencies() {
    echo -e "${YELLOW}检查并安装必要的软件包...${NC}"
    local pkgs_to_install=()
    local nft_pkg="nftables"
    local iproute_pkg="iproute2" # 大多数发行版的包名
    local awk_pkg="gawk"       # 通常是 gawk
    local grep_pkg="grep"
    local coreutils_pkg="coreutils"

    # 根据发行版调整可能的包名差异
    if [[ "$PKG_MANAGER" == "pacman" ]]; then
        iproute_pkg="iproute2"
    elif [[ "$PKG_MANAGER" == "zypper" ]]; then
         iproute_pkg="iproute2"
    fi

    # 检查 nft 命令
    if ! command -v nft > /dev/null 2>&1; then
        pkgs_to_install+=("$nft_pkg")
    fi
    # 检查 ss 命令 (来自 iproute2)
    if ! command -v ss > /dev/null 2>&1; then
         pkgs_to_install+=("$iproute_pkg")
    fi
    # 检查 awk 命令
    if ! command -v awk > /dev/null 2>&1; then
         pkgs_to_install+=("$awk_pkg")
    fi
     # 检查 grep 命令
    if ! command -v grep > /dev/null 2>&1; then
         pkgs_to_install+=("$grep_pkg")
    fi
     # 检查 ls, sort 等命令 (来自 coreutils)
     if ! command -v ls > /dev/null 2>&1 || ! command -v sort > /dev/null 2>&1; then
         pkgs_to_install+=("$coreutils_pkg")
     fi


    if [ ${#pkgs_to_install[@]} -gt 0 ]; then
        echo -e "${YELLOW}需要安装的软件包: ${pkgs_to_install[*]}${NC}"
        # 执行安装命令
        eval "$INSTALL_CMD ${pkgs_to_install[*]}"
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误：安装软件包失败。请检查错误信息并手动安装: ${pkgs_to_install[*]}${NC}"
            exit 1
        else
             echo -e "${GREEN}软件包安装成功或已存在${NC}"
        fi
    else
        echo -e "${GREEN}所有必要的软件包似乎已安装${NC}"
    fi

    # 再次检查 nft 命令是否可用
     if ! command -v nft > /dev/null 2>&1; then
        echo -e "${RED}错误：安装后仍然无法找到 nft 命令。请检查安装过程。${NC}"
        exit 1
    fi

    # 启用并启动 nftables 服务 (使用缓存的 systemctl 路径)
    if [ -n "$SYSCTL_CMD" ]; then
        if $SYSCTL_CMD list-unit-files | grep -q "^${NFT_SERVICE_NAME}"; then
            if ! $SYSCTL_CMD is-active --quiet $NFT_SERVICE_NAME; then
                echo -e "${YELLOW}启动 $NFT_SERVICE_NAME 服务...${NC}"
                $SYSCTL_CMD start $NFT_SERVICE_NAME || echo -e "${RED}启动 $NFT_SERVICE_NAME 服务失败${NC}"
            fi
            if ! $SYSCTL_CMD is-enabled --quiet $NFT_SERVICE_NAME; then
                echo -e "${YELLOW}启用 $NFT_SERVICE_NAME 服务 (开机启动)...${NC}"
                $SYSCTL_CMD enable $NFT_SERVICE_NAME || echo -e "${RED}启用 $NFT_SERVICE_NAME 服务失败${NC}"
            fi
        else
             echo -e "${YELLOW}警告: 无法找到 $NFT_SERVICE_NAME 服务单元文件。规则可能无法自动加载。${NC}"
        fi
    fi

    # 检查 IPv6 可用性
    if $ENABLE_IPV6 && ! ip -6 route show default > /dev/null 2>&1 && ! test -f /proc/net/if_inet6; then
         echo -e "${YELLOW}警告: 系统似乎未完全启用或配置 IPv6。将禁用 IPv6 相关规则。${NC}"
         ENABLE_IPV6=false
    fi
     echo -e "${GREEN}依赖检查和配置完成${NC}"
}


# 设置基础 nftables 规则
setup_base_rules() {
    echo -e "${YELLOW}正在配置基础 nftables 规则...${NC}"

    # 确保 inet filter 表存在
    nft list table inet filter > /dev/null 2>&1 || nft add table inet filter

    # 确保 input, forward, output 链存在于 inet filter 表
    nft list chain inet filter input > /dev/null 2>&1 || nft add chain inet filter input { type filter hook input priority filter \; }
    nft list chain inet filter forward > /dev/null 2>&1 || nft add chain inet filter forward { type filter hook forward priority filter \; }
    nft list chain inet filter output > /dev/null 2>&1 || nft add chain inet filter output { type filter hook output priority filter \; }

    # 清空我们可能添加的限制规则和集合 (如果再次运行脚本，提供一致性)
    echo -e "${BLUE}清理可能存在的旧限制规则和集合...${NC}"
    local handles_to_delete=$(nft -a list chain inet filter input 2>/dev/null | grep 'comment "connlimit_tcp_' | awk '{print $NF}')
    if [ -n "$handles_to_delete" ]; then
        echo -e "${YELLOW}找到旧规则句柄: $handles_to_delete${NC}"
        for handle in $handles_to_delete; do
            nft delete rule inet filter input handle "$handle" 2>/dev/null # 忽略错误，如果已被删除
        done
    fi
    local sets_to_delete=$(nft list sets 2>/dev/null | grep 'connlimit_tcp_')
     if [ -n "$sets_to_delete" ]; then
        echo -e "${YELLOW}找到旧集合: $sets_to_delete${NC}"
        # 解析 set name 并删除
        echo "$sets_to_delete" | grep '^set' | awk '{print $2}' | while read -r set_name; do
             nft delete set inet filter "$set_name" 2>/dev/null # 忽略错误
        done
     fi

    # 设置默认策略
    echo -e "${YELLOW}设置默认策略 => INPUT: $DEFAULT_POLICY, FORWARD: $DEFAULT_POLICY, OUTPUT: accept ${NC}"
    nft chain inet filter input { policy $DEFAULT_POLICY \; }
    nft chain inet filter forward { policy $DEFAULT_POLICY \; } # 通常设为 DROP，除非是路由器
    nft chain inet filter output { policy accept \; } # 通常允许出站

    # 插入基础规则 (使用 insert 确保它们在链的顶部附近，或使用 priority)
    # 允许本地回环接口
    nft insert rule inet filter input iifname "lo" accept comment \"allow_loopback\"
    # 允许已建立和相关的连接 (非常重要)
    nft insert rule inet filter input ct state related,established accept comment \"allow_established_related\"
    # 可选：丢弃无效状态的包
    nft insert rule inet filter input ct state invalid drop comment \"drop_invalid\"

    # 允许 ICMP (Ping等) - 对于网络诊断很重要
    nft add rule inet filter input ip protocol icmp accept comment \"allow_icmpv4\" 2>/dev/null || \
    nft insert rule inet filter input ip protocol icmp accept comment \"allow_icmpv4\" # 如果 add 失败 (规则已存在)，尝试 insert
    if $ENABLE_IPV6; then
        nft add rule inet filter input ip6 nexthdr icmpv6 accept comment \"allow_icmpv6\" 2>/dev/null || \
        nft insert rule inet filter input ip6 nexthdr icmpv6 accept comment \"allow_icmpv6\"
    fi

    # 如果策略是 DROP，并且配置了允许 SSH 端口
    # if [ "$DEFAULT_POLICY" = "DROP" ] && [ -n "$ALLOW_SSH_PORT" ] && [[ "$ALLOW_SSH_PORT" =~ ^[0-9]+$ ]]; then
    #      echo -e "${YELLOW}由于策略为 DROP，添加入站 SSH (端口 $ALLOW_SSH_PORT) 规则...${NC}"
    #      nft add rule inet filter input tcp dport "$ALLOW_SSH_PORT" accept comment \"allow_ssh_${ALLOW_SSH_PORT}\" 2>/dev/null || \
    #      nft insert rule inet filter input tcp dport "$ALLOW_SSH_PORT" accept comment \"allow_ssh_${ALLOW_SSH_PORT}\"
    # fi

    echo -e "${GREEN}基础 nftables 规则已设置${NC}"
    if [ "$DEFAULT_POLICY" = "ACCEPT" ]; then
         echo -e "${YELLOW}警告：当前输入链默认策略为 ACCEPT。为了提高安全性，建议在确认所有必需服务都已允许后，考虑将默认策略更改为 DROP。${NC}"
    fi
}


# 添加 TCP 端口连接限制规则
add_tcp_rule() {
    echo -e "${YELLOW}请输入要添加限制规则的 TCP 端口号:${NC}"
    read port
    if [[ ! $port =~ ^[0-9]+$ ]] || [ "$port" -gt 65535 ] || [ "$port" -lt 1 ]; then
        echo -e "${RED}错误：请输入有效的端口号 (1-65535)${NC}"
        return
    fi
    echo -e "${YELLOW}请输入该端口允许的【每个 IP】最大连接数:${NC}"
    read limit
    if [[ ! $limit =~ ^[0-9]+$ ]] || [ "$limit" -lt 1 ]; then
        echo -e "${RED}错误：请输入有效的连接数 (至少为 1)${NC}"
        return
    fi

    local set_name_v4="connlimit_tcp_v4_${port}"
    local set_name_v6="connlimit_tcp_v6_${port}"
    local rule_comment_v4="connlimit_tcp_v4_${port}_rule"
    local rule_comment_v6="connlimit_tcp_v6_${port}_rule"

    # 检查 IPv4 规则是否已存在 (通过注释)
    if nft -a list chain inet filter input 2>/dev/null | grep -q "comment \"$rule_comment_v4\""; then
        echo -e "${YELLOW}端口 $port 的 IPv4 限制规则似乎已存在。${NC}"
    else
        # 创建 IPv4 set (如果不存在)
        nft list set inet filter "$set_name_v4" > /dev/null 2>&1 || \
            nft add set inet filter "$set_name_v4" { type ipv4_addr\; flags dynamic, timeout\; timeout 60s\; counter\; size 65536\; }

        # 添加 IPv4 规则
        echo -e "${BLUE}添加 IPv4 规则: 端口 $port, 限制 $limit 连接/IP${NC}"
        # 使用 insert 将规则添加到 established/related 规则之后，但在默认策略之前
        nft insert rule inet filter input ip protocol tcp tcp dport "$port" ct state new \
            update @$set_name_v4 { ip saddr counter packets 1 } \
            gt "$limit" reject with tcp reset comment \"$rule_comment_v4\"

        if [ $? -ne 0 ]; then
             echo -e "${RED}添加 IPv4 规则失败${NC}"
        else
             echo -e "${GREEN}IPv4 规则添加成功${NC}"
        fi
    fi

    if $ENABLE_IPV6; then
       if nft -a list chain inet filter input 2>/dev/null | grep -q "comment \"$rule_comment_v6\""; then
           echo -e "${YELLOW}端口 $port 的 IPv6 限制规则似乎已存在。${NC}"
       else
           # 创建 IPv6 set (如果不存在)
           nft list set inet filter "$set_name_v6" > /dev/null 2>&1 || \
                nft add set inet filter "$set_name_v6" { type ipv6_addr\; flags dynamic, timeout\; timeout 60s\; counter\; size 65536\; }

            # 添加 IPv6 规则
            echo -e "${BLUE}添加 IPv6 规则: 端口 $port, 限制 $limit 连接/IP${NC}"
            nft insert rule inet filter input ip6 nexthdr tcp tcp dport "$port" ct state new \
                update @$set_name_v6 { ip6 saddr counter packets 1 } \
                gt "$limit" reject with tcp reset comment \"$rule_comment_v6\"

            if [ $? -ne 0 ]; then
                 echo -e "${RED}添加 IPv6 规则失败${NC}"
            else
                 echo -e "${GREEN}IPv6 规则添加成功${NC}"
            fi
       fi
    fi
    echo ""
}

# 删除 TCP 端口连接限制规则
delete_tcp_rule() {
    echo -e "${YELLOW}请输入要删除限制规则的 TCP 端口号:${NC}"
    read port
     if [[ ! $port =~ ^[0-9]+$ ]] || [ "$port" -gt 65535 ] || [ "$port" -lt 1 ]; then
        echo -e "${RED}错误：请输入有效的端口号 (1-65535)${NC}"
        return
    fi

    local rule_comment_v4="connlimit_tcp_v4_${port}_rule"
    local rule_comment_v6="connlimit_tcp_v6_${port}_rule"
    local set_name_v4="connlimit_tcp_v4_${port}"
    local set_name_v6="connlimit_tcp_v6_${port}"
    local deleted_v4=false
    local deleted_v6=false

    # 删除 IPv4 规则 (通过注释找到句柄)
    local handle_v4=$(nft -a list chain inet filter input 2>/dev/null | grep "comment \"$rule_comment_v4\"" | awk '{print $NF}')
    if [ -n "$handle_v4" ]; then
        echo -e "${BLUE}找到 IPv4 规则 (句柄 $handle_v4)，正在删除...${NC}"
        nft delete rule inet filter input handle "$handle_v4"
        if [ $? -eq 0 ]; then
             echo -e "${GREEN}IPv4 规则已删除${NC}"
             deleted_v4=true
             # 考虑自动删除关联的 set (如果不再有规则使用它)
             # 简单起见，暂时不删除 set，让条目自动超时
             # nft delete set inet filter "$set_name_v4" 2>/dev/null
        else
             echo -e "${RED}删除 IPv4 规则失败 (句柄: $handle_v4)${NC}"
        fi
    else
        echo -e "${BLUE}未找到端口 $port 的 IPv4 限制规则${NC}"
    fi

    # 删除 IPv6 规则
    if $ENABLE_IPV6; then
        local handle_v6=$(nft -a list chain inet filter input 2>/dev/null | grep "comment \"$rule_comment_v6\"" | awk '{print $NF}')
         if [ -n "$handle_v6" ]; then
            echo -e "${BLUE}找到 IPv6 规则 (句柄 $handle_v6)，正在删除...${NC}"
            nft delete rule inet filter input handle "$handle_v6"
             if [ $? -eq 0 ]; then
                 echo -e "${GREEN}IPv6 规则已删除${NC}"
                 deleted_v6=true
                 # nft delete set inet filter "$set_name_v6" 2>/dev/null
            else
                 echo -e "${RED}删除 IPv6 规则失败 (句柄: $handle_v6)${NC}"
            fi
        else
            echo -e "${BLUE}未找到端口 $port 的 IPv6 限制规则${NC}"
        fi
    fi
     echo ""
}

# 查看当前规则 (使用高亮)
view_rules() {
    echo -e "${BLUE}--- 当前 nftables 规则集 (高亮相关部分) ---${NC}"
    # 使用 grep 高亮 'connlimit_tcp_', 'policy', 和链定义行
    nft -a list ruleset | grep --color=always -E '^\s*chain |^\s*set connlimit_tcp_|comment "connlimit_tcp_|policy ' || nft list ruleset
    echo ""
}

# 查看 TCP 连接数 (高亮)
view_tcp_connections() {
    echo -e "${BLUE}--- 当前 TCPv4 连接数（按源IP统计，前20）---${NC}"
    # 使用 ss 并高亮输出行
    ss -tn state established | awk 'NR>1 {print $4}' | cut -d: -f1 | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | sort | uniq -c | sort -nr | head -20 | while IFS= read -r line; do
        echo -e "${GREEN}$line${NC}" # 高亮显示每一行结果
    done
    echo ""

    if $ENABLE_IPV6; then
        echo -e "${BLUE}--- 当前 TCPv6 连接数（按源IP统计，前20）---${NC}"
        # 使用 ss 并高亮输出行
        ss -t6n state established | awk 'NR>1 {print $4}' | sed -e 's/\[//g' -e 's/\]:.*$//g' | grep -v '^::1$' | grep -v '^fe80' | sort | uniq -c | sort -nr | head -20 | while IFS= read -r line; do
             echo -e "${GREEN}$line${NC}" # 高亮显示每一行结果
        done
        echo ""
    fi
}


# 保存并应用规则
save_and_apply() {
    if [ -z "$NFT_CONFIG_PATH" ]; then
        echo -e "${RED}错误：无法确定 nftables 配置文件路径。无法保存。${NC}"
        return 1
    fi
    echo -e "${YELLOW}正在保存当前规则到 $NFT_CONFIG_PATH ...${NC}"
    # 备份旧配置
    if [ -f "$NFT_CONFIG_PATH" ]; then
        cp "$NFT_CONFIG_PATH" "$NFT_CONFIG_PATH.bak_$(date +%Y%m%d%H%M%S)"
        echo -e "${BLUE}旧配置已备份到 $NFT_CONFIG_PATH.bak_...${NC}"
    fi

    # 获取当前规则集并保存
    nft list ruleset > "$NFT_CONFIG_PATH"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}规则已保存到 $NFT_CONFIG_PATH ${NC}"
        if [ -n "$SYSCTL_CMD" ]; then
            echo -e "${YELLOW}尝试重新加载 $NFT_SERVICE_NAME 服务以应用持久化规则...${NC}"
            $SYSCTL_CMD reload $NFT_SERVICE_NAME
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}$NFT_SERVICE_NAME 服务已重新加载${NC}"
            else
                # reload 失败有时需要 restart
                echo -e "${YELLOW}Reload 失败，尝试 restart $NFT_SERVICE_NAME ...${NC}"
                 $SYSCTL_CMD restart $NFT_SERVICE_NAME
                 if [ $? -eq 0 ]; then
                     echo -e "${GREEN}$NFT_SERVICE_NAME 服务已重启并应用规则${NC}"
                 else
                    echo -e "${RED}重新加载和重启 $NFT_SERVICE_NAME 服务均失败。规则已保存但可能未激活。请手动检查: 'systemctl status $NFT_SERVICE_NAME' 或 'nft list ruleset'${NC}"
                 fi
            fi
        else
             echo -e "${YELLOW}警告：未找到 systemctl。规则已保存，但需要手动激活或确保系统引导时加载 $NFT_CONFIG_PATH。${NC}"
        fi
    else
        echo -e "${RED}保存规则到 $NFT_CONFIG_PATH 失败${NC}"
    fi
    echo ""
}

# 卸载所有配置及软件
uninstall_all() {
    read -p "$(echo -e ${YELLOW}"确定要移除所有由本脚本添加的 nftables 规则和集合，并卸载 nftables 吗？ (y/N): "${NC})" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}操作已取消${NC}"
        return
    fi

    echo -e "${YELLOW}正在移除本脚本添加的 nftables 规则和集合...${NC}"
    # 删除规则
    local handles_to_delete=$(nft -a list chain inet filter input 2>/dev/null | grep 'comment "connlimit_tcp_' | awk '{print $NF}')
     if [ -n "$handles_to_delete" ]; then
        for handle in $handles_to_delete; do
            nft delete rule inet filter input handle "$handle" 2>/dev/null
        done
        echo -e "${GREEN}限制规则已尝试移除${NC}"
    else
        echo -e "${BLUE}未找到需要移除的限制规则${NC}"
    fi

    # 删除集合
    local sets_to_delete=$(nft list sets 2>/dev/null | grep 'connlimit_tcp_')
     if [ -n "$sets_to_delete" ]; then
        echo "$sets_to_delete" | grep '^set' | awk '{print $2}' | while read -r set_name; do
            nft delete set inet filter "$set_name" 2>/dev/null
        done
         echo -e "${GREEN}限制集合已尝试移除${NC}"
     else
        echo -e "${BLUE}未找到需要移除的限制集合${NC}"
     fi

    echo -e "${YELLOW}正在尝试保存清理后的规则集...${NC}"
    save_and_apply # 保存移除规则/集合后的状态

    if [ -n "$SYSCTL_CMD" ]; then
        echo -e "${YELLOW}正在停止并禁用 $NFT_SERVICE_NAME 服务...${NC}"
        $SYSCTL_CMD stop $NFT_SERVICE_NAME > /dev/null 2>&1
        $SYSCTL_CMD disable $NFT_SERVICE_NAME > /dev/null 2>&1
    fi

    echo -e "${YELLOW}正在卸载 nftables 软件包 (${PKG_MANAGER})...${NC}"
     case "$PKG_MANAGER" in
        apt)
            apt-get remove --purge -y nftables && apt-get autoremove -y
            ;;
        dnf)
            dnf remove -y nftables
            ;;
        yum)
            yum remove -y nftables
            ;;
        pacman)
            pacman -Rns --noconfirm nftables
            ;;
        zypper)
            zypper remove -y nftables
            ;;
        *)
            echo -e "${RED}无法确定卸载命令。请手动卸载 nftables。${NC}"
            ;;
     esac

    echo -e "${GREEN}nftables 及相关配置已卸载${NC}"
    echo -e "${YELLOW}注意：基础网络和防火墙状态可能需要手动检查或恢复到卸载前的状态。${NC}"
    exit 0
}

# 主菜单 (使用高亮)
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}=== nftables 交互式TCP连接数限制管理工具 (v2) ===${NC}"
        echo -e "${BLUE}  OS: ${OS_ID:-未知} | IPv6: ${ENABLE_IPV6} | Policy: ${DEFAULT_POLICY} | Config: ${NFT_CONFIG_PATH:-未知}${NC}"
        echo -e "----------------------------------------------------------"
        echo -e "${GREEN} 1. 查看当前规则${NC}"
        echo -e "${GREEN} 2. 查看 TCP 连接数统计 (按IP)${NC}"
        echo -e "${GREEN} 3. 删除 TCP 端口限制规则${NC}"
        echo -e "${GREEN} 4. 新增 TCP 端口限制规则${NC}"
        echo -e "${GREEN} 5. ${YELLOW}保存规则并应用 (持久化)${NC}"
        echo -e "${GREEN} 6. ${RED}卸载本工具及 nftables${NC}"
        echo -e "${GREEN} 7. 退出${NC}"
        echo -e "----------------------------------------------------------"
        echo -e "${YELLOW}请选择操作 (1-7):${NC}"
        read choice

        case $choice in
            1) view_rules ;;
            2) view_tcp_connections ;;
            3) delete_tcp_rule ;;
            4) add_tcp_rule ;;
            5) save_and_apply ;;
            6) uninstall_all ;;
            7) echo -e "${GREEN}退出程序${NC}"; exit 0 ;;
            *) echo -e "${RED}无效的选择，请输入 1-7${NC}" ;;
        esac
        echo ""
        read -p "$(echo -e ${YELLOW}"按 Enter 键继续..."${NC})"
    done
}

# --- 脚本执行入口 ---
echo -e "${BLUE}--- 初始化脚本 ---${NC}"
check_root
get_os_info
install_dependencies
# 每次启动脚本时，重新设置基础规则，确保环境一致性
# 这也会清除之前通过脚本添加的限制规则，需要重新添加
setup_base_rules
echo -e "${GREEN}--- 初始化完成 ---${NC}"
# 进入主菜单
main_menu
