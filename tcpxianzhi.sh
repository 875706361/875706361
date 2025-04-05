#!/bin/bash

# 配置文件路径
NFT_CONFIG="/etc/nftables.conf"
TEMP_RULES="/tmp/nft_rules_add"

# 检测操作系统类型
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法检测操作系统类型。"
    exit 1
fi

# 安装 nftables 工具
install_nftables() {
    echo "检测到操作系统: $OS"
    case $OS in
        ubuntu|debian)
            echo "正在更新包列表并安装 nftables..."
            sudo apt-get update
            sudo apt-get install -y nftables
            ;;
        centos|rhel|fedora)
            echo "正在安装 epel-release 和 nftables..."
            sudo yum install -y epel-release
            sudo yum install -y nftables
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac

    # 启动并启用 nftables 服务
    case $OS in
        ubuntu|debian)
            sudo systemctl enable --now nftables
            ;;
        centos|rhel|fedora)
            # CentOS 8+ 使用 systemd 管理 nftables
            sudo systemctl enable --now nftables
            ;;
    esac

    echo "nftables 安装并启动成功。"
}

# 函数：显示菜单
show_menu() {
    echo "==========================="
    echo "      nftables 连接数管理      "
    echo "==========================="
    echo "1. 查看当前 nftables 规则"
    echo "2. 查看当前 TCP 连接数"
    echo "3. 新增端口连接数限制"
    echo "4. 删除指定端口的连接数限制"
    echo "5. 保存并应用规则"
    echo "6. 退出"
    echo "==========================="
    echo -n "请选择操作 [1-6]: "
}

# 函数：查看当前 nftables 规则
view_rules() {
    if [[ -f "$NFT_CONFIG" ]]; then
        echo "当前 nftables 规则:"
        sudo nft list ruleset
    else
        echo "nftables 配置文件不存在于 $NFT_CONFIG。"
    fi
}

# 函数：查看当前 TCP 连接数
view_tcp_connections() {
    echo "当前 TCP 连接数（每个端口超过 1 个连接）:"
    sudo ss -tun | awk '{print $5}' | grep -oE '[0-9]+$' | sort | uniq -c | awk '$1 > 1 {print "端口: " $2 " 连接数: " $1}'
}

# 函数：新增端口连接数限制
add_port_limit() {
    read -p "请输入要限制的端口号: " PORT
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo "无效的端口号。请重新运行脚本并输入有效的端口号。"
        return
    fi

    read -p "请输入最大连接数: " MAX_CONN
    if ! [[ "$MAX_CONN" =~ ^[0-9]+$ ]] || [ "$MAX_CONN" -lt 1 ]; then
        echo "无效的最大连接数。请重新运行脚本并输入有效的数值。"
        return
    fi

    # 检查是否已存在该端口的规则
    if sudo nft list ruleset | grep -q "tcp dport $PORT ct count over $MAX_CONN"; then
        echo "端口 $PORT 的连接数限制已存在。"
        return
    fi

    # 添加规则到临时文件
    echo "添加端口 $PORT 的连接数限制为 $MAX_CONN ..."
    sudo tee -a "$NFT_CONFIG" > /dev/null <<EOF
# 限制端口 $PORT 的最大连接数为 $MAX_CONN
table inet filter {
    chain input {
        type filter hook input priority 0; policy accept;
        tcp dport $PORT ct count over $MAX_CONN drop
    }
}
EOF

    echo "规则已添加到配置文件。请运行 '保存并应用规则' 以生效。"
}

# 函数：删除指定端口的连接数限制
delete_port_limit() {
    read -p "请输入要删除限制的端口号: " PORT
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo "无效的端口号。请重新运行脚本并输入有效的端口号。"
        return
    fi

    # 检查配置文件中是否存在该端口的规则
    if sudo nft list ruleset | grep -q "tcp dport $PORT ct count over"; then
        # 使用 nft 命令删除规则
        # 注意：这需要精确匹配规则，以下方法仅作为示例，实际应用中可能需要更复杂的逻辑
        # 这里假设规则的顺序固定，不推荐在生产环境中使用
        # 更好的方法是手动管理规则或使用更精确的匹配方式

        echo "端口 $PORT 的连接数限制存在，正在尝试删除..."
        # 获取规则的句柄（需要更复杂的解析）
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
                sudo nft delete rule inet filter input handle "$HANDLE_NUM"
                echo "端口 $PORT 的连接数限制已删除。"
            else
                echo "无法提取规则句柄。"
            fi
        else
            echo "未找到端口 $PORT 的具体规则。"
        fi
    else
        echo "端口 $PORT 的连接数限制不存在。"
    fi
}

# 函数：保存并应用规则
save_and_apply_rules() {
    case $OS in
        ubuntu|debian)
            echo "正在检查 nftables 规则是否已更改..."
            # Debian/Ubuntu 使用 nftables-persistent 管理规则
            if command -v netfilter-persistent &> /dev/null; then
                sudo netfilter-persistent save
                sudo netfilter-persistent reload
                echo "nftables 规则已保存并应用。"
            else
                echo "netfilter-persistent 未安装。尝试直接加载规则..."
                sudo nft -f "$NFT_CONFIG"
                # 提示用户手动保存规则
                echo "规则已应用，但未保存持久化。建议安装 nftables-persistent 并手动保存规则。"
            fi
            ;;
        centos|rhel|fedora)
            echo "正在应用 nftables 规则..."
            sudo nft -f "$NFT_CONFIG"
            # CentOS 8+ 使用 nftables 服务
            sudo systemctl restart nftables
            echo "nftables 规则已应用并重启服务。"
            ;;
        *)
            echo "不支持的操作系统。"
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
            echo "退出脚本。"
            break
            ;;
        *)
            echo "无效的选择，请重新选择。"
            ;;
    esac
    echo ""
done

# 如果需要自动安装 nftables，可以取消下面的注释
install_nftables
