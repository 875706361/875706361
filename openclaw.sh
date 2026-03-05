#!/bin/bash

# ==========================================
# OpenClaw 自动化部署与管理脚本 (分步逻辑版)
# ==========================================

# 颜色输出格式
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 恢复默认

# 必须以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 此脚本需要 root 权限，请使用 sudo su 切换为 root 后重新运行。${NC}"
    exit 1
fi

# 确保 NVM 在脚本环境中可用
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

# 1. 设置 Swap 交换空间 (物理内存的两倍) & 安装前置软件
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
    echo -e "${YELLOW}正在检测系统基础依赖 (curl)...${NC}"
    if command -v apt-get >/dev/null; then
        apt-get update -y && apt-get install -y curl
    elif command -v yum >/dev/null; then
        yum install -y curl
    elif command -v dnf >/dev/null; then
        dnf install -y curl
    else
        echo -e "${RED}未知的包管理器。请手动安装 curl。${NC}"
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

# 3. 运行向导并自动修复 Systemd
run_wizard_and_patch() {
    load_nvm
    if ! command -v openclaw >/dev/null; then
        echo -e "${RED}未检测到 OpenClaw，请先执行选项 2 进行安装！${NC}"
        return
    fi
    
    echo -e "${YELLOW}\n>>> 第一步: 启动 OpenClaw 向导及守护进程...${NC}"
    export NODE_OPTIONS="--max-old-space-size=4096"
    openclaw onboard --install-daemon
    
    echo -e "${YELLOW}\n>>> 第二步: 自动为 Systemd 注入内存补丁...${NC}"
    if ! systemctl list-units --all --type=service | grep -q "openclaw.service"; then
        echo -e "${RED}未检测到 openclaw.service。向导可能未能成功生成服务，跳过内存补丁修复。${NC}"
        return
    fi

    SERVICE_DIR="/etc/systemd/system/openclaw.service.d"
    mkdir -p "$SERVICE_DIR"

    cat <<EOF > "$SERVICE_DIR/override.conf"
[Service]
Environment="NODE_OPTIONS=--max-old-space-size=4096"
EOF

    systemctl daemon-reload
    systemctl restart openclaw.service
    
    echo -e "${GREEN}===================================================${NC}"
    echo -e "${GREEN}🎉 向导执行完毕，并且守护进程内存限制已成功修复！${NC}"
    echo -e "${GREEN}后台服务现在拥有 4GB 的专属内存上限，彻底告别内存溢出。${NC}"
    echo -e "${GREEN}===================================================${NC}"
}

# 4. 查看运行状态
check_status() {
    echo -e "${YELLOW}查询 OpenClaw 守护进程状态...${NC}"
    if systemctl list-units --type=service | grep -q "openclaw.service"; then
        systemctl status openclaw.service
    else
        echo -e "${RED}未发现 openclaw.service 运行。可能尚未完成向导配置。${NC}"
    fi
}

# 5. 卸载 OpenClaw
uninstall_openclaw() {
    echo -e "${YELLOW}正在卸载 OpenClaw 及服务...${NC}"
    if systemctl list-units --all --type=service | grep -q "openclaw.service"; then
        systemctl stop openclaw.service
        systemctl disable openclaw.service
        rm -f /etc/systemd/system/openclaw.service
        rm -rf /etc/systemd/system/openclaw.service.d 
        systemctl daemon-reload
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
    echo -e "${YELLOW}     🦞 OpenClaw 管理脚本 🦞      ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo "1. 配置 Swap 并安装前置软件 (NVM, Node 22)"
    echo "2. 安装 OpenClaw 最新版"
    echo "3. 运行 OpenClaw 初始向导 (含自动修复守护进程内存限制)"
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
