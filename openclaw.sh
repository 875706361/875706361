#!/bin/bash

# ==========================================
# OpenClaw 自动化部署与管理脚本 (手动接管 Systemd 版)
# ==========================================

# 颜色输出格式
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 此脚本专为 root 用户设计，请切换到 root 后重试。${NC}"
    exit 1
fi

load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

# 1. 设置 Swap
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

install_prereqs() {
    echo -e "${YELLOW}正在检测系统基础依赖...${NC}"
    if command -v apt-get >/dev/null; then
        apt-get update -y && apt-get DEBIAN_FRONTEND=noninteractive install -y curl systemd
    elif command -v yum >/dev/null; then
        yum install -y curl systemd
    elif command -v dnf >/dev/null; then
        dnf install -y curl systemd
    fi

    echo -e "${YELLOW}正在安装 NVM...${NC}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    load_nvm
    
    echo -e "${YELLOW}正在安装 Node.js 22...${NC}"
    nvm install 22
    nvm alias default 22
}

# 2. 安装 OpenClaw
install_openclaw() {
    load_nvm
    if ! command -v npm >/dev/null; then
        echo -e "${RED}未检测到 npm，请先执行选项 1 安装前置软件！${NC}"
        return
    fi
    echo -e "${YELLOW}正在全局安装 OpenClaw 最新版...${NC}"
    npm install -g openclaw@latest
    echo -e "${GREEN}OpenClaw 安装完成！${NC}"
}

# 3. 运行向导并由 Bash 手动创建守护进程 (抛弃官方故障参数)
run_wizard_and_patch() {
    load_nvm
    if ! command -v openclaw >/dev/null; then
        echo -e "${RED}未检测到 OpenClaw，请先执行选项 2 进行安装！${NC}"
        return
    fi
    
    echo -e "${YELLOW}\n>>> 第一步: 启动 OpenClaw 向导... (已去掉会导致报错的 --install-daemon)${NC}"
    export NODE_OPTIONS="--max-old-space-size=4096"
    # 我们只让它做配置，不再让它去碰 Systemd
    openclaw onboard
    
    echo -e "${YELLOW}\n>>> 第二步: 手动创建稳定版全局 Systemd 守护进程...${NC}"
    
    SERVICE_NAME="openclaw-gateway.service"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
    
    # 写入全局服务文件，利用 Bash -lc 确保能加载 NVM 的环境变量
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=OpenClaw Gateway Global Service
After=network.target

[Service]
Type=simple
User=root
Environment="NODE_OPTIONS=--max-old-space-size=4096"
# 使用 bash -lc 启动，确保 NVM 环境生效。如果需要特殊启动命令(如 openclaw start)，请修改末尾
ExecStart=/bin/bash -lc "openclaw"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
    
    echo -e "${GREEN}===================================================${NC}"
    echo -e "${GREEN}🎉 恭喜！已成功绕过 OpenClaw 自带的报错逻辑！${NC}"
    echo -e "${GREEN}现在它由系统的全局 Systemd 完全接管，拥有 4GB 内存上限。${NC}"
    echo -e "${GREEN}===================================================${NC}"
}

# 4. 查看运行状态
check_status() {
    echo -e "${YELLOW}查询 OpenClaw 全局守护进程状态...${NC}"
    SERVICE_NAME="openclaw-gateway.service"
    if systemctl list-units --all --type=service | grep -q "$SERVICE_NAME"; then
        systemctl status "$SERVICE_NAME"
    else
        echo -e "${RED}未发现 $SERVICE_NAME 运行。${NC}"
    fi
}

# 5. 卸载 OpenClaw
uninstall_openclaw() {
    echo -e "${YELLOW}正在卸载 OpenClaw 及服务...${NC}"
    SERVICE_NAME="openclaw-gateway.service"
    if systemctl list-units --all --type=service | grep -q "$SERVICE_NAME"; then
        systemctl stop "$SERVICE_NAME"
        systemctl disable "$SERVICE_NAME"
        rm -f "/etc/systemd/system/$SERVICE_NAME"
        systemctl daemon-reload
    fi
    
    load_nvm
    if command -v npm >/dev/null; then
        npm uninstall -g openclaw
    fi
    echo -e "${GREEN}OpenClaw 已完全卸载。${NC}"
}

while true; do
    echo -e "\n${GREEN}=====================================${NC}"
    echo -e "${YELLOW} 🦞 OpenClaw 管理脚本 (手动接管守护版) 🦞 ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo "1. 配置 Swap 并安装前置软件 (NVM, Node 22)"
    echo "2. 安装 OpenClaw 最新版"
    echo "3. 运行 OpenClaw 向导 (修复所有报错并注入内存补丁)"
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
        *) echo -e "${RED}无效输入，请输入 0 到
