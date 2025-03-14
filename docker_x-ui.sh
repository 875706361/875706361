#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无色

CONTAINER_NAME="xui"
IMAGE_NAME="enwaiax/x-ui"
DB_DIR="$PWD/db"
CERT_DIR="$PWD/cert"

# 检查并安装 Docker
function install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker，正在安装...${NC}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}Docker 安装完成！${NC}"
    else
        echo -e "${GREEN}Docker 已安装，跳过安装步骤。${NC}"
    fi
}

# 检查并安装 Docker Compose
function install_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}未检测到 Docker Compose，正在安装...${NC}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
        echo -e "${GREEN}Docker Compose 安装完成！${NC}"
    else
        echo -e "${GREEN}Docker Compose 已安装，跳过安装步骤。${NC}"
    fi
}

# 安装必要软件
function install_required_software() {
    echo -e "${YELLOW}正在安装必要的软件 (curl, wget, unzip)...${NC}"
    apt update && apt install -y curl wget unzip
    echo -e "${GREEN}必要软件安装完成！${NC}"
}

# 安装容器版 x-ui
function install_xui() {
    install_required_software
    install_docker
    install_docker_compose
    echo -e "${BLUE}正在安装容器版 x-ui...${NC}"
    mkdir -p "$DB_DIR" "$CERT_DIR"
    docker run -d --name $CONTAINER_NAME \
        --volume $DB_DIR:/etc/x-ui/ \
        --volume $CERT_DIR:/root/cert/ \
        --restart unless-stopped \
        --network host \
        $IMAGE_NAME
    echo -e "${GREEN}容器版 x-ui 安装完成！${NC}"
    
    # 输出安装完成信息
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}🎉 x-ui 已成功安装！${NC}"
    echo -e "${YELLOW}🔹 容器名称: ${NC}${CONTAINER_NAME}"
    echo -e "${YELLOW}🔹 访问方式: ${NC}http://<你的服务器IP>:54321"
    echo -e "${YELLOW}🔹 查看运行状态: ${NC}docker ps | grep x-ui"
    echo -e "${YELLOW}🔹 进入容器: ${NC}docker exec -it ${CONTAINER_NAME} /bin/sh"
    echo -e "${BLUE}========================================${NC}"
}

# 删除 x-ui 容器
function remove_xui() {
    echo -e "${RED}正在删除 x-ui 容器...${NC}"
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
    echo -e "${GREEN}x-ui 容器已删除！${NC}"
}

# 重启 x-ui 容器
function restart_xui_container() {
    echo -e "${BLUE}正在重启 x-ui 容器...${NC}"
    docker restart $CONTAINER_NAME
    echo -e "${GREEN}x-ui 容器已重启！${NC}"
}

# 进入 x-ui 容器
function enter_xui_container() {
    echo -e "${YELLOW}进入 x-ui 容器...${NC}"
    docker exec -it $CONTAINER_NAME /bin/sh
}

# 在容器中重启 x-ui 服务
function restart_xui_inside_container() {
    echo -e "${BLUE}在容器中重启 x-ui 服务...${NC}"
    docker exec $CONTAINER_NAME x-ui restart
    echo -e "${GREEN}x-ui 服务已在容器内重启！${NC}"
}

# 显示菜单
while true; do
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}🚀 x-ui 容器管理脚本${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}1) 安装容器版 x-ui${NC}"
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
