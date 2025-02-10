#!/bin/bash

# 颜色定义
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# 默认配置
CONTAINER_NAME="h-ui"
IMAGE_NAME="jonssonyan/h-ui"
HUI_DIR="/h-ui"
DEFAULT_PORT=8081

# 分隔线
separator() {
    echo -e "${YELLOW}---------------------------------${RESET}"
}

# 检测 Linux 发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s)
    fi
}

# 安装 Docker
install_docker() {
    separator
    echo -e "${GREEN}正在检测并安装 Docker...${RESET}"
    
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker 已安装，无需重复安装。${RESET}"
        return
    fi

    detect_os
    case "$OS" in
        almalinux|centos|rocky)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        ubuntu|debian)
            sudo apt update
            sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo apt-key add -
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/$OS $(lsb_release -cs) stable"
            sudo apt update
            sudo apt install -y docker-ce docker-ce-cli containerd.io
            ;;
        *)
            echo -e "${RED}不支持的 Linux 发行版，请手动安装 Docker。${RESET}"
            exit 1
            ;;
    esac

    sudo systemctl enable docker
    sudo systemctl start docker

    echo -e "${GREEN}Docker 安装完成！${RESET}"
}

# 检查容器状态
container_status() {
    local status=$(docker ps -a --filter "name=$CONTAINER_NAME" --format "{{.State}}")
    if [[ -z "$status" ]]; then
        echo "not installed"
    else
        echo "$status"
    fi
}

# 安装 H-UI
install_h_ui() {
    install_docker

    # 让用户选择是否拉取最新镜像
    read -p "是否拉取最新 H-UI Docker 镜像？(y/n): " pull_choice
    if [[ "$pull_choice" == "y" || "$pull_choice" == "Y" ]]; then
        echo -e "${YELLOW}拉取最新 H-UI 镜像中...${RESET}"
        docker pull $IMAGE_NAME
    fi

    # 创建挂载目录
    mkdir -p $HUI_DIR/{bin,data,export,logs}

    # 让用户输入映射端口
    read -p "请输入 H-UI 访问端口 (默认: $DEFAULT_PORT): " port
    port=${port:-$DEFAULT_PORT}

    # 运行 Docker 容器（使用 host 网络模式）
    echo -e "${YELLOW}启动 H-UI 容器中...${RESET}"
    docker run -d --cap-add=NET_ADMIN \
      --name $CONTAINER_NAME --restart always \
      --network=host \
      -e TZ=Asia/Shanghai \
      -v $HUI_DIR/bin:/h-ui/bin \
      -v $HUI_DIR/data:/h-ui/data \
      -v $HUI_DIR/export:/h-ui/export \
      -v $HUI_DIR/logs:/h-ui/logs \
      $IMAGE_NAME ./h-ui -p $port

    # 检查是否启动成功
    if [[ $(docker ps -q -f name=$CONTAINER_NAME) ]]; then
        echo -e "${GREEN}H-UI 已成功安装并运行！${RESET}"
        echo -e "访问地址: ${GREEN}http://localhost:$port${RESET}"
    else
        echo -e "${RED}H-UI 安装失败，请检查 Docker 日志。${RESET}"
        docker logs $CONTAINER_NAME
    fi
}

# 获取 H-UI 账号密码
get_h_ui_credentials() {
    separator
    echo -e "${GREEN}正在获取 H-UI 账号和密码...${RESET}"
    docker logs $CONTAINER_NAME 2>&1 | grep "账号"
}

# 进入容器修改管理员密码
change_admin_password() {
    separator
    echo -e "${YELLOW}进入 H-UI 容器修改管理员密码...${RESET}"
    docker exec -it $CONTAINER_NAME /bin/sh
}

# 查看容器状态
status_h_ui() {
    install_docker
    local status=$(container_status)
    echo -e "H-UI 容器状态: ${GREEN}$status${RESET}"
}

# 停止容器
stop_h_ui() {
    install_docker
    local status=$(container_status)

    if [[ "$status" == "running" ]]; then
        echo -e "${YELLOW}正在停止 H-UI 容器...${RESET}"
        docker stop $CONTAINER_NAME
        echo -e "${GREEN}H-UI 容器已停止。${RESET}"
    else
        echo -e "${RED}H-UI 容器未运行或不存在。${RESET}"
    fi
}

# 重启容器
restart_h_ui() {
    install_docker
    local status=$(container_status)

    if [[ "$status" == "running" ]]; then
        echo -e "${YELLOW}正在重启 H-UI 容器...${RESET}"
        docker restart $CONTAINER_NAME
        echo -e "${GREEN}H-UI 容器已重启。${RESET}"
    else
        echo -e "${RED}H-UI 容器未运行或不存在，请先安装。${RESET}"
    fi
}

# 删除容器并清理数据
remove_h_ui() {
    install_docker
    local status=$(container_status)

    if [[ "$status" == "not installed" ]]; then
        echo -e "${RED}H-UI 容器未安装。${RESET}"
        return
    fi

    echo -e "${YELLOW}正在删除 H-UI 容器和数据...${RESET}"
    docker stop $CONTAINER_NAME &>/dev/null
    docker rm $CONTAINER_NAME &>/dev/null
    docker rmi $IMAGE_NAME &>/dev/null
    rm -rf $HUI_DIR
    echo -e "${GREEN}H-UI 容器及数据已清理。${RESET}"
}

# 主菜单
main_menu() {
    while true; do
        separator
        echo -e "${GREEN}H-UI Docker 管理脚本${RESET}"
        separator
        echo -e "1. 安装/重新安装 H-UI"
        echo -e "2. 查看 H-UI 账号密码"
        echo -e "3. 进入容器修改管理员密码"
        echo -e "4. 查看容器状态"
        echo -e "5. 停止 H-UI 容器"
        echo -e "6. 重启 H-UI 容器"
        echo -e "7. 删除 H-UI 容器及数据"
        echo -e "8. 退出"
        separator
        read -p "请选择操作 (1-8): " choice
        case $choice in
            1) install_h_ui ;;
            2) get_h_ui_credentials ;;
            3) change_admin_password ;;
            4) status_h_ui ;;
            5) stop_h_ui ;;
            6) restart_h_ui ;;
            7) remove_h_ui ;;
            8) exit 0 ;;
            *) echo -e "${RED}无效输入，请重新选择。${RESET}" ;;
        esac
    done
}

# 运行主菜单
main_menu
