#!/bin/bash

# ==========================================
# OpenClaw 自动化部署与管理脚本 (Root 专属修复版)
# ==========================================

# 颜色输出格式
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 恢复默认

# 强制检查：必须以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 此脚本专为 root 用户设计，请切换到 root 后重试。${NC}"
    exit 1
fi

# 确保 NVM 在脚本环境中可用
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

# 核心修复：强制启动 Root 的用户级 Systemd 实例
setup_root_systemd() {
    # 强制允许 root 驻留后台 (即使断开 SSH 也不杀进程)
    loginctl enable-linger root
    
    # 手动创建并授权 root 的运行时目录
    export XDG_RUNTIME_DIR=/run/user/0
    mkdir -p $XDG_RUNTIME_DIR
    chmod 700 $XDG_RUNTIME_DIR
    
    # 强制启动 root 的 user-level systemd 服务
    systemctl start user@0.service
    
    # 设置 D-Bus 环境变量，让 systemctl --user 能找到正确的通信套接字
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
}

# 1. 设置 Swap 交换空间 (物理内存的两倍)
setup_swap() {
    echo -e "${YELLOW}正在检查系统 Swap 空间...${NC}"
    current_swap=$(free -m | awk '/^Swap:/ {print $2}')
    
    if [ "$current_swap" -gt 0 ]; then
        echo -e "${GREEN}系统已配置 Swap 空间 (${current_swap} MB)，跳过 Swap 创建。${NC}"
    else
        mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        mem_total_mb=$((mem_total_kb / 1024))
        swap_size_mb=$((mem_total_mb * 2))
        
        echo -e "${YELLOW}未检测到 Swap。正在为您创建 ${swap_size_mb} MB 的 Swap 空间...${NC}"
        fallocate -l ${swap_size_mb}M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=${swap_size_mb} status=progress
        
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
        echo -e "${GREEN}Swap 空间配置成功！${NC}"
    fi
}

# 安装前置软件
install_prereqs() {
    echo -e "${YELLOW}正在检测系统基础依赖 (curl, systemd, dbus)...${NC}"
    if command -v apt-get >/dev/null; then
        apt-get update -y && apt-get DEBIAN_FRONTEND=noninteractive install -y curl systemd dbus-user-session
    elif command -v yum >/dev/null; then
        yum install -y curl systemd dbus
    elif command -v dnf >/dev/null; then
        dnf install -y curl systemd dbus
    else
        echo -e "${RED}未知的包管理器。请手动安装 curl 和 systemd。${NC}"
    fi

    echo -e "${YELLOW}正在安装 NVM...${NC}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    load_nvm
    
    echo -e "${YELLOW}正在安装 Node.js 22...${NC}"
    nvm install 22
    nvm alias default 22
    echo -e "${GREEN}前置软件安装完毕！当前 Node 版本：$(node -v)${NC}"
}

# 2. 安装 OpenClaw 最新版
install_openclaw() {
    load_nvm
    if ! command -v npm >/dev/null; then
        echo -e "${RED}未检测到 npm，请先执行选项 1 安装前置软件！${NC}"
        return
    fi
    echo -e "${YELLOW}正在全局安装 OpenClaw 最新版...${NC}"
    npm install -g openclaw@latest
    echo -e "${GREEN}OpenClaw 安装完成！可以继续执行选项 3 运行向导。${NC}"
}

# 3. 运行向导并自动修复 Systemd (User-level)
run_wizard_and_patch() {
    load_nvm
    if ! command -v openclaw >/dev/null; then
        echo -e "${RED}未检测到 OpenClaw，请先执行选项 2 进行安装！${NC}"
        return
    fi
    
    echo -e "${YELLOW}\n>>> 准备环境: 强行唤醒 Root 的 systemctl --user 环境...${NC}"
    setup_root_systemd
    
    echo -e "${YELLOW}\n>>> 第一步: 启动 OpenClaw 向导及守护进程...${NC}"
    export NODE_OPTIONS="--max-old-space-size=4096"
    openclaw onboard --install-daemon
    
    echo -e "${YELLOW}\n>>> 第二步: 自动为 Systemd (Root用户级) 注入内存补丁...${NC}"
    # 检查服务名
    SERVICE_NAME=$(systemctl --user list-units --all --type=service | grep -o 'openclaw.*\.service' | head -n 1)
    
    if [ -z "$SERVICE_NAME" ]; then
        SERVICE_NAME="openclaw-gateway.service"
    fi

    # Root 用户的配置目录在 ~/.config/systemd/user/ (即 /root/.config/systemd/user/)
    SERVICE_DIR="$HOME/.config/systemd/user/${SERVICE_NAME}.d"
    mkdir -p "$SERVICE_DIR"

    cat <<EOF > "$SERVICE_DIR/override.conf"
[Service]
Environment="NODE_OPTIONS=--max-old-space-size=4096"
EOF

    systemctl --user daemon-reload
    systemctl --user restart "$SERVICE_NAME" 2>/dev/null || echo -e "${YELLOW}服务启动中，请稍后通过选项 4 检查状态。${NC}"
    
    echo -e "${GREEN}===================================================${NC}"
    echo -e "${GREEN}🎉 向导执行完毕！Root 下的守护进程已配置完毕。${NC}"
    echo -e "${GREEN}后台服务 ($SERVICE_NAME) 现在拥有 4GB 的专属内存上限。${NC}"
    echo -e "${GREEN}===================================================${NC}"
}

# 4. 查看运行状态
check_status() {
    setup_root_systemd
    echo -e "${YELLOW}查询 OpenClaw 守护进程状态...${NC}"
    
    SERVICE_NAME=$(systemctl --user list-units --all --type=service | grep -o 'openclaw.*\.service' | head -n 1)
    if [ -z "$SERVICE_NAME" ]; then
        SERVICE_NAME="openclaw-gateway.service"
    fi

    if systemctl --user list-units --all --type=service | grep -q "$SERVICE_NAME"; then
        systemctl --user status "$SERVICE_NAME"
    else
        echo -e "${RED}未发现 $SERVICE_NAME 运行。可能尚未完成向导配置。${NC}"
    fi
}

# 5. 卸载 OpenClaw
uninstall_openclaw() {
    setup_root_systemd
    echo -e "${YELLOW}正在卸载 OpenClaw 及服务...${NC}"
    
    SERVICE_NAME=$(systemctl --user list-units --all --type=service | grep -o 'openclaw.*\.service' | head -n 1)
    if [ -z "$SERVICE_NAME" ]; then
        SERVICE_NAME="openclaw-gateway.service"
    fi

    if systemctl --user list-units --all --type=service | grep -q "$SERVICE_NAME"; then
        systemctl --user stop "$SERVICE_NAME"
        systemctl --user disable "$SERVICE_NAME"
        rm -f "$HOME/.config/systemd/user/$SERVICE_NAME"
        rm -rf "$HOME/.config/systemd/user/${SERVICE_NAME}.d" 
        systemctl --user daemon-reload
    fi
    
    load_nvm
    if command -v npm >/dev/null; then
        npm uninstall -g openclaw
    fi
    echo -e "${GREEN}OpenClaw 已完全卸载。${NC}"
}

# ==========================================
# 交互式菜单主循环
# ==========================================
while true; do
    echo -e "\n${GREEN}=====================================${NC}"
    echo -e "${YELLOW}   🦞 OpenClaw Root 专属管理脚本 🦞   ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo "1. 配置 Swap 并安装前置软件 (NVM, Node 22)"
    echo "2. 安装 OpenClaw 最新版"
    echo "3. 运行 OpenClaw 初始向导 (含 Root 守护进程修复)"
    echo "4. 查看 OpenClaw 运行状态"
    echo "5. 彻底卸载 OpenClaw"
    echo "0. 退出脚本"
    echo -e "${GREEN}=====================================${NC}"
    read -p "请输入选项序号 [0-5]: " choice

    case $choice in
        1) setup_swap; install_prereqs ;;
        2) install_openclaw ;;
        3) run_wizard_and_patch ;;
        4) check_status ;;
        5) read -p "确定要彻底卸载 OpenClaw 吗？(y/n): " confirm
           if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
               uninstall_openclaw
           fi
           ;;
        0) echo -e "${GREEN}感谢使用，再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效输入，请输入 0 到 5 之间的数字。${NC}" ;;
    esac
done
