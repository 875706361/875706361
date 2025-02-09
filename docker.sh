#!/bin/bash

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# 检测当前 Linux 发行版
detect_os() {
    if grep -qi "ubuntu" /etc/os-release; then
        OS="ubuntu"
    elif grep -qi "debian" /etc/os-release; then
        OS="debian"
    elif grep -qi "alma" /etc/os-release; then
        OS="almalinux"
    elif grep -qi "centos" /etc/os-release; then
        OS="centos"
    elif grep -qi "rocky" /etc/os-release; then
        OS="rockylinux"
    else
        echo -e "${RED}无法检测到受支持的 Linux 发行版，脚本终止！${RESET}"
        exit 1
    fi
    echo -e "${GREEN}检测到系统：$OS${RESET}"
}

# 安装必要的依赖软件
install_dependencies() {
    echo -e "${YELLOW}正在安装必要的依赖软件...${RESET}"
    case $OS in
        ubuntu|debian)
            sudo apt update
            sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common
            ;;
        almalinux|centos|rockylinux)
            sudo yum install -y yum-utils curl ca-certificates
            ;;
    esac
    echo -e "${GREEN}依赖软件安装完成！${RESET}"
}

# 安装 Docker
install_docker() {
    echo -e "${YELLOW}正在安装 Docker...${RESET}"

    case $OS in
        ubuntu|debian)
            curl -fsSL https://download.docker.com/linux/${OS}/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${OS} $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt update
            sudo apt install -y docker-ce docker-ce-cli containerd.io
            ;;
        almalinux|centos|rockylinux)
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
    esac

    # 启动并设置开机自启
    sudo systemctl start docker
    sudo systemctl enable docker

    echo -e "${GREEN}Docker 安装完成！${RESET}"
}

# 安装 Docker Compose
install_docker_compose() {
    echo -e "${YELLOW}正在安装 Docker Compose...${RESET}"
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
    sudo curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose 安装完成！${RESET}"
}

# 查看运行中的容器
view_running_containers() {
    echo -e "${YELLOW}当前运行的容器:${RESET}"
    docker ps
}

# 删除指定容器
delete_container() {
    echo -e "${YELLOW}请输入要删除的容器 ID:${RESET}"
    read CONTAINER_ID
    if [ -n "$CONTAINER_ID" ]; then
        docker rm -f "$CONTAINER_ID"
        echo -e "${GREEN}容器 $CONTAINER_ID 已删除！${RESET}"
    else
        echo -e "${RED}未输入容器 ID，操作取消！${RESET}"
    fi
}

# 交互式菜单
menu() {
    while true; do
        echo -e "\n${GREEN}Docker 管理脚本${RESET}"
        echo "1. 安装 Docker"
        echo "2. 安装 Docker Compose"
        echo "3. 启动 Docker"
        echo "4. 停止 Docker"
        echo "5. 重启 Docker"
        echo "6. 设置 Docker 开机自启"
        echo "7. 取消 Docker 开机自启"
        echo "8. 查看运行中的容器"
        echo "9. 删除指定容器"
        echo "10. 退出"
        echo -n "请输入选项: "
        read choice

        case $choice in
            1) install_dependencies; install_docker ;;
            2) install_docker_compose ;;
            3) sudo systemctl start docker; echo -e "${GREEN}Docker 已启动${RESET}" ;;
            4) sudo systemctl stop docker; echo -e "${RED}Docker 已停止${RESET}" ;;
            5) sudo systemctl restart docker; echo -e "${GREEN}Docker 已重启${RESET}" ;;
            6) sudo systemctl enable docker; echo -e "${GREEN}Docker 开机自启已设置${RESET}" ;;
            7) sudo systemctl disable docker; echo -e "${RED}Docker 开机自启已取消${RESET}" ;;
            8) view_running_containers ;;
            9) delete_container ;;
            10) exit ;;
            *) echo -e "${RED}无效选项，请重新输入！${RESET}" ;;
        esac
    done
}

# 运行脚本
detect_os
menu
