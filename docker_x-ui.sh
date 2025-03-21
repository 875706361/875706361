#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请以 root 权限运行此脚本！${NC}"
    echo -e "${YELLOW}使用: sudo bash $0${NC}"
    exit 1
fi

# 安装必要的软件
install_dependencies() {
    echo -e "${BLUE}正在安装必要依赖...${NC}"
    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy curl
    else
        echo -e "${RED}无法识别的包管理器，请手动安装 curl${NC}"
        exit 1
    fi
}

# 安装 Docker
install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${BLUE}正在安装 Docker...${NC}"
        curl -sSL https://get.docker.com/ | sh
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}Docker 安装完成！${NC}"
    else
        echo -e "${YELLOW}Docker 已安装，跳过...${NC}"
    fi
}

# 安装 x-ui
install_xui() {
    echo -e "${BLUE}正在安装 x-ui...${NC}"
    
    # 检查是否已存在 x-ui 容器
    if docker ps -a --filter "name=x-ui" | grep -q "x-ui"; then
        echo -e "${YELLOW}检测到已存在的 x-ui 容器，正在清理...${NC}"
        docker stop x-ui 2>/dev/null
        docker rm x-ui 2>/dev/null
    fi
    
    # 创建目录并安装
    mkdir -p x-ui && cd x-ui
    docker run -itd --network=host \
        -v $PWD/db/:/etc/x-ui/ \
        -v $PWD/cert/:/root/cert/ \
        --name x-ui --restart=unless-stopped \
        enwaiax/x-ui:alpha-zh
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}x-ui 安装成功！${NC}"
        show_info
    else
        echo -e "${RED}x-ui 安装失败！请检查网络或 Docker 服务${NC}"
        cd .. && rm -rf x-ui
    fi
    cd ..
}

# 显示安装信息
show_info() {
    echo -e "${GREEN}================ x-ui 信息 ================${NC}"
    echo -e "${YELLOW}容器名称:${NC} x-ui"
    echo -e "${YELLOW}数据目录:${NC} $(pwd)/x-ui/db/"
    echo -e "${YELLOW}证书目录:${NC} $(pwd)/x-ui/cert/"
    echo -e "${YELLOW}访问地址:${NC} http://<你的IP>:54321"
    echo -e "${GREEN}========================================${NC}"
}

# 查看运行状态
check_status() {
    echo -e "${BLUE}检查 x-ui 运行状态...${NC}"
    docker ps -a --filter "name=x-ui"
}

# 重启 x-ui
restart_xui() {
    echo -e "${BLUE}正在重启 x-ui...${NC}"
    docker restart x-ui
    echo -e "${GREEN}x-ui 已重启！${NC}"
}

# 删除 x-ui
remove_xui() {
    echo -e "${YELLOW}警告: 这将删除 x-ui 容器及其数据！${NC}"
    read -p "确认删除？(y/n): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        docker stop x-ui 2>/dev/null
        docker rm x-ui 2>/dev/null
        rm -rf x-ui
        echo -e "${GREEN}x-ui 已删除！${NC}"
    else
        echo -e "${YELLOW}取消删除操作${NC}"
    fi
}

# 进入容器
enter_xui() {
    echo -e "${BLUE}正在进入 x-ui 容器...${NC}"
    docker exec -it x-ui /bin/sh
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}======== x-ui 管理脚本 ========${NC}"
        echo "1) 安装 x-ui"
        echo "2) 查看运行状态"
        echo "3) 重启 x-ui"
        echo "4) 删除 x-ui"
        echo "5) 进入 x-ui 容器"
        echo "6) 退出"
        echo -e "${GREEN}==============================${NC}"
        read -p "请选择操作 (1-6): " choice
        
        case $choice in
            1)
                install_dependencies
                install_docker
                install_xui
                read -p "按 Enter 键继续..."
                ;;
            2)
                check_status
                read -p "按 Enter 键继续..."
                ;;
            3)
                restart_xui
                read -p "按 Enter 键继续..."
                ;;
            4)
                remove_xui
                read -p "按 Enter 键继续..."
                ;;
            5)
                enter_xui
                ;;
            6)
                echo -e "${GREEN}退出脚本${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择！${NC}"
                read -p "按 Enter 键继续..."
                ;;
        esac
    done
}

# 执行主菜单
main_menu