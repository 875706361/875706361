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
    if [ -f /etc/redhat-release ]; then
        # CentOS 系统
        PKG_MANAGER="yum"
        $PKG_MANAGER install -y nftables net-tools iproute2 awk grep coreutils
        systemctl enable nftables
        systemctl start nftables
    elif [ -f /etc/lsb-release ]; then
        # Ubuntu 系统
        PKG_MANAGER="apt-get"
        $PKG_MANAGER update -y
        $PKG_MANAGER install -y nftables net-tools iproute2 awk grep coreutils
        systemctl enable nftables
        systemctl start nftables
    else
        echo -e "${RED}不支持的操作系统${NC}"
        exit 1
    fi
    echo -e "${GREEN}软件包安装完成${NC}"
}

# 卸载所有配置及软件
uninstall_all() {
    echo -e "${YELLOW}正在卸载所有配置及软件...${NC}"
    if [ -f /etc/redhat-release ]; then
        # CentOS 系统
        systemctl stop nftables
        systemctl disable nftables
        yum remove -y nftables net-tools iproute2 awk grep coreutils
        rm -f /etc/nftables.conf
    elif [ -f /etc/lsb-release ]; then
        # Ubuntu 系统
        systemctl stop nftables
        systemctl disable nftables
        apt-get remove -y nftables net-tools iproute2 awk grep coreutils
        apt-get autoremove -y
        rm -f /etc/nftables.conf
    fi
    echo -e "${GREEN}所有配置及软件已卸载${NC}"
    exit 0
}

# 保存并应用规则
save_and_apply() {
    echo -e "${YELLOW}正在保存并应用规则...${NC}"
    nft list ruleset > /etc/nftables.conf
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}规则已保存到 /etc/nftables.conf${NC}"
        echo -e "${YELLOW}正在重启 nftables 服务...${NC}"
        systemctl restart nftables
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}nftables 服务已重启，规则已应用${NC}"
        else
            echo -e "${RED}重启 nftables 服务失败${NC}"
        fi
    else
        echo -e "${RED}保存规则失败${NC}"
    fi
    echo ""
}

# 查看当前 nftables 规则
view_rules() {
    echo -e "${BLUE}当前 nftables 规则:${NC}"
    nft list ruleset
    echo ""
}

# 查看 TCP 连接数
view_tcp_connections() {
    echo -e "${BLUE}当前 TCP 端口连接数:${NC}"
    ss -tun | awk '{print $5}' | grep -oE '[0-9]+$' | sort | uniq -c | awk '$1 > 1 {print "端口: " $2 " 连接数: " $1}' | while read line; do
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
    echo -e "${YELLOW}正在删除端口 $port 的规则...${NC}"
    nft delete rule filter input tcp dport "$port" 2>/dev/null
    nft delete rule filter output tcp sport "$port" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}端口 $port 的规则已删除${NC}"
    else
        echo -e "${RED}未找到端口 $port 的规则或删除失败${NC}"
    fi
    echo ""
}

# 新增 TCP 端口规则并限制连接数
add_tcp_rule() {
    echo -e "${YELLOW}请输入要添加的 TCP 端口号:${NC}"
    read port
    if [[ ! $port =~ ^[0-9]+$ ]]; then
        echo -e "${RED}请输入有效的端口号${NC}"
        return
    fi
    echo -e "${YELLOW}请输入最大 TCP 连接数:${NC}"
    read limit
    if [[ ! $limit =~ ^[0-9]+$ ]]; then
        echo -e "${RED}请输入有效的连接数${NC}"
        return
    fi
    echo -e "${YELLOW}正在添加端口 $port 的规则，限制连接数为 $limit...${NC}"
    nft list table filter >/dev/null 2>&1 || nft add table filter
    nft list chain filter input >/dev/null 2>&1 || nft add chain filter input { type filter hook input priority 0 \; }
    nft list chain filter output >/dev/null 2>&1 || nft add chain filter output { type filter hook output priority 0 \; }
    nft add rule filter input tcp dport "$port" ct count "$limit" accept
    nft add rule filter output tcp sport "$port" ct count "$limit" accept
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}端口 $port 的规则已添加，最大连接数限制为 $limit${NC}"
    else
        echo -e "${RED}添加端口 $port 规则失败${NC}"
    fi
    echo ""
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}=== Netfilter (nftables) 交互式管理工具 ===${NC}"
        echo -e "${GREEN}1. 查看当前 nftables 规则${NC}"
        echo -e "${GREEN}2. 查看 TCP 连接数${NC}"
        echo -e "${GREEN}3. 删除 TCP 端口规则${NC}"
        echo -e "${GREEN}4. 新增 TCP 端口规则并限制连接数${NC}"
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

# 安装依赖并启动主菜单
install_dependencies
main_menu
