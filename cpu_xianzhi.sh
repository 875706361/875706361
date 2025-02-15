#!/bin/bash

# 颜色定义
GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

# 相关文件路径
SCRIPT_PATH="/usr/local/bin/cpu_limit.sh"
SERVICE_PATH="/etc/systemd/system/cpu_limit.service"
LOG_FILE="/var/log/cpu_limit.log"

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}无法检测系统类型，退出！${RESET}"
        exit 1
    fi
}

# 安装 cpulimit
install_cpulimit() {
    if command -v cpulimit &>/dev/null; then
        echo -e "${GREEN}cpulimit 已安装，无需重复安装。${RESET}"
        return
    fi

    echo -e "${GREEN}正在安装 cpulimit...${RESET}"

    case "$OS" in
    ubuntu | debian)
        apt update -y && apt install -y cpulimit
        ;;
    almalinux | centos | rocky)
        yum install -y epel-release && yum install -y cpulimit
        ;;
    *)
        echo -e "${RED}不支持的系统类型：$OS${RESET}"
        exit 1
        ;;
    esac

    if command -v cpulimit &>/dev/null; then
        echo -e "${GREEN}cpulimit 安装成功！${RESET}"
    else
        echo -e "${RED}cpulimit 安装失败，请检查网络或手动安装。${RESET}"
        exit 1
    fi
}

# 创建 CPU 限制脚本
create_cpu_limit_script() {
    echo -e "${GREEN}创建 CPU 监控脚本...${RESET}"
    cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash

LOG_FILE="/var/log/cpu_limit.log"

echo "\$(date) - 启动 CPU 限制进程..." >> "\$LOG_FILE"

while true; do
    # 查找 CPU 使用率超过 90% 的进程
    high_cpu_process=\$(ps -eo pid,%cpu,comm --sort=-%cpu | awk '\$2>90 {print \$1}' | head -n 1)

    if [ -n "\$high_cpu_process" ]; then
        echo "\$(date) - 限制进程 \$high_cpu_process CPU 占用" >> "\$LOG_FILE"
        cpulimit -p "\$high_cpu_process" -l 90 -b
    fi

    sleep 5  # 每 5 秒检查一次
done
EOF

    chmod +x "$SCRIPT_PATH"
}

# 创建 systemd 服务
create_systemd_service() {
    echo -e "${GREEN}创建 systemd 服务...${RESET}"
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=CPU 限制进程守护
After=network.target

[Service]
ExecStart=$SCRIPT_PATH
Restart=always
RestartSec=5
User=root
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF
}

# 启动 CPU 限制服务
start_cpu_limit_service() {
    echo -e "${GREEN}正在启动 CPU 限制服务...${RESET}"
    systemctl daemon-reload
    systemctl start cpu_limit.service
    systemctl enable cpu_limit.service
    echo -e "${GREEN}CPU 限制服务已启动！${RESET}"
}

# 停止 CPU 限制服务
stop_cpu_limit_service() {
    echo -e "${GREEN}正在停止 CPU 限制服务...${RESET}"
    systemctl stop cpu_limit.service
    echo -e "${GREEN}CPU 限制服务已停止！${RESET}"
}

# 卸载 CPU 限制服务
uninstall_cpu_limit_service() {
    echo -e "${GREEN}正在卸载 CPU 限制服务...${RESET}"
    stop_cpu_limit_service
    systemctl disable cpu_limit.service
    rm -f "$SERVICE_PATH"
    rm -f "$SCRIPT_PATH"
    systemctl daemon-reload
    echo -e "${GREEN}CPU 限制进程已卸载！${RESET}"
}

# 交互式主菜单
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}===== VPS CPU 限制管理器 =====${RESET}"
        echo "1. 安装并启动 CPU 限制"
        echo "2. 停止 CPU 限制"
        echo "3. 卸载 CPU 限制"
        echo "4. 退出"
        read -p "请选择操作 (1/2/3/4): " choice

        case "$choice" in
        1)
            install_cpulimit
            create_cpu_limit_script
            create_systemd_service
            start_cpu_limit_service
            ;;
        2)
            stop_cpu_limit_service
            ;;
        3)
            uninstall_cpu_limit_service
            ;;
        4)
            echo -e "${GREEN}退出程序。${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效输入，请输入 1-4 之间的数字！${RESET}"
            ;;
        esac
    done
}

# 运行主菜单
detect_os
main_menu
