#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：请以 root 权限运行此脚本！${NC}"
        echo "请使用 'sudo -i' 或 'sudo bash $0' 运行"
        exit 1
    fi
}

# 检查系统环境
check_system() {
    echo -e "${BLUE}正在检查系统环境...${NC}"
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}正在安装 curl...${NC}"
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y curl
        elif [ -f /etc/redhat-release ]; then
            yum install -y curl
        elif [ -f /etc/arch-release ]; then
            pacman -Syu --noconfirm curl
        else
            echo -e "${RED}不支持的 Linux 发行版！${NC}"
            exit 1
        fi
    fi
}

# 安装 Docker
install_docker() {
    echo -e "${BLUE}正在安装 Docker...${NC}"
    if ! command -v docker >/dev/null 2>&1; then
        curl -sSL https://get.docker.com/ | sh
        if [ $? -ne 0 ]; then
            echo -e "${RED}Docker 安装失败！${NC}"
            exit 1
        fi
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}Docker 安装成功！${NC}"
    else
        echo -e "${YELLOW}Docker 已安装，跳过...${NC}"
    fi

    # 安装 docker-compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        echo -e "${BLUE}正在安装 docker-compose...${NC}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}docker-compose 安装成功！${NC}"
    else
        echo -e "${YELLOW}docker-compose 已安装，跳过...${NC}"
    fi
}

# 安装 x-ui
install_xui() {
    echo -e "${BLUE}正在安装 x-ui...${NC}"
    mkdir -p x-ui && cd x-ui
    if [ ! -f "docker-compose.yml" ]; then
        wget https://raw.githubusercontent.com/chasing66/x-ui/main/docker-compose.yml
        if [ $? -ne 0 ]; then
            echo -e "${RED}下载 docker-compose.yml 失败！${NC}"
            exit 1
        fi
    fi
    docker-compose up -d
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}x-ui 安装成功！${NC}"
        show_info
    else
        echo -e "${RED}x-ui 安装失败！${NC}"
        exit 1
    fi
    cd ..
}

# 查看运行状态
check_status() {
    echo -e "${BLUE}正在检查 x-ui 运行状态...${NC}"
    cd x-ui || {
        echo -e "${RED}错误：x-ui 目录不存在！${NC}"
        exit 1
    }
    docker-compose ps
    cd ..
}

# 重启 x-ui
restart_xui() {
    echo -e "${BLUE}正在重启 x-ui...${NC}"
    cd x-ui || {
        echo -e "${RED}错误：x-ui 目录不存在！${NC}"
        exit 1
    }
    docker-compose restart
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}x-ui 重启成功！${NC}"
    else
        echo -e "${RED}x-ui 重启失败！${NC}"
    fi
    cd ..
}

# 删除 x-ui
remove_xui() {
    echo -e "${YELLOW}警告：此操作将删除 x-ui 容器及其数据！${NC}"
    read -p "确认删除？(y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo -e "${BLUE}正在删除 x-ui...${NC}"
        cd x-ui || {
            echo -e "${RED}错误：x-ui 目录不存在！${NC}"
            exit 1
        }
        docker-compose down
        cd ..
        rm -rf x-ui
        echo -e "${GREEN}x-ui 删除成功！${NC}"
    else
        echo -e "${YELLOW}操作已取消${NC}"
    fi
}

# 显示安装信息
show_info() {
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}       x-ui 安装信息${NC}"
    echo -e "${GREEN}====================================${NC}"
    echo -e "安装路径: $(pwd)/x-ui"
    echo -e "数据库路径: $(pwd)/x-ui/db"
    echo -e "证书路径: $(pwd)/x-ui/cert"
    echo -e "运行状态: ${GREEN}运行中${NC}"
    echo -e "访问地址: http://<你的服务器IP>:54321"
    echo -e "${GREEN}====================================${NC}"
}

# 主菜单
show_menu() {
    clear
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}       x-ui 管理脚本${NC}"
    echo -e "${GREEN}====================================${NC}"
    echo -e "1. 安装 x-ui"
    echo -e "2. 查看运行状态"
    echo -e "3. 重启 x-ui"
    echo -e "4. 删除 x-ui"
    echo -e "5. 退出"
    echo -e "${GREEN}====================================${NC}"
    read -p "请选择操作 [1-5]: " choice
}

# 主程序
main() {
    check_root
    check_system

    while true; do
        show_menu
        case $choice in
            1)
                install_docker
                install_xui
                read -p "按回车键返回菜单..."
                ;;
            2)
                check_status
                read -p "按回车键返回菜单..."
                ;;
            3)
                restart_xui
                read -p "按回车键返回菜单..."
                ;;
            4)
                remove_xui
                read -p "按回车键返回菜单..."
                ;;
            5)
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请输入 1-5！${NC}"
                read -p "按回车键返回菜单..."
                ;;
        esac
    done
}

# 启动脚本
main
