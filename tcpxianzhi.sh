#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 配置文件路径
NFT_CONFIG="/etc/nftables.conf"
TEMP_RULES="/tmp/nft_rules_add"

# 检测操作系统类型
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}无法检测操作系统类型。${NC}"
    exit 1
fi

# 安装 nftables 及相关工具
install_nftables() {
    echo -e "${YELLOW}检测到操作系统: $OS${NC}"
    case $OS in
        ubuntu|debian)
            echo -e "${YELLOW}正在更新包列表并安装 nftables 及 netfilter-persistent...${NC}"
            sudo apt-get update
            sudo apt-get install -y nftables nftables-persistent
            ;;
        centos|rhel|fedora)
            echo -e "${YELLOW}正在安装 epel-release 和 nftables...${NC}"
            sudo yum install -y epel-release
            sudo yum install -y nftables
            # 启用并启动 nftables 服务
            sudo systemctl enable --now nftables
            echo -e "${YELLOW}nftables 服务已启用并启动。${NC}"
            ;;
        *)
            echo -e "${RED}不支持的操作系统: $OS${NC}"
            exit 1
            ;;
    esac

    # 对于 Ubuntu/Debian，netfilter-persistent 已经安装
    # 对于 CentOS/RHEL/Fedora，nftables 服务已启用

    echo -e "${GREEN}nftables 及相关工具安装成功。${NC}"
}

# 函数：显示菜单
show_menu() {
    echo -e "
${BLUE}===========================${NC}
${BLUE}      nftables 连接数管理      ${NC}
${BLUE}===========================${NC}
${GREEN}1.${NC} 查看当前 nftables 规则
${GREEN}2.${NC} 查看当前 TCP 连接数
${GREEN}3.${NC} 新增端口连接数限制
${GREEN}4.${NC} 删除指定端口的连接数限制
${GREEN}5.${NC} 保存并应用规则
${GREEN}6.${NC} 退出
${BLUE}===========================${NC}
${YELLOW}请选择操作 [1-6]: ${NC}"
}

# 函数：查看当前 nftables 规则
view_rules() {
    if [[ -f "$NFT_CONFIG" ]]; then
        echo -e "${GREEN}当前 nftables 规则:${NC}"
        sudo nft list ruleset
    else
        echo -e "${RED}nftables 配置文件不存在于 $NFT_CONFIG。${NC}"
    fi
}

# 函数：查看当前 TCP 连接数
view_tcp_connections() {
    echo -e "${GREEN}当前 TCP 连接数（每个端口超过 1 个连接）:${NC}"
    sudo ss -tun | awk '{print $5}' | grep -oE '[0-9]+$' | sort | uniq -c | awk '$1 > 1 {print "端口: " $2 " 连接数: " $1}'
}

# 函数：新增端口连接数限制
add_port_limit() {
    read -p "${YELLOW}请输入要限制的端口号: ${NC}" PORT
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo -e "${RED}无效的端口号。请重新运行脚本并输入有效的端口号。${NC}"
        return
    fi

    read -p "${YELLOW}请输入最大连接数: ${NC}" MAX_CONN
    if ! [[ "$MAX_CONN" =~ ^[0-9]+$ ]] || [ "$MAX_CONN" -lt 1 ]; then
        echo -e "${RED}无效的最大连接数。请重新运行脚本并输入有效的数值。${NC}"
        return
    fi

    # 检查是否已存在该端口的规则
    if sudo nft list ruleset | grep -q "tcp dport $PORT ct count over $MAX_CONN"; then
        echo -e "${RED}端口 $PORT 的连接数限制已存在。${NC}"
        return
    fi

    # 添加规则到配置文件
    echo -e "${GREEN}添加端口 $PORT 的连接数限制为 $MAX_CONN ...${NC}"
    sudo tee -a "$NFT_CONFIG" > /dev/null <<EOF
# 限制端口 $PORT 的最大连接数为 $MAX_CONN
table inet filter {
    chain input {
        type filter hook input priority 0; policy accept;
        tcp dport $PORT ct count over $MAX_CONN drop
    }
}
EOF

    echo -e "${YELLOW}规则已添加到配置文件。请运行 '保存并应用规则' 以生效。${NC}"
}

# 函数：删除指定端口的连接数限制
delete_port_limit() {
    read -p "${YELLOW}请输入要删除限制的端口号: ${NC}" PORT
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo -e "${RED}无效的端口号。请重新运行脚本并输入有效的端口号。${NC}"
        return
    fi

    # 检查配置文件中是否存在该端口的规则
    if sudo nft list ruleset | grep -q "tcp dport $PORT ct count over"; then
        # 使用 nft 命令删除规则
        echo -e "${YELLOW}端口 $PORT 的连接数限制存在，正在尝试删除...${NC}"
        
        # 获取规则的句柄
        HANDLE=$(sudo nft list ruleset | awk -v port="$PORT" '
            /table inet filter/ { in_table=1 }
            in_table && /chain input/ { in_chain=1 }
            in_chain && /tcp dport '"$PORT"' ct count over/ {
                match=1
            }
            match && /^}/ {
                exit
            }
            match {
                print $0
            }
        ')

        if [[ -n "$HANDLE" ]]; then
            # 提取句柄编号（假设格式为 "handle X"）
            HANDLE_NUM=$(echo "$HANDLE" | grep -oE 'handle [0-9]+' | awk '{print $2}')
            if [[ -n "$HANDLE_NUM" ]]; then
                # 使用 nft delete rule 命令删除规则
                sudo nft delete rule inet filter input handle "$HANDLE_NUM"
                echo -e "${GREEN}端口 $PORT 的连接数限制已删除。${NC}"
            else
                echo -e "${RED}无法提取规则句柄。${NC}"
            fi
        else
            echo -e "${RED}未找到端口 $PORT 的具体规则。${NC}"
        fi
    else
        echo -e "${RED}端口 $PORT 的连接数限制不存在。${NC}"
    fi
}

# 函数：保存并应用规则
save_and_apply_rules() {
    case $OS in
        ubuntu|debian)
            echo -e "${YELLOW}正在检查 nftables 规则是否已更改...${NC}"
            # Debian/Ubuntu 使用 nftables-persistent 管理规则
            if command -v netfilter-persistent &> /dev/null; then
                sudo netfilter-persistent save
                sudo netfilter-persistent reload
                echo -e "${GREEN}nftables 规则已保存并应用。${NC}"
            else
                echo -e "${YELLOW}netfilter-persistent 未安装。尝试直接加载规则...${NC}"
                sudo nft -f "$NFT_CONFIG"
                echo -e "${YELLOW}规则已应用，但未保存持久化。建议安装 nftables-persistent 并手动保存规则。${NC}"
            fi
            ;;
        centos|rhel|fedora)
            echo -e "${YELLOW}正在应用 nftables 规则...${NC}"
            sudo nft -f "$NFT_CONFIG"
            # CentOS 8+ 使用 nftables 服务
            sudo systemctl restart nftables
            echo -e "${GREEN}nftables 规则已应用并重启服务。${NC}"
            ;;
        *)
            echo -e "${RED}不支持的操作系统。${NC}"
            ;;
    esac
}

# 主循环
while true; do
    show_menu
    read CHOICE
    case $CHOICE in
        1)
            view_rules
            ;;
        2)
            view_tcp_connections
            ;;
        3)
            add_port_limit
            ;;
        4)
            delete_port_limit
            ;;
        5)
            save_and_apply_rules
            ;;
        6)
            echo -e "${GREEN}退出脚本。${NC}"
            break
            ;;
        *)
            echo -e "${RED}无效的选择，请重新选择。${NC}"
            ;;
    esac
    echo ""
done

# 如果需要自动安装 nftables 及相关工具，可以取消下面的注释
install_nftables
