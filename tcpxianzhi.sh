#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查并安装必要的软件包
install_dependencies() {
    echo -e "${YELLOW}检查并安装必要的软件包...${NC}"
    PKGS="iptables net-tools iproute2 awk grep coreutils"
    if [ -f /etc/redhat-release ]; then
        yum install -y $PKGS
        systemctl enable iptables 2>/dev/null
        systemctl start iptables 2>/dev/null
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
        apt-get update -y
        apt-get install -y $PKGS
    else
        echo -e "${RED}不支持的操作系统${NC}"
        exit 1
    fi
    echo -e "${GREEN}软件包安装完成${NC}"
}

# 全放行iptables
allow_all_iptables() {
    echo -e "${YELLOW}正在配置iptables为完全放行，仅用于连接数限制...${NC}"
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F
    iptables -X
    # 防止connlimit规则被链前DROP覆盖，特意不设置DROP策略
    echo -e "${GREEN}iptables已设置为全部放行，仅用于连接数限制${NC}"
}

# 卸载所有配置及软件
uninstall_all() {
    echo -e "${YELLOW}正在卸载所有配置及软件...${NC}"
    if [ -f /etc/redhat-release ]; then
        yum remove -y iptables net-tools iproute2 awk grep coreutils
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
        apt-get remove -y iptables net-tools iproute2 awk grep coreutils
        apt-get autoremove -y
    fi
    echo -e "${GREEN}所有配置及软件已卸载${NC}"
    exit 0
}

# 保存并应用规则
save_and_apply() {
    echo -e "${YELLOW}正在保存并应用规则...${NC}"
    if [ -f /etc/redhat-release ]; then
        service iptables save 2>/dev/null
        systemctl restart iptables 2>/dev/null
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
        iptables-save > /etc/iptables.rules
        # 可选：恢复规则到启动(推荐手动配置)
        # iptables-restore < /etc/iptables.rules
    fi
    echo -e "${GREEN}规则已保存并应用${NC}"
    echo ""
}

# 查看当前 iptables 规则
view_rules() {
    echo -e "${BLUE}当前 iptables 规则:${NC}"
    iptables -L -n --line-numbers | grep --color=auto -E "dpt:|CONNLIMIT|REJECT|ACCEPT"
    echo ""
}

# 查看 TCP 连接数
view_tcp_connections() {
    echo -e "${BLUE}当前 TCP 端口连接数（前20 IP）:${NC}"
    ss -tn state established | awk '{print $5}' | cut -d: -f1 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort | uniq -c | sort -nr | head -20 | while read line; do
        echo -e "${GREEN}$line${NC}"
    done
    echo ""
}

# 删除指定 TCP 端口的规则
delete_tcp_rule() {
    echo -e "${YELLOW}请输入要删除的 TCP 端口号:${NC}"
    read port
    if [[ ! $port =~ ^[0-9]+$ ]]; then
        echo -e "${RED}请输入有效的端口号${NC}"
        return
    fi
    # 查找并删除该端口的所有 connlimit 规则
    while iptables -C INPUT -p tcp --dport "$port" -m connlimit --connlimit-above 1 -j REJECT 2>/dev/null; do
        num=$(iptables -L INPUT --line-numbers | grep "tcp dpt:$port" | grep CONNLIMIT | awk '{print $1}' | head -1)
        if [ -n "$num" ]; then
            iptables -D INPUT "$num"
        else
            break
        fi
    done
    echo -e "${GREEN}端口 $port 的限制规则已删除（如有存在）${NC}"
    echo ""
}

# 新增 TCP 端口规则并限制每IP连接数
add_tcp_rule() {
    echo -e "${YELLOW}请输入要添加的 TCP 端口号:${NC}"
    read port
    if [[ ! $port =~ ^[0-9]+$ ]]; then
        echo -e "${RED}请输入有效的端口号${NC}"
        return
    fi
    echo -e "${YELLOW}请输入每IP最大连接数:${NC}"
    read limit
    if [[ ! $limit =~ ^[0-9]+$ ]]; then
        echo -e "${RED}请输入有效的连接数${NC}"
        return
    fi
    # 检查是否已存在此规则
    iptables -C INPUT -p tcp --dport "$port" -m connlimit --connlimit-above "$limit" -j REJECT 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}该规则已存在，无需重复添加${NC}"
    else
        iptables -I INPUT -p tcp --dport "$port" -m connlimit --connlimit-above "$limit" -j REJECT
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}端口 $port 的规则已添加，每IP最大连接数限制为 $limit${NC}"
        else
            echo -e "${RED}添加端口 $port 规则失败${NC}"
        fi
    fi
    echo ""
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}=== iptables 交互式TCP连接数限制管理工具（全端口放行版） ===${NC}"
        echo -e "${GREEN}1. 查看当前 iptables 规则${NC}"
        echo -e "${GREEN}2. 查看 TCP 连接数（前20 IP）${NC}"
        echo -e "${GREEN}3. 删除 TCP 端口限制规则${NC}"
        echo -e "${GREEN}4. 新增 TCP 端口规则并限制每IP连接数${NC}"
        echo -e "${GREEN}5. 保存并应用规则${NC}"
        echo -e "${GREEN}6. 卸载所有配置及软件${NC}"
        echo -e "${GREEN}7. 退出${NC}"
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
        echo -e "${YELLOW}按 Enter 键继续...${NC}"
        read
    done
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本${NC}"
    exit 1
fi

install_dependencies
allow_all_iptables
main_menu
