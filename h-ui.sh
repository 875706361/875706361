#!/bin/bash

# 颜色定义
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
RESET="\033[0m"
BOLD="\033[1m"

# 默认配置
CONTAINER_NAME="h-ui"
IMAGE_NAME="jonssonyan/h-ui:v0.0.11"
HUI_DIR="/h-ui"
DEFAULT_WEB_PORT=8081

# 分隔线
separator() {
    echo -e "${YELLOW}-----------------------------------------------${RESET}"
}

# 检查 Docker 版本
check_docker_version() {
    separator
    echo -e "${GREEN}正在检测 Docker 版本...${RESET}"
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}Docker 未安装，请先安装 Docker！${RESET}"
        exit 1
    fi
    DOCKER_VERSION=$(docker --version | awk -F' ' '{print $3}' | tr -d ',')
    REQUIRED_VERSION="20.10.0"
    if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$DOCKER_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
        echo -e "${RED}Docker 版本过低，请升级至 $REQUIRED_VERSION 或更新版本！${RESET}"
        exit 1
    fi
    echo -e "${GREEN}Docker 版本符合要求: $DOCKER_VERSION${RESET}"
}

# 安装 Docker
install_docker() {
    check_docker_version
    echo -e "${GREEN}Docker 已安装，继续执行操作。${RESET}"
}

# 重置 H-UI 账号密码
reset_h_ui_credentials() {
    separator
    echo -e "${YELLOW}正在重置 H-UI 账号密码...${RESET}"
    docker exec -it $CONTAINER_NAME ./h-ui reset
    sleep 3
}

# 安装 H-UI
install_h_ui() {
    install_docker
    separator
    echo -e "${YELLOW}拉取指定版本 H-UI 镜像: $IMAGE_NAME${RESET}"
    docker pull $IMAGE_NAME
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
    reset_h_ui_credentials

    if [[ $(docker ps -q -f name=$CONTAINER_NAME) ]]; then
        echo -e "${GREEN}H-UI v0.0.11 已成功安装并运行！${RESET}"
        echo -e "Web 访问地址: ${GREEN}http://localhost:$web_port${RESET}"
        echo -e "${YELLOW}H-UI 配置文件路径（宿主机）:${RESET}"
        echo -e "${GREEN}$HUI_DIR/data/config.yaml${RESET}"
    else
        echo -e "${RED}H-UI 安装失败，请检查 Docker 日志。${RESET}"
        docker logs $CONTAINER_NAME
    fi
}

# 其他管理命令
status_h_ui() {
    local status=$(docker ps -a --filter "name=$CONTAINER_NAME" --format "{{.State}}")
    echo -e "H-UI 容器状态: ${GREEN}${status:-not installed}${RESET}"
}

stop_h_ui() {
    echo -e "${YELLOW}正在停止 H-UI 容器...${RESET}"
    docker stop $CONTAINER_NAME
    echo -e "${GREEN}H-UI 容器已停止。${RESET}"
}

restart_h_ui() {
    echo -e "${YELLOW}正在重启 H-UI 容器...${RESET}"
    docker restart $CONTAINER_NAME
    echo -e "${GREEN}H-UI 容器已重启。${RESET}"
}

remove_h_ui() {
    echo -e "${YELLOW}正在删除 H-UI 容器和数据...${RESET}"
    docker stop $CONTAINER_NAME &>/dev/null
    docker rm $CONTAINER_NAME &>/dev/null
    docker rmi $IMAGE_NAME &>/dev/null
    rm -rf $HUI_DIR
    echo -e "${GREEN}H-UI 容器及数据已清理。${RESET}"
}

enter_container() {
    separator
    echo -e "${GREEN}正在进入 H-UI 容器...${RESET}"
    docker exec -it $CONTAINER_NAME /bin/bash
}

# 主菜单
main_menu() {
    while true; do
        separator
        echo -e "${BOLD}${BLUE}            H-UI Docker 管理脚本${RESET}"
        separator
        echo -e "${GREEN}      1.${RESET} 安装/重新安装 H-UI"
        echo -e "${GREEN}      2.${RESET} 重置 H-UI 账号密码"
        echo -e "${GREEN}      3.${RESET} 查看容器状态"
        echo -e "${GREEN}      4.${RESET} 停止 H-UI 容器"
        echo -e "${GREEN}      5.${RESET} 重启 H-UI 容器"
        echo -e "${GREEN}      6.${RESET} 删除 H-UI 容器及数据"
        echo -e "${GREEN}      7.${RESET} 进入 H-UI 容器"
        echo -e "${GREEN}      8.${RESET} 退出"
        separator
        read -p "请选择操作 (1-8): " choice
        case $choice in
            1) install_h_ui ;;
            2) reset_h_ui_credentials ;;
            3) status_h_ui ;;
            4) stop_h_ui ;;
            5) restart_h_ui ;;
            6) remove_h_ui ;;
            7) enter_container ;;
            8) exit 0 ;;
            *) echo -e "${RED}无效输入，请重新选择。${RESET}" ;;
        esac
    done
}

# 运行主菜单
main_menu
