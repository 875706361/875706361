#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无色

CONTAINER_NAME="x-ui"
DB_DIR="/etc/x-ui"
CERT_DIR="$PWD/cert"
BACKUP_URL="https://github.com/875706361/x-ui_FranzKafkaYu/releases/download/0.3.4.4/docker_x-ui.tar"
BACKUP_FILE="/root/docker_x-ui.tar"

# 检测 Linux 发行版
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="centos"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
    else
        OS="unknown"
    fi
}

# 安装 Docker（支持所有 Linux 发行版）
install_docker() {
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker 已安装，跳过安装步骤。${NC}"
        return
    fi

    echo -e "${YELLOW}未检测到 Docker，正在安装...${NC}"
    detect_os

    case $OS in
        ubuntu|debian)
            apt update && apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://get.docker.com | bash
            systemctl enable docker --now
            ;;
        centos|rhel)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            systemctl enable docker --now
            ;;
        arch)
            pacman -Syu --noconfirm docker
            systemctl enable docker --now
            ;;
        alpine)
            apk add --no-cache docker
            rc-update add docker default
            service docker start
            ;;
        *)
            echo -e "${RED}不支持的 Linux 发行版，请手动安装 Docker！${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}Docker 安装完成！${NC}"
}

# 安装必要工具
install_required_software() {
    echo -e "${YELLOW}正在安装必要的软件 (curl, wget, unzip)...${NC}"
    detect_os

    case $OS in
        ubuntu|debian)
            apt update && apt install -y curl wget unzip
            ;;
        centos|rhel)
            yum install -y curl wget unzip
            ;;
        arch)
            pacman -Syu --noconfirm curl wget unzip
            ;;
        alpine)
            apk add --no-cache curl wget unzip
            ;;
    esac

    echo -e "${GREEN}必要软件安装完成！${NC}"
}

# 下载 x-ui 备份并恢复容器
install_xui() {
    install_required_software
    install_docker

    echo -e "${BLUE}正在下载 x-ui 备份文件...${NC}"
    wget -O $BACKUP_FILE $BACKUP_URL

    echo -e "${BLUE}正在加载 Docker 镜像...${NC}"
    docker load < $BACKUP_FILE

    echo -e "${BLUE}正在创建 x-ui 容器...${NC}"
    mkdir -p $DB_DIR
    chmod 777 $DB_DIR  # 赋予所有用户读写权限

    docker run -d --name $CONTAINER_NAME \
        --volume $DB_DIR:/etc/x-ui \
        --volume $CERT_DIR:/root/cert/ \
        --restart unless-stopped \
        --network host \
        x-ui:latest

    echo -e "${GREEN}x-ui 容器安装完成！${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}🎉 x-ui 已成功安装！${NC}"
    echo -e "${YELLOW}🔹 容器名称: ${NC}${CONTAINER_NAME}"
    echo -e "${YELLOW}🔹 数据库路径: ${NC}${DB_DIR}/x-ui.db"
    echo -e "${YELLOW}🔹 访问方式: ${NC}http://<你的服务器IP>:54321"
    echo -e "${YELLOW}🔹 查看运行状态: ${NC}docker ps | grep x-ui"
    echo -e "${YELLOW}🔹 进入容器: ${NC}docker exec -it ${CONTAINER_NAME} /bin/sh"
    echo -e "${BLUE}========================================${NC}"
}

# 删除 x-ui 容器
remove_xui() {
    echo -e "${RED}正在删除 x-ui 容器...${NC}"
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
    echo -e "${GREEN}x-ui 容器已删除！${NC}"
}

# 重启 x-ui 容器
restart_xui_container() {
    echo -e "${BLUE}正在重启 x-ui 容器...${NC}"
    docker restart $CONTAINER_NAME
    echo -e "${GREEN}x-ui 容器已重启！${NC}"
}

# 进入 x-ui 容器
enter_xui_container() {
    echo -e "${YELLOW}进入 x-ui 容器...${NC}"
    docker exec -it $CONTAINER_NAME /bin/sh
}

# 在容器中重启 x-ui 服务
restart_xui_inside_container() {
    echo -e "${BLUE}在容器中重启 x-ui 服务...${NC}"
    docker exec $CONTAINER_NAME x-ui restart
    echo -e "${GREEN}x-ui 服务已在容器内重启！${NC}"
}

# 交互式菜单
while true; do
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}🚀 x-ui 容器管理脚本${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}1) 安装 x-ui 容器（基于备份恢复）${NC}"
    echo -e "${RED}2) 删除 x-ui 容器${NC}"
    echo -e "${BLUE}3) 重启 x-ui 容器${NC}"
    echo -e "${YELLOW}4) 进入 x-ui 容器${NC}"
    echo -e "${BLUE}5) 在容器中重启 x-ui 服务${NC}"
    echo -e "${RED}6) 退出${NC}"
    echo -e "${BLUE}========================================${NC}"
    read -p "请输入选项 (1-6): " choice

    case $choice in
        1) install_xui ;;
        2) remove_xui ;;
        3) restart_xui_container ;;
        4) enter_xui_container ;;
        5) restart_xui_inside_container ;;
        6) echo -e "${GREEN}退出脚本。${NC}"; exit 0 ;;
        *) echo -e "${RED}无效输入，请重新选择。${NC}" ;;
    esac
done
