#!/bin/bash

SCRIPT_VERSION="2.1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 添加错误处理函数
handle_error() {
  local message="$1"
  local exit_code="${2:-1}"
  echo -e "${RED}错误：${message}${NC}"
  [[ "$exit_code" -ne 0 ]] && exit "$exit_code"
  return 1
}

if [[ $EUID -ne 0 ]]; then
  handle_error "请以 root 用户运行此脚本。" 1
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
    OS_VERSION="$VERSION_ID"
  elif [[ -f /etc/lsb-release ]]; then
    source /etc/lsb-release
    OS="${DISTRIB_ID,,}"
    OS_VERSION="$DISTRIB_RELEASE"
  else
    handle_error "无法检测到操作系统。"
  fi

  echo -e "${GREEN}检测到操作系统：${BLUE}$OS $OS_VERSION${NC}"
  
  case "$OS" in
    ubuntu|debian)
      PACKAGE_MANAGER="apt"
      DEP_PACKAGES="build-essential libpcre3 libpcre3-dev libssl-dev zlib1g-dev wget curl"
      DEFAULT_SITE_CONFIG="/etc/nginx/sites-available/default"
      SERVICE_RESTART="systemctl restart nginx || service nginx restart"
      ;;
    centos|rhel|fedora)
      PACKAGE_MANAGER="yum"
      DEP_PACKAGES="gcc gcc-c++ make pcre pcre-devel zlib zlib-devel openssl-devel wget curl"
      DEFAULT_SITE_CONFIG="/etc/nginx/conf.d/default.conf"
      SERVICE_RESTART="systemctl restart nginx || service nginx restart"
      ;;
    opensuse|suse)
      PACKAGE_MANAGER="zypper"
      DEP_PACKAGES="gcc gcc-c++ make pcre-devel zlib-devel libopenssl-devel wget curl"
      DEFAULT_SITE_CONFIG="/etc/nginx/default.conf"
      SERVICE_RESTART="systemctl restart nginx"
      ;;
    arch)
      PACKAGE_MANAGER="pacman"
      DEP_PACKAGES="base-devel pcre openssl zlib wget curl"
      DEFAULT_SITE_CONFIG="/etc/nginx/sites-available/default"
      SERVICE_RESTART="systemctl restart nginx"
      ;;
    *)
      handle_error "不支持的操作系统 ${BLUE}$OS${NC}"
      ;;
  esac
  
  echo -e "${GREEN}使用包管理器：${BLUE}$PACKAGE_MANAGER${NC}"
}

install_dependencies() {
  echo -e "${YELLOW}安装编译依赖包...${NC}"
  
  # 检查网络连接
  if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    echo -e "${YELLOW}警告：网络连接可能有问题，安装可能会失败。${NC}"
  fi
  
  case "$PACKAGE_MANAGER" in
    apt)
      apt update
      apt install -y $DEP_PACKAGES || handle_error "无法安装依赖包"
      ;;
    yum)
      yum install -y epel-release
      yum install -y $DEP_PACKAGES || handle_error "无法安装依赖包"
      ;;
    zypper)
      zypper --non-interactive refresh
      zypper --non-interactive install $DEP_PACKAGES || handle_error "无法安装依赖包"
      ;;
    pacman)
      pacman -Sy --noconfirm $DEP_PACKAGES || handle_error "无法安装依赖包"
      ;;
  esac
  
  echo -e "${GREEN}依赖包安装完成${NC}"
}

compile_nginx() {
  local version="1.27.5"
  local src_url="http://nginx.org/download/nginx-${version}.tar.gz"
  local workdir="/usr/local/src/nginx_build"
  
  # 检查是否已安装
  if command -v nginx >/dev/null 2>&1; then
    local current_version=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
    echo -e "${YELLOW}检测到已安装 Nginx ${current_version}${NC}"
    read -p "是否继续安装 Nginx ${version}？ (yes/no): " confirm
    if [[ ! "$confirm" =~ ^(yes|y)$ ]]; then
      echo -e "${YELLOW}安装已取消${NC}"
      return
    fi
  fi

  echo -e "${YELLOW}开始编译安装 Nginx ${version}...${NC}"
  
  # 创建工作目录
  mkdir -p "$workdir" || handle_error "无法创建工作目录 $workdir"
  cd "$workdir" || handle_error "无法进入工作目录 $workdir"
  
  # 下载源码
  echo -e "${YELLOW}下载 Nginx 源码...${NC}"
  if [[ ! -f "nginx-${version}.tar.gz" ]]; then
    wget "$src_url" -O "nginx-${version}.tar.gz" || handle_error "下载 Nginx 源码失败"
  fi
  
  # 解压源码
  echo -e "${YELLOW}解压源码...${NC}"
  tar zxf "nginx-${version}.tar.gz" || handle_error "解压 Nginx 源码失败"
  cd "nginx-${version}" || handle_error "无法进入源码目录"
  
  echo -e "${YELLOW}配置 Nginx 构建环境...${NC}"
  ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/lock/nginx.lock \
    --user=www-data \
    --group=www-data \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_mp4_module \
    --with-http_flv_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-pcre \
    --with-file-aio \
    --with-threads || handle_error "配置 Nginx 构建环境失败"

  echo -e "${YELLOW}编译 Nginx...${NC}"
  # 获取CPU核心数以优化编译性能
  local cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
  make -j "$cpu_cores" || handle_error "编译 Nginx 失败"
  
  echo -e "${YELLOW}安装 Nginx...${NC}"
  make install || handle_error "安装 Nginx 失败"

  # 创建Systemd服务单元文件
  create_systemd_service
  
  echo -e "${GREEN}Nginx ${version} 编译安装完成！${NC}"
}

# 创建systemd服务文件
create_systemd_service() {
  echo -e "${YELLOW}创建 Nginx systemd 服务...${NC}"
  cat > /lib/systemd/system/nginx.service <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable nginx
  echo -e "${GREEN}Nginx systemd 服务创建完成${NC}"
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
  # 检查配置文件
  nginx -t > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Nginx 配置文件有错误，启动前请修复。${NC}"
    nginx -t
    return 1
  fi
  
  systemctl start nginx || service nginx start
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 启动成功${NC}"
    echo -e "Nginx 状态：$(systemctl status nginx 2>/dev/null | grep Active || service nginx status)"
    check_nginx_port
  else
    handle_error "Nginx 启动失败，请检查日志" 0
  fi
}

stop_nginx() {
  echo -e "${YELLOW}停止 Nginx 服务...${NC}"
  systemctl stop nginx || service nginx stop
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 停止成功${NC}"
  else
    handle_error "Nginx 停止失败，请检查日志" 0
    
    # 如果服务停止失败，尝试直接杀死进程
    local pid=$(pgrep nginx)
    if [[ -n "$pid" ]]; then
      echo -e "${YELLOW}尝试强制结束 Nginx 进程...${NC}"
      kill -9 $pid
      if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Nginx 进程已强制结束${NC}"
      else
        echo -e "${RED}无法强制结束 Nginx 进程${NC}"
      fi
    fi
  fi
}

restart_nginx() {
  echo -e "${YELLOW}重启 Nginx 服务...${NC}"
  # 检查配置文件
  nginx -t > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Nginx 配置文件有错误，重启前请修复。${NC}"
    nginx -t
    return 1
  fi
  
  eval "$SERVICE_RESTART"
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 重启成功${NC}"
    check_nginx_port
  else
    handle_error "Nginx 重启失败，请检查日志" 0
  fi
}

check_nginx_port() {
  # 检查 Nginx 使用的端口
  local port=$(grep -E "listen\s+[0-9]+" "$DEFAULT_SITE_CONFIG" | grep -oP "listen\s+\K[0-9]+" | head -1)
  port=${port:-80}
  
  echo -e "${YELLOW}检查 Nginx 端口 ${port} 是否正常监听...${NC}"
  
  # 等待端口启动
  for i in {1..5}; do
    if ss -tuln | grep -q ":$port "; then
      echo -e "${GREEN}Nginx 正在监听端口 ${port}${NC}"
      return 0
    fi
    echo -ne "${YELLOW}.${NC}"
    sleep 1
  done
  
  echo -e "\n${RED}警告：Nginx 可能未正确监听端口 ${port}，请检查${NC}"
  return 1
}

change_port() {
  local current_port
  current_port=$(grep -E "listen\s+[0-9]+" "$DEFAULT_SITE_CONFIG" | grep -oP "listen\s+\K[0-9]+" | head -1)
  current_port=${current_port:-80}

  echo -e "当前 Nginx 端口：${BLUE}$current_port${NC}"
  read -p "请输入新的 Nginx 端口号（默认：80）：" new_port
  new_port=${new_port:-80}

  # 验证端口号是否有效
  if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
    handle_error "无效的端口号。请输入 1-65535 之间的数字。" 0
    return 1
  fi

  if [[ "$new_port" == "$current_port" ]]; then
    echo -e "${YELLOW}Nginx 已经运行在端口 ${BLUE}$new_port${NC}，无需修改。${NC}"
    return 0
  fi
  
  # 检查端口是否被占用
  if ss -tuln | grep -q ":$new_port "; then
    local process_info=$(ss -tulnp | grep ":$new_port " | head -1)
    echo -e "${RED}错误：端口 $new_port 已被占用${NC}"
    echo -e "占用进程信息：$process_info"
    
    read -p "是否仍然继续修改？(yes/no): " force_change
    if [[ ! "$force_change" =~ ^(yes|y)$ ]]; then
      echo -e "${YELLOW}操作已取消${NC}"
      return 1
    fi
  fi

  echo -e "${YELLOW}修改 Nginx 端口 ${current_port} -> ${new_port}...${NC}"
  
  # 备份配置文件
  local backup_file="${DEFAULT_SITE_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$DEFAULT_SITE_CONFIG" "$backup_file" || handle_error "无法备份配置文件" 0
  echo -e "${GREEN}配置文件已备份为：${backup_file}${NC}"
  
  # 修改端口
  sed -i -r "s/listen\s+[0-9]+;/listen $new_port;/" "$DEFAULT_SITE_CONFIG"
  
  # 检查 IPv6 地址设置并更新
  if grep -q "listen \[\:\:\]" "$DEFAULT_SITE_CONFIG"; then
    sed -i -r "s/listen\s+\[\:\:\]\:[0-9]+;/listen [::]:$new_port;/" "$DEFAULT_SITE_CONFIG"
  fi

  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}端口修改成功，正在重启 Nginx...${NC}"
    restart_nginx
  else
    echo -e "${RED}Nginx 配置语法错误，端口修改失败。正在恢复备份文件...${NC}"
    cp "$backup_file" "$DEFAULT_SITE_CONFIG"
    echo -e "${YELLOW}已恢复到原始配置${NC}"
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
  echo -e "${YELLOW}配置 HTTPS...${NC}"
  
  # 检查是否已安装 SSL 证书
  if [[ -f "/etc/nginx/ssl/nginx.crt" && -f "/etc/nginx/ssl/nginx.key" ]]; then
    echo -e "${YELLOW}检测到已存在的 SSL 证书${NC}"
    read -p "是否重新生成 SSL 证书？(yes/no): " regen_cert
    if [[ ! "$regen_cert" =~ ^(yes|y)$ ]]; then
      echo -e "${GREEN}保留现有证书${NC}"
    else
      generate_ssl_cert
    fi
  else
    generate_ssl_cert
  fi
  
  # 配置 Nginx 启用 HTTPS
  echo -e "${YELLOW}配置 Nginx 启用 HTTPS...${NC}"
  
  # 备份配置文件
  local backup_file="${DEFAULT_SITE_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$DEFAULT_SITE_CONFIG" "$backup_file" || handle_error "无法备份配置文件" 0
  
  # 检查并修改 Nginx 配置以支持 HTTPS
  local server_name
  server_name=$(grep -E "server_name" "$DEFAULT_SITE_CONFIG" | head -1 | awk '{print $2}' | tr -d ';')
  server_name=${server_name:-_}
  
  cat > "$DEFAULT_SITE_CONFIG" <<EOF
server {
    listen 80;
    server_name $server_name;
    
    # 重定向 HTTP 到 HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $server_name;
    
    ssl_certificate     /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # 安全头配置
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    location / {
        root /CLAY;
        index index.html index.htm;
    }
    
    location /1/ {
        alias /CLAY/1/;
        autoindex on;
        mp4;
        mp4_buffer_size 1m;
        mp4_max_buffer_size 5m;
    }
}
EOF

  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}HTTPS 配置成功，正在重启 Nginx...${NC}"
    restart_nginx
    
    echo -e "${GREEN}HTTPS 已启用！${NC}"
    local port=$(grep -E "listen\s+[0-9]+" "$DEFAULT_SITE_CONFIG" | grep "ssl" | head -1 | grep -oP "\d+")
    port=${port:-443}
    echo -e "您现在可以通过 ${BLUE}https://$(hostname -I | awk '{print $1}'):${port}${NC} 访问网站。"
  else
    echo -e "${RED}HTTPS 配置语法错误，配置失败。正在恢复备份文件...${NC}"
    cp "$backup_file" "$DEFAULT_SITE_CONFIG"
    echo -e "${YELLOW}已恢复到原始配置${NC}"
  fi
}

generate_ssl_cert() {
  echo -e "${YELLOW}生成 SSL 自签名证书...${NC}"
  
  # 安装 OpenSSL（如果需要）
  if ! command -v openssl &> /dev/null; then
    echo -e "${YELLOW}安装 OpenSSL...${NC}"
    case "$PACKAGE_MANAGER" in
      apt) apt install -y openssl ;;
      yum) yum install -y openssl ;;
      zypper) zypper --non-interactive install openssl ;;
      pacman) pacman -Sy --noconfirm openssl ;;
    esac
  fi
  
  # 创建目录存储证书
  mkdir -p /etc/nginx/ssl
  
  # 生成私钥和证书
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/CN=$(hostname)/O=Nginx HTTPS/C=CN" \
    -addext "subjectAltName = DNS:$(hostname),IP:$(hostname -I | awk '{print $1}')"
  
  chmod 400 /etc/nginx/ssl/nginx.key
  chmod 444 /etc/nginx/ssl/nginx.crt
  
  echo -e "${GREEN}SSL 证书生成完成${NC}"
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

check_nginx_status() {
  echo -e "${YELLOW}检查 Nginx 状态...${NC}"
  
  # 检查进程
  if pgrep nginx &>/dev/null; then
    echo -e "${GREEN}Nginx 进程正在运行${NC}"
    echo -e "进程信息：$(ps -ef | grep nginx | grep -v grep | head -1)"
  else
    echo -e "${RED}Nginx 进程未运行${NC}"
    return 1
  fi
  
  # 显示版本
  echo -e "Nginx 版本：$(nginx -v 2>&1)"
  
  # 检查配置
  nginx -t
  
  # 检查端口
  local port=$(grep -E "listen\s+[0-9]+" "$DEFAULT_SITE_CONFIG" | grep -oP "listen\s+\K[0-9]+" | head -1)
  port=${port:-80}
  
  if ss -tuln | grep -q ":$port "; then
    echo -e "${GREEN}Nginx 正在监听端口 $port${NC}"
  else
    echo -e "${RED}警告：Nginx 未在端口 $port 上监听${NC}"
  fi
  
  # 检查已加载模块
  echo -e "${YELLOW}已加载模块：${NC}"
  nginx -V 2>&1 | grep -o -- '--with-[a-zA-Z0-9_]*_module' | sort
  
  # 显示systemd状态
  if command -v systemctl &>/dev/null; then
    echo -e "\n${YELLOW}Systemd 服务状态：${NC}"
    systemctl status nginx | head -10
  fi
  
  # 反馈PHP-FPM状态
  if pgrep php-fpm &>/dev/null; then
    echo -e "\n${YELLOW}检测到 PHP-FPM 正在运行，可能与 Nginx 配合使用${NC}"
  fi
  
  return 0
}

show_help() {
  echo -e "${YELLOW}Nginx 管理脚本帮助${NC}"
  echo -e "用法: $0 [选项]"
  echo -e "选项:"
  echo -e "  -h, --help                显示此帮助信息"
  echo -e "  -i, --install             安装 Nginx（源码编译）"
  echo -e "  -u, --uninstall           卸载 Nginx"
  echo -e "  -s, --start               启动 Nginx"
  echo -e "  -p, --stop                停止 Nginx"
  echo -e "  -r, --restart             重启 Nginx"
  echo -e "  -c, --check               检查 Nginx 状态"
  echo -e "  -https                     配置 HTTPS"
  echo -e "  -port [端口号]             修改 Nginx 端口"
  echo -e "示例:"
  echo -e "  $0 -i        # 安装 Nginx"
  echo -e "  $0 -c        # 检查 Nginx 状态"
  echo -e "  $0 -port 8080 # 修改 Nginx 端口为 8080"
}

parse_arguments() {
  if [[ $# -eq 0 ]]; then
    return 0
  fi
  
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -i|--install)
      detect_os
      install_nginx
      exit $?
      ;;
    -u|--uninstall)
      detect_os
      uninstall_nginx
      exit $?
      ;;
    -s|--start)
      detect_os
      start_nginx
      exit $?
      ;;
    -p|--stop)
      detect_os
      stop_nginx
      exit $?
      ;;
    -r|--restart)
      detect_os
      restart_nginx
      exit $?
      ;;
    -c|--check)
      detect_os
      check_nginx_status
      exit $?
      ;;
    -https)
      detect_os
      configure_https
      exit $?
      ;;
    -port)
      detect_os
      if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
        new_port="$2"
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
          handle_error "无效的端口号。请输入 1-65535 之间的数字。" 1
        fi
        change_port_direct "$new_port"
        exit $?
      else
        handle_error "使用 -port 参数时必须指定有效端口号" 1
      fi
      ;;
    *)
      echo -e "${RED}未知参数：$1${NC}"
      show_help
      exit 1
      ;;
  esac
}

change_port_direct() {
  local new_port="$1"
  local current_port
  current_port=$(grep -E "listen\s+[0-9]+" "$DEFAULT_SITE_CONFIG" | grep -oP "listen\s+\K[0-9]+" | head -1)
  current_port=${current_port:-80}
  
  if [[ "$new_port" == "$current_port" ]]; then
    echo -e "${YELLOW}Nginx 已经运行在端口 ${BLUE}$new_port${NC}，无需修改。${NC}"
    return 0
  fi
  
  echo -e "${YELLOW}修改 Nginx 端口 ${current_port} -> ${new_port}...${NC}"
  
  # 备份配置文件
  local backup_file="${DEFAULT_SITE_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$DEFAULT_SITE_CONFIG" "$backup_file" || handle_error "无法备份配置文件" 0
  
  # 修改端口
  sed -i -r "s/listen\s+[0-9]+;/listen $new_port;/" "$DEFAULT_SITE_CONFIG"
  
  # 检查 IPv6 地址设置并更新
  if grep -q "listen \[\:\:\]" "$DEFAULT_SITE_CONFIG"; then
    sed -i -r "s/listen\s+\[\:\:\]\:[0-9]+;/listen [::]:$new_port;/" "$DEFAULT_SITE_CONFIG"
  fi

  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}端口修改成功，正在重启 Nginx...${NC}"
    restart_nginx
  else
    echo -e "${RED}Nginx 配置语法错误，端口修改失败。正在恢复备份文件...${NC}"
    cp "$backup_file" "$DEFAULT_SITE_CONFIG"
    echo -e "${YELLOW}已恢复到原始配置${NC}"
    return 1
  fi
}

main_menu() {
  clear
  script_info
  echo
  echo "请选择操作："
  echo "1) 安装 Nginx（源码编译）"
  echo "2) 卸载 Nginx"
  echo "3) 启动 Nginx"
  echo "4) 停止 Nginx"
  echo "5) 重启 Nginx"
  echo "6) 修改默认端口"
  echo "7) 修改默认网站根目录为 /CLAY 并创建示例首页"
  echo "8) 配置 HTTPS"
  echo "9) 检查 Nginx 状态"
  echo "0) 退出"
  echo -n "输入选项 [0-9]: "
  read choice
}

main() {
  # 处理命令行参数
  parse_arguments "$@"
  
  # 如果没有命令行参数，显示交互菜单
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
      9) check_nginx_status ;;
      0) echo -e "${YELLOW}退出脚本。${NC}"; exit 0 ;;
      *) echo -e "${RED}无效选项，请重试。${NC}" ;;
    esac
    
    echo
    read -p "按 Enter 键继续..."
  done
}

main "$@"
