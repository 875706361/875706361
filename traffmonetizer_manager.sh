#!/bin/bash

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# 配置文件路径
CONFIG_FILE="/etc/traffmonetizer.conf"
CONTAINER_NAME="tm"
IMAGE_NAME="traffmonetizer/cli_v2"

# 读取 Access Token
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        echo "ACCESS_TOKEN=''" > "$CONFIG_FILE"
    fi
}

# 保存 Access Token
save_config() {
    echo "ACCESS_TOKEN='$ACCESS_TOKEN'" > "$CONFIG_FILE"
}

# 检查 & 安装 Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker 未安装，正在安装...${RESET}"
        curl -fsSL https://get.docker.com | bash
        sudo systemctl start docker
        sudo systemctl enable docker
        echo -e "${GREEN}Docker 安装完成！${RESET}"
    else
        echo -e "${GREEN}Docker 已安装！${RESET}"
    fi
}

# 运行 TraffMonetizer 容器
run_traffmonetizer() {
    echo -e "${YELLOW}请输入你的 TraffMonetizer Access Token（或回车使用已保存的）:${RESET}"
    read input_token
    if [[ ! -z "$input_token" ]]; then
        ACCESS_TOKEN="$input_token"
        save_config
    fi

    if [[ -z "$ACCESS_TOKEN" ]]; then
        echo -e "${RED}错误：Access Token 不能为空！${RESET}"
        exit 1
    fi

    echo -e "${YELLOW}请选择运行模式（默认: fast）:${RESET}"
    echo "1. normal  （普通模式）"
    echo "2. fast    （全速模式）"
    echo -n "请输入选项 (1/2): "
    read mode_choice

    case $mode_choice in
        1) SPEED_MODE="normal" ;;
        2|*) SPEED_MODE="fast" ;;
    esac

    # 停止并删除旧容器
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
        echo -e "${YELLOW}正在删除旧的 TraffMonetizer 容器...${RESET}"
        docker rm -f $CONTAINER_NAME
    fi

    # 运行新的 TraffMonetizer 容器
    echo -e "${YELLOW}正在启动 TraffMonetizer（模式：$SPEED_MODE）...${RESET}"
    docker run -d --name $CONTAINER_NAME \
      --restart always \
      $IMAGE_NAME \
      start accept --token $ACCESS_TOKEN --speed $SPEED_MODE

    # 检查容器是否成功运行
    if docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
        echo -e "${GREEN}TraffMonetizer 已成功启动！（模式：$SPEED_MODE）${RESET}"
    else
        echo -e "${RED}TraffMonetizer 启动失败，请检查日志！${RESET}"
        exit 1
    fi
}

# 查看运行状态
check_status() {
    echo -e "${YELLOW}正在检查 TraffMonetizer 运行状态...${RESET}"
    docker ps --filter "name=$CONTAINER_NAME"
}

# 停止 TraffMonetizer
stop_traffmonetizer() {
    echo -e "${YELLOW}正在停止 TraffMonetizer...${RESET}"
    docker stop $CONTAINER_NAME
}

# 删除 TraffMonetizer 容器
remove_traffmonetizer() {
    echo -e "${YELLOW}正在删除 TraffMonetizer 容器...${RESET}"
    docker rm -f $CONTAINER_NAME
}

# 交互式菜单
menu() {
    while true; do
        echo -e "\n${GREEN}TraffMonetizer 管理脚本${RESET}"
        echo "1. 运行 TraffMonetizer"
        echo "2. 查看运行状态"
        echo "3. 停止 TraffMonetizer"
        echo "4. 删除 TraffMonetizer 容器"
        echo "5. 退出"
        echo -n "请输入选项: "
        read choice

        case $choice in
            1) run_traffmonetizer ;;
            2) check_status ;;
            3) stop_traffmonetizer ;;
            4) remove_traffmonetizer ;;
            5) exit ;;
            *) echo -e "${RED}无效选项，请重新输入！${RESET}" ;;
        esac
    done
}

# 执行脚本
load_config
install_docker
menu
