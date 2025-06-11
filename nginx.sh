#!/bin/bash

# 脚本版本
SCRIPT_VERSION="1.10"

# 颜色代码定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 检查是否以 root 运行
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}错误：请以 root 用户运行此脚本。${NC}"
  exit 1
fi

# 输出脚本信息
script_info() {
  echo -e "${BLUE}Nginx 管理脚本 v${SCRIPT_VERSION}${NC}"
  echo "-------------------------"
  echo "本脚本用于管理 Nginx 服务和配置。"
  echo "-------------------------"
}

# 检测操作系统及设置变量
detect_os() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS="${ID,,}"
  elif [[ -f /etc/debian_version ]]; then
    OS="debian"
  elif [[ -f /etc/redhat-release ]]; then
    OS="redhat"
  elif [[ -f /etc/SuSE-release ]]; then
    OS="suse"
  else
    echo -e "${RED}错误：无法检测到操作系统。${NC}"
    exit 1
  fi

  case "$OS" in
    ubuntu|debian)
      PACKAGE_MANAGER="apt"
      SERVICE_MANAGER="systemctl"
      CONFIG_FILE="/etc/nginx/nginx.conf"
      CONFIG_DIR="/etc/nginx"
      SITES_AVAILABLE_DIR="/etc/nginx/sites-available"
      SITES_ENABLED_DIR="/etc/nginx/sites-enabled"
      DEFAULT_SITE_CONFIG="/etc/nginx/sites-available/default"
      ;;
    centos|redhat|fedora)
      PACKAGE_MANAGER="yum"
      SERVICE_MANAGER="systemctl"
      CONFIG_FILE="/etc/nginx/nginx.conf"
      CONFIG_DIR="/etc/nginx"
      SITES_AVAILABLE_DIR="/etc/nginx/conf.d"
      SITES_ENABLED_DIR="/etc/nginx/conf.d"
      DEFAULT_SITE_CONFIG="/etc/nginx/conf.d/default.conf"
      ;;
    opensuse|suse)
      PACKAGE_MANAGER="zypper"
      SERVICE_MANAGER="systemctl"
      CONFIG_FILE="/etc/nginx/nginx.conf"
      CONFIG_DIR="/etc/nginx"
      SITES_AVAILABLE_DIR="/etc/nginx/vhosts.d"
      SITES_ENABLED_DIR="/etc/nginx/vhosts.d"
      DEFAULT_SITE_CONFIG="/etc/nginx/default.conf"
      ;;
    arch)
      PACKAGE_MANAGER="pacman"
      SERVICE_MANAGER="systemctl"
      CONFIG_FILE="/etc/nginx/nginx.conf"
      CONFIG_DIR="/etc/nginx"
      SITES_AVAILABLE_DIR="/etc/nginx/sites-available"
      SITES_ENABLED_DIR="/etc/nginx/sites-enabled"
      DEFAULT_SITE_CONFIG="/etc/nginx/sites-available/default"
      ;;
    *)
      echo -e "${RED}错误：不支持的操作系统：${BLUE}$OS${NC}"
      exit 1
      ;;
  esac

  echo -e "${GREEN}检测到操作系统：${BLUE}$OS${NC}"
  echo -e "${GREEN}使用的包管理器：${BLUE}$PACKAGE_MANAGER${NC}"
  echo -e "${GREEN}使用的服务管理器：${BLUE}$SERVICE_MANAGER${NC}"
  echo -e "${GREEN}Nginx 主配置文件路径：${BLUE}$CONFIG_FILE${NC}"
  echo -e "${GREEN}Nginx 配置目录：${BLUE}$CONFIG_DIR${NC}"
  echo -e "${GREEN}Nginx 可用站点配置目录：${BLUE}$SITES_AVAILABLE_DIR${NC}"
  echo -e "${GREEN}Nginx 启用站点配置目录：${BLUE}$SITES_ENABLED_DIR${NC}"
  echo -e "${GREEN}Nginx 默认站点配置文件路径：${BLUE}$DEFAULT_SITE_CONFIG${NC}"
}

# 检查 Nginx 是否安装
is_nginx_installed() {
  command -v nginx >/dev/null 2>&1
}

# 启动 Nginx
start_nginx() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装，请先安装。${NC}"
    return
  fi
  echo -e "${YELLOW}正在启动 Nginx 服务...${NC}"
  $SERVICE_MANAGER start nginx
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 启动成功。${NC}"
  else
    echo -e "${RED}错误：启动 Nginx 失败。请检查配置或日志。${NC}"
  fi
}

# 停止 Nginx
stop_nginx() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装。${NC}"
    return
  fi
  echo -e "${YELLOW}正在停止 Nginx 服务...${NC}"
  $SERVICE_MANAGER stop nginx
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 停止成功。${NC}"
  else
    echo -e "${RED}错误：停止 Nginx 失败。${NC}"
  fi
}

# 重启 Nginx
restart_nginx() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装。${NC}"
    return
  fi
  echo -e "${YELLOW}正在重启 Nginx 服务...${NC}"
  $SERVICE_MANAGER restart nginx
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 重启成功。${NC}"
  else
    echo -e "${RED}错误：重启 Nginx 失败。请检查配置或日志。${NC}"
  fi
}

# 安装 Nginx，并自动配置访问 /CLAY/1 目录支持视频播放（不创建目录）
install_nginx() {
  echo -e "${YELLOW}正在安装 Nginx...${NC}"
  if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    apt update
    apt install -y nginx
  elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
    yum install -y nginx
  elif [[ "$PACKAGE_MANAGER" == "zypper" ]]; then
    zypper --non-interactive install nginx
  elif [[ "$PACKAGE_MANAGER" == "pacman" ]]; then
    pacman -S --noconfirm nginx
  fi

  if is_nginx_installed; then
    echo -e "${GREEN}Nginx 安装成功。${NC}"
    start_nginx
    configure_clay_video_access
  else
    echo -e "${RED}错误：Nginx 安装失败。请检查网络或软件源。${NC}"
  fi
}

# 卸载 Nginx
uninstall_nginx() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装。${NC}"
    return
  fi

  echo -e "${YELLOW}正在卸载 Nginx...${NC}"
  if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    apt purge -y nginx nginx-common nginx-core
    apt autoremove -y
  elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
    yum remove -y nginx
  elif [[ "$PACKAGE_MANAGER" == "zypper" ]]; then
    zypper --non-interactive remove nginx
  elif [[ "$PACKAGE_MANAGER" == "pacman" ]]; then
    pacman -R --noconfirm nginx
  fi
  echo -e "${GREEN}Nginx 卸载成功。${NC}"
}

# 配置 /CLAY/1 目录访问支持（不创建目录）
configure_clay_video_access() {
  echo -e "${YELLOW}配置 Nginx 支持访问 /CLAY/1 目录的视频播放...${NC}"

  # 备份默认站点配置文件
  cp "$DEFAULT_SITE_CONFIG" "${DEFAULT_SITE_CONFIG}.bak"

  # 删除已有的 location /1/ 配置，避免重复
  sed -i '/location \/1\//,/\}/d' "$DEFAULT_SITE_CONFIG"

  # 在 server { 行后插入 location /1/ 块
  sed -i "/server {/a \\
    location /1/ {\\
        alias /CLAY/1/;\\
        autoindex on;\\
    }" "$DEFAULT_SITE_CONFIG"

  # 创建示例首页，提示用户自行上传视频
  if [[ ! -d "/CLAY" ]]; then
    echo -e "${YELLOW}注意：目录 /CLAY 不存在，示例首页无法创建。请自行创建。${NC}"
  else
    INDEX_HTML="/CLAY/index.html"
    echo -e "${YELLOW}创建示例首页：${INDEX_HTML}${NC}"
    cat > "$INDEX_HTML" <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <title>视频播放示例</title>
</head>
<body>
  <h1>视频播放示例</h1>
  <p>请将视频文件上传到 <code>/CLAY/1</code> 目录，然后访问 <code>/1/视频文件名.mp4</code> 播放。</p>
  <video width="640" height="360" controls>
    <source src="/1/sample.mp4" type="video/mp4" />
    您的浏览器不支持 video 标签。
  </video>
</body>
</html>
EOF
    chown www-data:www-data "$INDEX_HTML"
    chmod 644 "$INDEX_HTML"
  fi

  # 测试 Nginx 配置
  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 配置语法正确，正在重启 Nginx...${NC}"
    restart_nginx
  else
    echo -e "${RED}错误：Nginx 配置语法错误，恢复备份。${NC}"
    mv -f "${DEFAULT_SITE_CONFIG}.bak" "$DEFAULT_SITE_CONFIG"
  fi
}

# 其他函数省略，保持你之前的脚本内容（如修改端口、修改根目录、HTTPS配置等）

# 主菜单
main_menu() {
  echo -e "${BLUE}Nginx 管理脚本 v${SCRIPT_VERSION}${NC}"
  echo "-------------------------"
  echo "1. 安装 Nginx"
  echo "2. 卸载 Nginx"
  echo "3. 启动 Nginx"
  echo "4. 停止 Nginx"
  echo "5. 重启 Nginx"
  echo "6. 修改默认端口"
  echo "7. 修改默认网站根目录为 /CLAY 并创建示例首页"
  echo "8. 配置 HTTPS (SSL)"
  echo "0. 退出"
  echo "-------------------------"
  read -p "请选择一个选项： " choice
}

# 主程序
script_info
detect_os

while true; do
  main_menu
  case "$choice" in
    1) install_nginx ;;
    2) uninstall_nginx ;;
    3) start_nginx ;;
    4) stop_nginx ;;
    5) restart_nginx ;;
    6) change_port ;;           # 你之前的函数
    7) change_web_root ;;       # 你之前的函数
    8) configure_https ;;       # 你之前的函数
    0) echo -e "${YELLOW}正在退出...${NC}" && exit 0 ;;
    *) echo -e "${RED}无效选择，请重试。${NC}" ;;
  esac
done
