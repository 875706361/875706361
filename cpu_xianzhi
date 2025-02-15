#!/bin/bash

# 颜色定义
GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

# 日志文件
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

# 限制高 CPU 占用进程
limit_high_cpu_processes() {
    echo -e "${GREEN}启动 CPU 限制进程...${RESET}"
    echo "$(date) - CPU 限制进程已启动" >> "$LOG_FILE"

    while true; do
        # 查找 CPU 使用率超过 90% 的进程
        high_cpu_process=$(ps -eo pid,%cpu,comm --sort=-%cpu | awk '$2>90 {print $1}' | head -n 1)

        if [ -n "$high_cpu_process" ]; then
            echo -e "${GREEN}发现 CPU 超 90% 进程 (PID: $high_cpu_process)，限制其使用率...${RESET}"
            echo "$(date) - 限制进程 $high_cpu_process CPU 占用" >> "$LOG_FILE"
            cpulimit -p "$high_cpu_process" -l 90 -b
        fi

        sleep 5  # 每 5 秒检查一次
    done
}

# 停止 CPU 限制
stop_cpu_limit() {
    echo -e "${GREEN}正在停止 CPU 限制进程...${RESET}"
    pkill -f "cpulimit"
    echo "$(date) - CPU 限制进程已停止" >> "$LOG_FILE"
    echo -e "${GREEN}CPU 限制已停止！${RESET}"
}

# 卸载 cpulimit
uninstall_cpulimit() {
    echo -e "${GREEN}正在卸载 cpulimit...${RESET}"
    
    stop_cpu_limit  # 先停止正在运行的限制进程

    case "$OS" in
    ubuntu | debian)
        apt remove -y cpulimit
        ;;
    almalinux | centos | rocky)
        yum remove -y cpulimit
        ;;
    *)
        echo -e "${RED}不支持的系统类型：$OS${RESET}"
        exit 1
        ;;
    esac

    echo -e "${GREEN}cpulimit 卸载完成！${RESET}"
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}===== VPS CPU 限制管理器 =====${RESET}"
        echo "1. 安装并运行 CPU 限制"
        echo "2. 停止 CPU 限制"
        echo "3. 卸载 CPU 限制工具"
        echo "4. 退出"
        read -p "请选择操作 (1/2/3/4): " choice

        case "$choice" in
        1)
            install_cpulimit
            limit_high_cpu_processes
            ;;
        2)
            stop_cpu_limit
            ;;
        3)
            uninstall_cpulimit
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
