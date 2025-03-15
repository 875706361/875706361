#!/bin/bash

# 定义变量
CONTAINER_NAME="h-ui"
IMAGE_NAME="jonssonyan/h-ui"
WEB_PORT="8081" # 默认端口
TIMEZONE="Asia/Shanghai" # 默认时区
HUI_DATA_DIR="/h-ui" # h-ui 数据目录

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 检查 Docker 是否安装
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo "${YELLOW}Docker 未安装，正在尝试自动安装...${NC}"
    install_docker
  else
    echo "${GREEN}Docker 已安装。${NC}"
  fi
}

# 安装 Docker
install_docker() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "${RED}请以 root 用户或使用 sudo 运行此脚本以安装 Docker。${NC}"
    exit 1
  fi

  if command -v apt-get &> /dev/null; then
    # Ubuntu/Debian 系统
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
  elif command -v yum &> /dev/null; then
    # CentOS/RHEL 系统
    yum install -y yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io
    systemctl start docker
    systemctl enable docker
  elif command -v dnf &> /dev/null; then
    # Fedora 系统
    dnf install -y dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io
    systemctl start docker
    systemctl enable docker
  else
    echo "${RED}不支持的 Linux 发行版，请手动安装 Docker。${NC}"
    exit 1
  fi

  echo "${GREEN}Docker 安装完成。${NC}"
}

# 安装 h-ui
install_hui() {
  echo "${YELLOW}正在安装 h-ui...${NC}"
  read -p "请输入 Web 端口 (默认为 8081): " web_port
  read -p "请输入时区 (默认为 Asia/Shanghai): " timezone

  if [ -n "$web_port" ]; then
    WEB_PORT="$web_port"
  fi

  if [ -n "$timezone" ]; then
    TIMEZONE="$timezone"
  fi

  docker run -d --cap-add=NET_ADMIN \
    --name ${CONTAINER_NAME} --restart always \
    --network=host \
    -e TZ=${TIMEZONE} \
    -v ${HUI_DATA_DIR}/bin:${HUI_DATA_DIR}/bin \
    -v ${HUI_DATA_DIR}/data:${HUI_DATA_DIR}/data \
    -v ${HUI_DATA_DIR}/export:${HUI_DATA_DIR}/export \
    -v ${HUI_DATA_DIR}/logs:${HUI_DATA_DIR}/logs \
    ${IMAGE_NAME} \
    ./h-ui -p ${WEB_PORT}

  if [ $? -eq 0 ]; then
    echo "${GREEN}h-ui 安装成功！可以通过 http://localhost:${WEB_PORT} 访问。${NC}"
  else
    echo "${RED}h-ui 安装失败。${NC}"
  fi
}

# 进入容器
enter_container() {
  echo "${YELLOW}正在进入 h-ui 容器...${NC}"
  docker exec -it ${CONTAINER_NAME} /bin/bash
}

# 删除容器
delete_container() {
  echo "${YELLOW}正在删除 h-ui 容器...${NC}"
  docker stop ${CONTAINER_NAME}
  docker rm -f ${CONTAINER_NAME}
  docker rmi ${IMAGE_NAME}
  rm -rf ${HUI_DATA_DIR}
  echo "${GREEN}h-ui 容器已删除。${NC}"
}

# 重启容器
restart_container() {
  echo "${YELLOW}正在重启 h-ui 容器...${NC}"
  docker restart ${CONTAINER_NAME}
  echo "${GREEN}h-ui 容器已重启。${NC}"
}

# 在容器中重启 h-ui
restart_h_ui_in_container() {
  echo "${YELLOW}正在容器内重启 h-ui 服务...${NC}"
  docker exec ${CONTAINER_NAME} systemctl restart h-ui
  if [ $? -eq 0 ]; then
    echo "${GREEN}容器内 h-ui 服务已重启。${NC}"
  else
    echo "${RED}容器内 h-ui 服务重启失败。${NC}"
  fi
}

# 主菜单
main_menu() {
  while true; do
    # 计算终端宽度
    terminal_width=$(tput cols)
    menu_width=30 # 菜单宽度
    padding=$(( (terminal_width - menu_width) / 2 )) # 计算填充

    # 输出菜单
    echo ""
    printf "%${padding}s %s\n" "" "------------------------"
    printf "%${padding}s %s\n" "" "${GREEN}h-ui 管理脚本${NC}"
    printf "%${padding}s %s\n" "" "------------------------"
    printf "%${padding}s %s\n" "" "1. 安装 h-ui"
    printf "%${padding}s %s\n" "" "2. 进入 h-ui 容器"
    printf "%${padding}s %s\n" "" "3. 删除 h-ui 容器"
    printf "%${padding}s %s\n" "" "4. 重启 h-ui 容器"
    printf "%${padding}s %s\n" "" "5. 在容器中重启 h-ui"
    printf "%${padding}s %s\n" "" "6. 退出"
    read -p "请选择操作 (1-6): " choice

    case $choice in
      1) install_hui ;;
      2) enter_container ;;
      3) delete_container ;;
      4) restart_container ;;
      5) restart_h_ui_in_container ;;
      6) exit 0 ;;
      *) echo "${RED}无效的选择，请重新输入。${NC}" ;;
    esac
  done
}

# 检查 Docker 并运行主菜单
check_docker
main_menu
