#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 定义版本和默认账号密码
HUI_VERSION="v0.0.11"
IMAGE_NAME="jonssonyan/h-ui:${HUI_VERSION}"
DEFAULT_USER="sysadmin"
DEFAULT_PASS="sysadmin"

# 检查 Docker 是否已安装
check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker 未安装，正在自动安装...${NC}"
        install_docker
    else
        echo -e "${GREEN}Docker 已安装${NC}"
    fi
}

# 安装 Docker
install_docker() {
    echo "检测系统类型并安装 Docker..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            ubuntu|debian)
                sudo apt-get update
                sudo apt-get install -y docker.io
                sudo systemctl start docker
                sudo systemctl enable docker
                ;;
            centos|rhel|fedora)
                sudo yum install -y docker
                sudo systemctl start docker
                sudo systemctl enable docker
                ;;
            arch)
                sudo pacman -Syu docker
                sudo systemctl start docker
                sudo systemctl enable docker
                ;;
            *)
                echo -e "${RED}不支持的 Linux 发行版，使用官方安装脚本安装 Docker${NC}"
                bash <(curl -fsSL https://get.docker.com)
                ;;
        esac
    else
        echo -e "${RED}无法检测系统类型，使用官方安装脚本安装 Docker${NC}"
        bash <(curl -fsSL https://get.docker.com)
    fi
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Docker 安装成功${NC}"
    else
        echo -e "${RED}Docker 安装失败，请手动安装${NC}"
        exit 1
    fi
}

# 官方脚本安装 h-ui 容器（选项 4）
install_hui_official() {
    echo -e "${BLUE}正在执行官方安装脚本并选择容器安装 (选项 4)...${NC}"
    echo "4" | bash <(curl -fsSL https://raw.githubusercontent.com/jonssonyan/h-ui/main/install.sh) "${HUI_VERSION}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}h-ui 官方容器安装成功${NC}"
        show_info_official
    else
        echo -e "${RED}h-ui 官方容器安装失败${NC}"
    fi
    read -p "按 Enter 返回菜单..."
}

# 重启 h-ui 容器
restart_hui() {
    echo -e "${BLUE}正在重启 h-ui 容器...${NC}"
    docker restart h-ui
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}h-ui 重启成功${NC}"
    else
        echo -e "${RED}h-ui 重启失败，可能是容器未运行${NC}"
    fi
    read -p "按 Enter 返回菜单..."
}

# 删除 h-ui 容器
remove_hui() {
    echo -e "${BLUE}正在删除 h-ui 容器和相关数据...${NC}"
    docker rm -f h-ui
    docker rmi "${IMAGE_NAME}"
    rm -rf /h-ui
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}h-ui 删除成功${NC}"
    else
        echo -e "${RED}h-ui 删除失败${NC}"
    fi
    read -p "按 Enter 返回菜单..."
}

# 进入 h-ui 容器
enter_hui() {
    echo -e "${BLUE}正在进入 h-ui 容器...${NC}"
    docker exec -it h-ui /bin/sh
}

# 显示官方安装信息
show_info_official() {
    echo -e "${YELLOW}===== h-ui 官方安装信息 ====="
    echo -e "${BLUE}镜像版本:${NC} ${IMAGE_NAME}"
    echo -e "${BLUE}容器名称:${NC} h-ui"
    echo -e "${BLUE}Web 端口:${NC} $(docker inspect h-ui 2>/dev/null | grep -i '"-p"' | awk '{print $2}' | cut -d' ' -f2 || echo '8081 (默认)')"
    echo -e "${BLUE}时区:${NC} $(docker inspect h-ui 2>/dev/null | grep -i 'TZ=' | cut -d'=' -f2 | tr -d '"' || echo 'Asia/Shanghai (默认)')"
    echo -e "${BLUE}数据目录:${NC} /h-ui"
    echo -e "${BLUE}默认账号:${NC} ${DEFAULT_USER}"
    echo -e "${BLUE}默认密码:${NC} ${DEFAULT_PASS}"
    echo -e "${BLUE}访问地址:${NC} http://your_server_ip:$(docker inspect h-ui 2>/dev/null | grep -i '"-p"' | awk '{print $2}' | cut -d' ' -f2 || echo '8081')"
    echo -e "${YELLOW}=========================${NC}"
    read -p "按 Enter 返回菜单..."
}

# 主菜单
main_menu() {
    while true; do
        echo -e "${YELLOW}===== h-ui 管理脚本 ====="
        echo -e "${GREEN}1. 安装 h-ui (官方脚本选项 4)${NC}"
        echo -e "${GREEN}2. 重启 h-ui${NC}"
        echo -e "${GREEN}3. 删除 h-ui${NC}"
        echo -e "${GREEN}4. 进入 h-ui 容器${NC}"
        echo -e "${GREEN}5. 显示安装信息${NC}"
        echo -e "${GREEN}6. 退出${NC}"
        echo -e "${YELLOW}=========================${NC}"
        echo
        read -p "请选择操作 (1-6): " choice
        
        case $choice in
            1)
                check_docker_installed
                install_hui_official
                ;;
            2)
                restart_hui
                ;;
            3)
                remove_hui
                ;;
            4)
                enter_hui
                ;;
            5)
                show_info_official
                ;;
            6)
                echo -e "${GREEN}退出脚本${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请输入 1-6${NC}"
                read -p "按 Enter 返回菜单..."
                ;;
        esac
    done
}

# 执行主菜单
main_menu