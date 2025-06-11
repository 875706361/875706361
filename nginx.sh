#!/bin/bash

SCRIPT_VERSION="2.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}错误：请以 root 用户运行此脚本。${NC}"
  exit 1
fi

script_info() {
  echo -e "${BLUE}Nginx 管理脚本 v${SCRIPT_VERSION}${NC}"
  echo "--------------------------------------------"
  echo "本脚本自动编译安装 Nginx，支持 MP4 模块"
  echo "并配置访问 /CLAY/1 目录支持视频播放"
  echo "--------------------------------------------"
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS="${ID,,}"
  else
    echo -e "${RED}错误：无法检测到操作系统。${NC}"
    exit 1
  fi

  case "$OS" in
    ubuntu|debian)
      PACKAGE_MANAGER="apt"
      DEP_PACKAGES="build-essential libpcre3 libpcre3-dev libssl-dev zlib1g-dev wget"
      DEFAULT_SITE_CONFIG="/etc/nginx/sites-available/default"
      ;;
    centos|rhel|fedora)
      PACKAGE_MANAGER="yum"
      DEP_PACKAGES="gcc gcc-c++ make pcre pcre-devel zlib zlib-devel openssl-devel wget"
      DEFAULT_SITE_CONFIG="/etc/nginx/conf.d/default.conf"
      ;;
    opensuse|suse)
      PACKAGE_MANAGER="zypper"
      DEP_PACKAGES="gcc gcc-c++ make pcre-devel zlib-devel libopenssl-devel wget"
      DEFAULT_SITE_CONFIG="/etc/nginx/default.conf"
      ;;
    arch)
      PACKAGE_MANAGER="pacman"
      DEP_PACKAGES="base-devel pcre openssl zlib wget"
      DEFAULT_SITE_CONFIG="/etc/nginx/sites-available/default"
      ;;
    *)
      echo -e "${RED}错误：不支持的操作系统 ${BLUE}$OS${NC}"
      exit 1
      ;;
  esac
  echo -e "${GREEN}检测到操作系统：${BLUE}$OS${NC}"
  echo -e "${GREEN}使用包管理器：${BLUE}$PACKAGE_MANAGER${NC}"
}

install_dependencies() {
  echo -e "${YELLOW}安装编译依赖包...${NC}"
  case "$PACKAGE_MANAGER" in
    apt)
      apt update
      apt install -y $DEP_PACKAGES
      ;;
    yum)
      yum install -y $DEP_PACKAGES
      ;;
    zypper)
      zypper --non-interactive install $DEP_PACKAGES
      ;;
    pacman)
      pacman -Sy --noconfirm $DEP_PACKAGES
      ;;
  esac
}

compile_nginx() {
  local version="1.27.5"
  local src_url="http://nginx.org/download/nginx-${version}.tar.gz"
  local workdir="/usr/local/src/nginx_build"

  echo -e "${YELLOW}开始编译安装 Nginx ${version}，包含 http_mp4_module 模块...${NC}"

  mkdir -p "$workdir"
  cd "$workdir" || exit 1

  if [[ ! -f "nginx-${version}.tar.gz" ]]; then
    wget "$src_url"
  fi

  tar zxvf "nginx-${version}.tar.gz"
  cd "nginx-${version}" || exit 1

  ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/lock/nginx.lock \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_mp4_module \
    --with-pcre \
    --with-file-aio \
    --with-threads \
    --with-http_gzip_static_module

  make && make install

  if [[ $? -ne 0 ]]; then
    echo -e "${RED}编译安装 Nginx 失败！请检查错误日志。${NC}"
    exit 1
  fi

  echo -e "${GREEN}编译安装 Nginx 成功！${NC}"
}

install_nginx() {
  install_dependencies
  compile_nginx
  configure_clay_video_access
  start_nginx
}

uninstall_nginx() {
  echo -e "${YELLOW}卸载 Nginx...${NC}"
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
  echo -e "${GREEN}卸载完成。${NC}"
}

start_nginx() {
  echo -e "${YELLOW}启动 Nginx 服务...${NC}"
  systemctl start nginx
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 启动成功${NC}"
  else
    echo -e "${RED}Nginx 启动失败，请检查日志${NC}"
  fi
}

stop_nginx() {
  echo -e "${YELLOW}停止 Nginx 服务...${NC}"
  systemctl stop nginx
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 停止成功${NC}"
  else
    echo -e "${RED}Nginx 停止失败，请检查日志${NC}"
  fi
}

restart_nginx() {
  echo -e "${YELLOW}重启 Nginx 服务...${NC}"
  systemctl restart nginx
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 重启成功${NC}"
  else
    echo -e "${RED}Nginx 重启失败，请检查日志${NC}"
  fi
}

change_port() {
  local current_port
  current_port=$(ss -tuln | grep -E 'nginx|:80' | awk '{print $5}' | cut -d':' -f2 | head -n1)
  current_port=${current_port:-80}

  read -p "请输入新的 Nginx 端口号（当前端口：${BLUE}$current_port${NC}，默认：80）：" new_port
  new_port=${new_port:-80}

  if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "${RED}错误：无效的端口号。${NC}"
    return
  fi

  if [[ "$new_port" == "$current_port" ]]; then
    echo -e "${YELLOW}Nginx 已经运行在端口 ${BLUE}$new_port${NC}，无需修改。${NC}"
    return
  fi

  sed -i -r "s/listen\s+[0-9]+;/listen $new_port;/" "$DEFAULT_SITE_CONFIG"

  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}端口修改成功，正在重启 Nginx...${NC}"
    restart_nginx
  else
    echo -e "${RED}Nginx 配置语法错误，端口修改失败。请检查配置文件。${NC}"
  fi
}

change_web_root() {
  read -p "是否将默认网站根目录更改为 /CLAY 并创建示例首页？（yes/no）：" confirm
  if [[ "$confirm" =~ ^(yes|y)$ ]]; then
    if [[ ! -d "/CLAY" ]]; then
      mkdir -p /CLAY || { echo -e "${RED}创建目录 /CLAY 失败${NC}"; return; }
    fi

    cat > /CLAY/index.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><title>欢迎</title></head>
<body><h1>欢迎光临</h1></body>
</html>
EOF

    sed -i -r "s#root\s+[^;]+;#root /CLAY;#" "$DEFAULT_SITE_CONFIG"

    nginx -t
    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}网站根目录修改成功，重启 Nginx...${NC}"
      restart_nginx
    else
      echo -e "${RED}配置语法错误，根目录修改失败。${NC}"
    fi
  else
    echo -e "${YELLOW}取消修改网站根目录。${NC}"
  fi
}

configure_https() {
  echo -e "${YELLOW}HTTPS 配置功能待完善...${NC}"
  # 这里你可以根据需要自行扩展
}

configure_clay_video_access() {
  echo -e "${YELLOW}配置 Nginx 支持访问 /CLAY/1 目录的视频播放...${NC}"

  cp "$DEFAULT_SITE_CONFIG" "${DEFAULT_SITE_CONFIG}.bak"

  sed -i '/location \/1\//,/\}/d' "$DEFAULT_SITE_CONFIG"

  sed -i "/server {/a \\
    location /1/ {\\
        alias /CLAY/1/;\\
        autoindex on;\\
        mp4;\\
        mp4_buffer_size 1m;\\
        mp4_max_buffer_size 5m;\\
    }" "$DEFAULT_SITE_CONFIG"

  if [[ -d /CLAY ]]; then
    cat > /CLAY/index.html <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><title>视频播放示例</title></head>
<body>
<h1>视频播放示例</h1>
<p>请将视频文件上传到 /CLAY/1 目录，然后访问 /1/视频文件名.mp4 播放。</p>
<video width="640" height="360" controls>
  <source src="/1/sample.mp4" type="video/mp4" />
  您的浏览器不支持 video 标签。
</video>
</body>
</html>
EOF
    chown www-data:www-data /CLAY/index.html
    chmod 644 /CLAY/index.html
  else
    echo -e "${YELLOW}目录 /CLAY 不存在，示例首页未创建，请自行创建。${NC}"
  fi

  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}配置语法正确，重启 Nginx...${NC}"
    systemctl restart nginx
  else
    echo -e "${RED}配置语法错误，恢复备份文件。${NC}"
    mv -f "${DEFAULT_SITE_CONFIG}.bak" "$DEFAULT_SITE_CONFIG"
  fi
}

main_menu() {
  script_info
  echo "请选择操作："
  echo "1) 安装 Nginx（源码编译）"
  echo "2) 卸载 Nginx"
  echo "3) 启动 Nginx"
  echo "4) 停止 Nginx"
  echo "5) 重启 Nginx"
  echo "6) 修改默认端口"
  echo "7) 修改默认网站根目录为 /CLAY 并创建示例首页"
  echo "8) 配置 HTTPS（待完善）"
  echo "0) 退出"
  echo -n "输入选项: "
  read choice
}

main() {
  detect_os
  while true; do
    main_menu
    case "$choice" in
      1) install_nginx ;;
      2) uninstall_nginx ;;
      3) start_nginx ;;
      4) stop_nginx ;;
      5) restart_nginx ;;
      6) change_port ;;
      7) change_web_root ;;
      8) configure_https ;;
      0) echo -e "${YELLOW}退出脚本。${NC}"; exit 0 ;;
      *) echo -e "${RED}无效选项，请重试。${NC}" ;;
    esac
  done
}

main
