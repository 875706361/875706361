#!/bin/bash

# 颜色定义
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# 默认配置
CONTAINER_NAME="h-ui"
IMAGE_NAME="jonssonyan/h-ui:v0.0.11"
HUI_DIR="/h-ui"
DEFAULT_WEB_PORT=8081

# 分隔线
separator() {
    echo -e "${YELLOW}---------------------------------${RESET}"
}

# 安装 Docker（官方推荐方式）
install_docker() {
    separator
    echo -e "${GREEN}正在检测并安装 Docker...${RESET}"
    
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker 已安装，无需重复安装。${RESET}"
        return
    fi

    bash <(curl -fsSL https://get.docker.com)

    sudo systemctl enable docker
    sudo systemctl start docker

    echo -e "${GREEN}Docker 安装完成！${RESET}"
}

# 重置 H-UI 账号密码
reset_h_ui_credentials() {
    separator
    echo -e "${YELLOW}正在重置 H-UI 账号密码...${RESET}"

    docker exec -it $CONTAINER_NAME ./h-ui reset

    sleep 3
}

# 在容器内重启 H-UI
restart_h_ui_in_container() {
    separator
    echo -e "${YELLOW}正在容器内重启 H-UI...${RESET}"

    docker exec -it $CONTAINER_NAME ./h-ui restart

    sleep 3
}

# 安装 H-UI
install_h_ui() {
    install_docker

    read -p "是否拉取 H-UI v0.0.11 Docker 镜像？(y/n): " pull_choice
    if [[ "$pull_choice" == "y" || "$pull_choice" == "Y" ]]; then
        echo -e "${YELLOW}拉取 H-UI v0.0.11 镜像中...${RESET}"
        docker pull $IMAGE_NAME
    fi

    mkdir -p $HUI_DIR/{bin,data,export,logs}

    read -p "请输入 H-UI Web 端口 (默认: $DEFAULT_WEB_PORT): " web_port
    web_port=${web_port:-$DEFAULT_WEB_PORT}

    echo -e "${YELLOW}默认时区为 Asia/Shanghai...${RESET}"

    echo -e "${YELLOW}启动 H-UI 容器中...${RESET}"
    docker run -d --cap-add=NET_ADMIN \
      --name $CONTAINER_NAME --restart always \
      --network=host \
      -e TZ=Asia/Shanghai \
      -v $HUI_DIR/bin:/h-ui/bin \
      -v $HUI_DIR/data:/h-ui/data \
      -v $HUI_DIR/export:/h-ui/export \
      -v $HUI_DIR/logs:/h-ui/logs \
      $IMAGE_NAME ./h-ui -p $web_port

    sleep 5
    reset_h_ui_credentials  # 自动重置账号密码

    if [[ $(docker ps -q -f name=$CONTAINER_NAME) ]]; then
        echo -e "${GREEN}H-UI 已成功安装并运行！${RESET}"
        echo -e "Web 访问地址: ${GREEN}http://localhost:$web_port${RESET}"
        echo -e "${YELLOW}H-UI 配置文件路径（宿主机）:${RESET}"
        echo -e "${GREEN}$HUI_DIR/data/config.yaml${RESET}"
    else
        echo -e "${RED}H-UI 安装失败，请检查 Docker 日志。${RESET}"
        docker logs $CONTAINER_NAME
    fi
}

# 查看容器状态
status_h_ui() {
    install_docker
    local status=$(docker ps -a --filter "name=$CONTAINER_NAME" --format "{{.State}}")
    echo -e "H-UI 容器状态: ${GREEN}${status:-not installed}${RESET}"
}

# 停止容器
stop_h_ui() {
    install_docker
    echo -e "${YELLOW}正在停止 H-UI 容器...${RESET}"
    docker stop $CONTAINER_NAME
    echo -e "${GREEN}H-UI 容器已停止。${RESET}"
}

# 重启容器
restart_h_ui() {
    install_docker
    echo -e "${YELLOW}正在重启 H-UI 容器...${RESET}"
    docker restart $CONTAINER_NAME
    echo -e "${GREEN}H-UI 容器已重启。${RESET}"
}

# 删除容器并清理数据
remove_h_ui() {
    install_docker
    echo -e "${YELLOW}正在删除 H-UI 容器和数据...${RESET}"
    docker stop $CONTAINER_NAME &>/dev/null
    docker rm $CONTAINER_NAME &>/dev/null
    docker rmi $IMAGE_NAME &>/dev/null
    rm -rf $HUI_DIR
    echo -e "${GREEN}H-UI 容器及数据已清理。${RESET}"
}

# 进入容器命令
enter_container() {
    separator
    echo -e "${GREEN}正在进入 H-UI 容器...${RESET}"
    docker exec -it $CONTAINER_NAME /bin/bash
}

# 主菜单
main_menu() {
    while true; do
        separator
        echo -e "${GREEN}H-UI Docker 管理脚本${RESET}"
        separator
        echo -e "1. 安装/重新安装 H-UI"
        echo -e "2. 重置 H-UI 账号密码"
        echo -e "3. 在容器内重启 H-UI"
        echo -e "4. 查看容器状态"
        echo -e "5. 停止 H-UI 容器"
        echo -e "6. 重启 H-UI 容器"
        echo -e "7. 删除 H-UI 容器及数据"
        echo -e "8. 进入 H-UI 容器"
        echo -e "9. 退出"
        separator
        read -p "请选择操作 (1-9): " choice
        case $choice in
           
::contentReference[oaicite:10]{index=10}
