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
  
  # 检测实际配置文件位置
  find_nginx_config_file
  
  echo -e "${GREEN}使用包管理器：${BLUE}$PACKAGE_MANAGER${NC}"
  echo -e "${GREEN}Nginx配置文件：${BLUE}$DEFAULT_SITE_CONFIG${NC}"
}

# 查找Nginx配置文件的实际位置
find_nginx_config_file() {
  # 检查默认路径是否存在
  if [[ -f "$DEFAULT_SITE_CONFIG" ]]; then
    return 0
  fi
  
  # 如果默认路径不存在，尝试其他常见位置
  local possible_locations=(
    "/etc/nginx/sites-available/default"
    "/etc/nginx/conf.d/default.conf"
    "/etc/nginx/default.conf"
    "/etc/nginx/conf.d/default"
    "/etc/nginx/sites-enabled/default"
    "/etc/nginx/nginx.conf"
  )
  
  for location in "${possible_locations[@]}"; do
    if [[ -f "$location" ]]; then
      DEFAULT_SITE_CONFIG="$location"
      echo -e "${YELLOW}找到Nginx配置文件：${DEFAULT_SITE_CONFIG}${NC}"
      return 0
    fi
  done
  
  # 如果找不到现有配置文件，使用nginx.conf作为备用
  if [[ -f "/etc/nginx/nginx.conf" ]]; then
    DEFAULT_SITE_CONFIG="/etc/nginx/nginx.conf"
    echo -e "${YELLOW}使用主Nginx配置文件：${DEFAULT_SITE_CONFIG}${NC}"
    return 0
  fi
  
  # 如果仍然找不到，创建一个新的配置文件
  if [[ -d "/etc/nginx/conf.d" ]]; then
    DEFAULT_SITE_CONFIG="/etc/nginx/conf.d/default.conf"
  elif [[ -d "/etc/nginx/sites-available" ]]; then
    DEFAULT_SITE_CONFIG="/etc/nginx/sites-available/default"
  else
    mkdir -p /etc/nginx/conf.d
    DEFAULT_SITE_CONFIG="/etc/nginx/conf.d/default.conf"
  fi
  
  echo -e "${YELLOW}未找到现有的Nginx配置文件，将创建：${DEFAULT_SITE_CONFIG}${NC}"
  
  # 创建一个基本配置
  cat > "$DEFAULT_SITE_CONFIG" <<'EOF'
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
    }
}
EOF

  return 0
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
  
  # 询问用户是否确认卸载
  read -p "确定要完全卸载Nginx及其所有配置文件吗? (yes/no): " confirm
  if [[ ! "$confirm" =~ ^(yes|y)$ ]]; then
    echo -e "${YELLOW}卸载已取消${NC}"
    return 0
  fi

  # 停止Nginx服务
  echo -e "${YELLOW}停止Nginx服务...${NC}"
  systemctl stop nginx 2>/dev/null
  service nginx stop 2>/dev/null
  killall -9 nginx 2>/dev/null
  
  # 禁用Nginx服务
  echo -e "${YELLOW}禁用Nginx服务...${NC}"
  systemctl disable nginx 2>/dev/null
  
  # 根据不同的包管理器卸载已安装的包
  echo -e "${YELLOW}使用包管理器卸载Nginx包...${NC}"
  local removed=0
  if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    apt purge -y nginx nginx-common nginx-core nginx-full 2>/dev/null
    apt autoremove -y 2>/dev/null
    removed=1
  elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
    yum remove -y nginx 2>/dev/null
    removed=1
  elif [[ "$PACKAGE_MANAGER" == "zypper" ]]; then
    zypper --non-interactive remove nginx 2>/dev/null
    removed=1
  elif [[ "$PACKAGE_MANAGER" == "pacman" ]]; then
    pacman -R --noconfirm nginx 2>/dev/null
    removed=1
  fi
  
  # 移除编译安装的Nginx可执行文件和相关资源
  echo -e "${YELLOW}移除编译安装的Nginx文件...${NC}"
  if [[ -f /usr/sbin/nginx ]]; then
    rm -f /usr/sbin/nginx
    echo -e "已删除: ${BLUE}/usr/sbin/nginx${NC}"
  fi
  
  # 清理Nginx配置目录
  echo -e "${YELLOW}清理Nginx配置目录...${NC}"
  if [[ -d /etc/nginx ]]; then
    read -p "是否删除所有Nginx配置文件？这将删除 /etc/nginx 目录下的所有文件 (yes/no): " del_config
    if [[ "$del_config" =~ ^(yes|y)$ ]]; then
      rm -rf /etc/nginx
      echo -e "已删除: ${BLUE}/etc/nginx${NC}"
    else
      echo -e "${YELLOW}保留Nginx配置文件${NC}"
    fi
  fi
  
  # 清理日志目录
  echo -e "${YELLOW}清理Nginx日志目录...${NC}"
  if [[ -d /var/log/nginx ]]; then
    rm -rf /var/log/nginx
    echo -e "已删除: ${BLUE}/var/log/nginx${NC}"
  fi
  
  # 删除systemd服务文件
  echo -e "${YELLOW}删除系统服务文件...${NC}"
  if [[ -f /lib/systemd/system/nginx.service ]]; then
    rm -f /lib/systemd/system/nginx.service
    systemctl daemon-reload
    echo -e "已删除: ${BLUE}/lib/systemd/system/nginx.service${NC}"
  fi
  
  # 删除编译目录
  echo -e "${YELLOW}清理编译目录...${NC}"
  if [[ -d /usr/local/src/nginx_build ]]; then
    rm -rf /usr/local/src/nginx_build
    echo -e "已删除: ${BLUE}/usr/local/src/nginx_build${NC}"
  fi
  
  # 删除其他常见的Nginx文件
  echo -e "${YELLOW}搜索并删除其他Nginx文件...${NC}"
  local nginx_dirs=(
    "/var/cache/nginx"
    "/var/www/html"
    "/usr/lib/nginx"
    "/usr/share/nginx"
    "/usr/local/nginx"
    "/etc/default/nginx"
    "/etc/logrotate.d/nginx"
  )
  
  for dir in "${nginx_dirs[@]}"; do
    if [[ -d "$dir" || -f "$dir" ]]; then
      echo -e "发现: ${BLUE}$dir${NC}"
      read -p "是否删除此Nginx关联文件/目录? (yes/no): " del_dir
      if [[ "$del_dir" =~ ^(yes|y)$ ]]; then
        rm -rf "$dir"
        echo -e "已删除: ${BLUE}$dir${NC}"
      else
        echo -e "${YELLOW}保留: $dir${NC}"
      fi
    fi
  done
  
  # 删除用户自定义的CLAY目录（如果存在）
  if [[ -d /CLAY ]]; then
    read -p "是否删除 /CLAY 目录及其中的内容? (yes/no): " del_clay
    if [[ "$del_clay" =~ ^(yes|y)$ ]]; then
      rm -rf /CLAY
      echo -e "已删除: ${BLUE}/CLAY${NC}"
    else
      echo -e "${YELLOW}保留: /CLAY${NC}"
    fi
  fi
  
  # 清理系统缓存
  echo -e "${YELLOW}更新系统缓存...${NC}"
  ldconfig 2>/dev/null
  
  # 检查卸载结果
  if ! command -v nginx &>/dev/null; then
    echo -e "${GREEN}Nginx 已成功卸载！${NC}"
  else
    echo -e "${RED}警告：Nginx 可能未完全卸载，请检查系统${NC}"
    echo -e "Nginx可执行文件路径: $(which nginx 2>/dev/null || echo '未找到')"
  fi
  
  echo -e "${GREEN}卸载过程完成。${NC}"
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
    # 确保配置文件存在
    if [[ ! -f "$DEFAULT_SITE_CONFIG" ]]; then
      echo -e "${YELLOW}Nginx配置文件 $DEFAULT_SITE_CONFIG 不存在，尝试查找或创建...${NC}"
      find_nginx_config_file
    fi
    
    # 确保目录存在
    if [[ ! -d "/CLAY" ]]; then
      mkdir -p /CLAY || { handle_error "创建目录 /CLAY 失败" 0; return; }
    fi

    # 备份配置文件
    local backup_file="${DEFAULT_SITE_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    if ! cp "$DEFAULT_SITE_CONFIG" "$backup_file"; then
      echo -e "${RED}无法备份配置文件 $DEFAULT_SITE_CONFIG${NC}"
    else
      echo -e "${GREEN}配置文件已备份为：${backup_file}${NC}"
    fi

    # 创建示例首页
    cat > /CLAY/index.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><title>欢迎</title></head>
<body><h1>欢迎光临</h1></body>
</html>
EOF

    chmod 644 /CLAY/index.html
    
    # 如果是主配置文件，处理方式不同
    if [[ "$DEFAULT_SITE_CONFIG" == "/etc/nginx/nginx.conf" ]]; then
      # 创建额外的配置文件
      local site_config="/etc/nginx/conf.d/default.conf"
      mkdir -p /etc/nginx/conf.d
      
      cat > "$site_config" <<EOF
server {
    listen 80;
    server_name localhost;
    
    location / {
        root /CLAY;
        index index.html index.htm;
    }
}
EOF
      
      # 确保主配置文件包含conf.d目录
      if ! grep -q "include.*conf.d" "/etc/nginx/nginx.conf"; then
        # 查找http块结束位置
        local http_end_line=$(grep -n "}" "/etc/nginx/nginx.conf" | grep -B1 "http" | head -1 | cut -d: -f1)
        if [[ -n "$http_end_line" ]]; then
          # 在http块结束前插入include指令
          sed -i "${http_end_line}i\\    include /etc/nginx/conf.d/*.conf;" "/etc/nginx/nginx.conf"
          echo -e "${GREEN}已将conf.d目录添加到主配置中${NC}"
        fi
      fi
      
      DEFAULT_SITE_CONFIG="$site_config"
      echo -e "${GREEN}已创建新的网站配置文件：${DEFAULT_SITE_CONFIG}${NC}"
    else
      # 修改配置文件中的root指令
      sed -i -r "s#root\s+[^;]+;#root /CLAY;#" "$DEFAULT_SITE_CONFIG" 2>/dev/null || {
        echo -e "${YELLOW}无法修改root指令，尝试重新创建配置...${NC}"
        cat > "$DEFAULT_SITE_CONFIG" <<EOF
server {
    listen 80;
    server_name localhost;
    
    location / {
        root /CLAY;
        index index.html index.htm;
    }
}
EOF
      }
    fi

    nginx -t
    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}网站根目录修改成功，重启 Nginx...${NC}"
      restart_nginx
    else
      echo -e "${RED}配置语法错误，根目录修改失败。${NC}"
      if [[ -f "$backup_file" ]]; then
        echo -e "${YELLOW}恢复备份文件...${NC}"
        cp -f "$backup_file" "$DEFAULT_SITE_CONFIG"
      fi
    fi
  else
    echo -e "${YELLOW}取消修改网站根目录。${NC}"
  fi
}

configure_https() {
  echo -e "${YELLOW}配置 HTTPS...${NC}"
  
  # 检查是否已安装 Nginx
  if ! command -v nginx &>/dev/null; then
    handle_error "未检测到Nginx安装，请先安装Nginx" 0
    return 1
  fi
  
  # 检查Nginx是否支持SSL模块
  if ! nginx -V 2>&1 | grep -q "with-http_ssl_module"; then
    echo -e "${RED}警告：当前Nginx可能未编译SSL模块支持${NC}"
    read -p "是否继续配置HTTPS？(yes/no): " continue_ssl
    if [[ ! "$continue_ssl" =~ ^(yes|y)$ ]]; then
      echo -e "${YELLOW}HTTPS配置已取消${NC}"
      return 0
    fi
  fi
  
  # 检查是否已安装 SSL 证书
  if [[ -f "/etc/nginx/ssl/nginx.crt" && -f "/etc/nginx/ssl/nginx.key" ]]; then
    echo -e "${YELLOW}检测到已存在的 SSL 证书${NC}"
    read -p "是否重新生成 SSL 证书？(yes/no): " regen_cert
    if [[ ! "$regen_cert" =~ ^(yes|y)$ ]]; then
      echo -e "${GREEN}保留现有证书${NC}"
    else
      generate_ssl_cert || {
        echo -e "${RED}SSL证书生成失败，无法配置HTTPS${NC}"
        return 1
      }
    fi
  else
    generate_ssl_cert || {
      echo -e "${RED}SSL证书生成失败，无法配置HTTPS${NC}"
      return 1
    }
  fi
  
  # 确保证书权限正确且Nginx可以读取
  if [[ -f "/etc/nginx/ssl/nginx.key" ]]; then
    # 获取Nginx用户
    local nginx_user=$(grep -E "^user" /etc/nginx/nginx.conf 2>/dev/null | awk '{print $2}' | sed 's/;$//')
    nginx_user=${nginx_user:-"www-data"}
    
    echo -e "${YELLOW}设置证书权限，确保Nginx用户($nginx_user)可访问...${NC}"
    chmod 600 /etc/nginx/ssl/nginx.key
    chmod 644 /etc/nginx/ssl/nginx.crt
    
    # 尝试设置所有者，但不强制要求成功
    chown $nginx_user:$nginx_user /etc/nginx/ssl/nginx.key 2>/dev/null || true
    chown $nginx_user:$nginx_user /etc/nginx/ssl/nginx.crt 2>/dev/null || true
  fi
  
  # 检查配置文件是否存在
  if [[ ! -f "$DEFAULT_SITE_CONFIG" ]]; then
    echo -e "${YELLOW}Nginx配置文件 $DEFAULT_SITE_CONFIG 不存在，尝试查找或创建...${NC}"
    find_nginx_config_file
  fi
  
  # 备份配置文件
  local backup_file="${DEFAULT_SITE_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  if ! cp "$DEFAULT_SITE_CONFIG" "$backup_file" 2>/dev/null; then
    echo -e "${YELLOW}无法备份配置文件 $DEFAULT_SITE_CONFIG，尝试直接创建新配置...${NC}"
  else
    echo -e "${GREEN}配置文件已备份为：${backup_file}${NC}"
  fi
  
  # 确保目录存在
  mkdir -p $(dirname "$DEFAULT_SITE_CONFIG")
  
  # 检查并修改 Nginx 配置以支持 HTTPS
  local server_name
  server_name=$(grep -E "server_name" "$DEFAULT_SITE_CONFIG" 2>/dev/null | head -1 | grep -o "server_name[[:space:]]*[^;]*" | sed 's/server_name[[:space:]]*//g' || echo "localhost")
  server_name=${server_name// /} # 移除多余空格
  [[ -z "$server_name" ]] && server_name="localhost" # 确保有默认值
  
  echo -e "${YELLOW}设置服务器名称为：${server_name}${NC}"
  
  # 创建HTTPS配置文件
  local https_config_path="$DEFAULT_SITE_CONFIG"
  
  # 如果是主配置文件，使用特殊处理
  if [[ "$DEFAULT_SITE_CONFIG" == "/etc/nginx/nginx.conf" ]]; then
    https_config_path="/etc/nginx/conf.d/https.conf"
    mkdir -p /etc/nginx/conf.d
  fi
  
  cat > "$https_config_path" <<EOF
# HTTP配置 - 重定向到HTTPS
server {
    listen 80;
    server_name $server_name;
    
    # 重定向 HTTP 到 HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS配置
server {
    listen 443 ssl;
    server_name $server_name;
    
    ssl_certificate     /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # 安全头配置
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    
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

  # 确保配置在主配置文件中被包含
  if [[ "$https_config_path" != "/etc/nginx/nginx.conf" && "$https_config_path" != "$DEFAULT_SITE_CONFIG" ]]; then
    local main_conf="/etc/nginx/nginx.conf"
    
    # 如果主配置文件存在
    if [[ -f "$main_conf" ]]; then
      echo -e "${YELLOW}更新主配置文件，确保包含HTTPS配置...${NC}"
      
      # 检查是否已包含该配置
      if ! grep -q "include.*$https_config_path" "$main_conf" 2>/dev/null; then
        # 检查是否包含conf.d目录
        if ! grep -q "include.*conf.d" "$main_conf" 2>/dev/null; then
          # 尝试在http块结束前添加include指令
          local http_end_line
          http_end_line=$(grep -n "}" "$main_conf" | grep -B1 "http" | head -1 | cut -d: -f1)
          
          if [[ -n "$http_end_line" ]]; then
            # 在http块结束前插入include指令
            sed -i "${http_end_line}i\\    include /etc/nginx/conf.d/*.conf;" "$main_conf"
            echo -e "${GREEN}已将conf.d目录添加到主配置中${NC}"
          else
            # 如果找不到http块，尝试在文件末尾添加
            echo -e "\nhttp {\n    include /etc/nginx/conf.d/*.conf;\n}" >> "$main_conf"
            echo -e "${YELLOW}无法找到http块，已在文件末尾添加配置${NC}"
          fi
        fi
      fi
    fi
  fi
  
  # 创建示例SSL首页
  if [[ -d /CLAY ]]; then
    mkdir -p /CLAY/1 2>/dev/null
    
    if [[ ! -f /CLAY/index.html ]]; then
      cat > /CLAY/index.html <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><title>HTTPS已启用</title>
<style>body{font-family:Arial,sans-serif;text-align:center;margin-top:50px;}</style>
</head>
<body>
<h1>HTTPS已成功配置</h1>
<p>恭喜，您的Nginx服务器已成功配置HTTPS！</p>
</body>
</html>
EOF
      chmod 644 /CLAY/index.html
    fi
  fi

  # 测试配置
  echo -e "${YELLOW}测试 Nginx 配置...${NC}"
  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}HTTPS 配置成功，正在重启 Nginx...${NC}"
    restart_nginx
    
    # 验证HTTPS是否实际启用
    sleep 2
    if ss -tuln | grep -q ":443 "; then
      # 获取服务器IP地址
      local server_ip
      server_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "127.0.0.1")
      
      echo -e "${GREEN}HTTPS 已成功启用！${NC}"
      echo -e "您现在可以通过 ${BLUE}https://$server_ip${NC} 或 ${BLUE}https://$server_name${NC} 访问网站。"
    else
      echo -e "${RED}警告：HTTPS 似乎未成功启用，无法检测到端口 443 监听${NC}"
      echo -e "${YELLOW}请检查：${NC}"
      echo -e "1. 端口443是否被其他程序占用"
      echo -e "2. 防火墙是否阻止了443端口"
      echo -e "3. 查看日志: ${BLUE}tail /var/log/nginx/error.log${NC}"
    fi
  else
    echo -e "${RED}HTTPS 配置语法错误，配置失败。${NC}"
    if [[ -f "$backup_file" ]]; then
      echo -e "${YELLOW}正在恢复备份文件...${NC}"
      cp "$backup_file" "$DEFAULT_SITE_CONFIG"
      echo -e "${YELLOW}已恢复到原始配置${NC}"
    fi
    
    # 输出具体的错误信息帮助诊断
    echo -e "${RED}配置错误详细信息:${NC}"
    nginx -t
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
  
  # 检查OpenSSL版本
  local openssl_version=$(openssl version | grep -oP '(?<=OpenSSL )[0-9.]+' || echo "0.0.0")
  local major_version=$(echo "$openssl_version" | cut -d. -f1)
  local minor_version=$(echo "$openssl_version" | cut -d. -f2)
  
  echo -e "${YELLOW}检测到 OpenSSL 版本: $openssl_version${NC}"
  
  # 获取主机名和IP地址（提高兼容性）
  local hostname_str=$(hostname 2>/dev/null || echo "localhost")
  local ip_address=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "127.0.0.1")
  
  if [[ "$major_version" -ge 1 && "$minor_version" -ge 1 ]]; then
    # OpenSSL 1.1.0及以上版本支持-addext参数
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/nginx.key \
      -out /etc/nginx/ssl/nginx.crt \
      -subj "/CN=$hostname_str/O=Nginx HTTPS/C=CN" \
      -addext "subjectAltName = DNS:$hostname_str,IP:$ip_address" || {
        echo -e "${RED}生成SSL证书失败，尝试使用兼容模式${NC}"
        # 回退到旧版本兼容模式
        generate_ssl_cert_legacy "$hostname_str" "$ip_address"
        return
      }
  else
    # 对于旧版本OpenSSL，使用兼容方式
    generate_ssl_cert_legacy "$hostname_str" "$ip_address"
  fi
  
  # 设置适当权限
  chmod 600 /etc/nginx/ssl/nginx.key
  chmod 644 /etc/nginx/ssl/nginx.crt
  
  # 验证证书是否正确生成
  if [[ ! -f /etc/nginx/ssl/nginx.crt || ! -f /etc/nginx/ssl/nginx.key ]]; then
    echo -e "${RED}SSL证书文件未正确生成${NC}"
    return 1
  fi
  
  echo -e "${GREEN}SSL 证书生成完成${NC}"
}

# 为旧版OpenSSL添加兼容模式函数
generate_ssl_cert_legacy() {
  local hostname_str="$1"
  local ip_address="$2"
  
  echo -e "${YELLOW}使用兼容模式为旧版OpenSSL生成证书...${NC}"
  
  # 创建配置文件
  local ssl_conf="/tmp/openssl-san.cnf"
  cat > "$ssl_conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $hostname_str
O = Nginx HTTPS
C = CN

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $hostname_str
IP.1 = $ip_address
EOF

  # 使用配置文件生成证书
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -config "$ssl_conf"
  
  # 清理临时文件
  rm -f "$ssl_conf"
  return $?
}

configure_clay_video_access() {
  echo -e "${YELLOW}配置 Nginx 支持访问 /CLAY/1 目录的视频播放...${NC}"

  # 确保配置文件存在
  if [[ ! -f "$DEFAULT_SITE_CONFIG" ]]; then
    echo -e "${YELLOW}Nginx配置文件 $DEFAULT_SITE_CONFIG 不存在，尝试查找或创建...${NC}"
    find_nginx_config_file
  fi

  # 备份配置文件
  local backup_file="${DEFAULT_SITE_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  if ! cp "$DEFAULT_SITE_CONFIG" "$backup_file"; then
    echo -e "${RED}无法备份配置文件 $DEFAULT_SITE_CONFIG${NC}"
    echo -e "${YELLOW}尝试直接创建新的配置文件...${NC}"
  else
    echo -e "${GREEN}配置文件已备份为：${backup_file}${NC}"
  fi

  # 确保CLAY目录存在
  mkdir -p /CLAY/1 2>/dev/null
  
  # 检查是否是主配置文件，如果是，需要特殊处理
  if [[ "$DEFAULT_SITE_CONFIG" == "/etc/nginx/nginx.conf" ]]; then
    # 创建额外的配置文件
    local site_config="/etc/nginx/conf.d/clay-video.conf"
    mkdir -p /etc/nginx/conf.d
    
    cat > "$site_config" <<EOF
server {
    listen 80;
    server_name localhost;
    
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
    
    # 确保主配置文件包含conf.d目录
    if ! grep -q "include.*conf.d" "/etc/nginx/nginx.conf"; then
      # 查找http块结束位置
      local http_end_line=$(grep -n "}" "/etc/nginx/nginx.conf" | grep -B1 "http" | head -1 | cut -d: -f1)
      if [[ -n "$http_end_line" ]]; then
        # 在http块结束前插入include指令
        sed -i "${http_end_line}i\\    include /etc/nginx/conf.d/*.conf;" "/etc/nginx/nginx.conf"
        echo -e "${GREEN}已将conf.d目录添加到主配置中${NC}"
      fi
    fi
    
    echo -e "${GREEN}已创建视频访问配置文件：${site_config}${NC}"
  else
    # 移除已有的视频配置（如果存在）
    sed -i '/location \/1\//,/\}/d' "$DEFAULT_SITE_CONFIG" 2>/dev/null

    # 添加新的视频配置
    sed -i "/server {/a \\
    location /1/ {\\
        alias /CLAY/1/;\\
        autoindex on;\\
        mp4;\\
        mp4_buffer_size 1m;\\
        mp4_max_buffer_size 5m;\\
    }" "$DEFAULT_SITE_CONFIG" 2>/dev/null
  fi

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
    chmod 644 /CLAY/index.html
    # 尝试设置正确的所有者，但如果失败也不影响
    chown www-data:www-data /CLAY/index.html 2>/dev/null || true
  else
    echo -e "${YELLOW}目录 /CLAY 不存在，示例首页未创建，请自行创建。${NC}"
  fi

  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}配置语法正确，重启 Nginx...${NC}"
    restart_nginx
  else
    echo -e "${RED}配置语法错误，恢复备份文件。${NC}"
    if [[ -f "$backup_file" ]]; then
      cp -f "$backup_file" "$DEFAULT_SITE_CONFIG"
    fi
  fi
}

check_nginx_status() {
  echo -e "${YELLOW}检查 Nginx 状态...${NC}"
  
  # 检查 Nginx 是否已安装
  if ! command -v nginx &>/dev/null; then
    echo -e "${RED}Nginx 未安装${NC}"
    return 1
  fi
  
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
  
  # 确保配置文件存在
  if [[ ! -f "$DEFAULT_SITE_CONFIG" ]]; then
    echo -e "${YELLOW}Nginx配置文件 $DEFAULT_SITE_CONFIG 不存在，尝试查找...${NC}"
    find_nginx_config_file
  fi
  
  # 检查端口
  echo -e "${YELLOW}Nginx 监听的端口:${NC}"
  local nginx_ports=$(ss -tuln | grep LISTEN | grep -E '(nginx|:80|:443)' | awk '{print $5}' | cut -d: -f2 | sort -u)
  
  if [[ -z "$nginx_ports" ]]; then
    echo -e "${RED}未找到 Nginx 监听的端口${NC}"
  else
    for port in $nginx_ports; do
      echo -e "  ${GREEN}端口 $port${NC}"
    done
  fi
  
  # 检查是否启用了 HTTPS
  if ss -tuln | grep -q ":443 "; then
    echo -e "${GREEN}HTTPS 已启用 (端口 443)${NC}"
    
    # 检查SSL证书
    if [[ -f "/etc/nginx/ssl/nginx.crt" ]]; then
      echo -e "${GREEN}SSL证书信息:${NC}"
      openssl x509 -noout -subject -dates -in /etc/nginx/ssl/nginx.crt 2>/dev/null || echo -e "${RED}无法读取SSL证书信息${NC}"
    else
      echo -e "${YELLOW}未找到SSL证书文件${NC}"
    fi
  else
    echo -e "${YELLOW}HTTPS 未启用${NC}"
  fi
  
  # 检查已加载模块
  echo -e "\n${YELLOW}已加载模块：${NC}"
  nginx -V 2>&1 | grep -o -- '--with-[a-zA-Z0-9_]*_module' | sort
  
  # 显示systemd状态
  if command -v systemctl &>/dev/null; then
    echo -e "\n${YELLOW}Systemd 服务状态：${NC}"
    systemctl status nginx | head -10
  elif command -v service &>/dev/null; then
    echo -e "\n${YELLOW}服务状态：${NC}"
    service nginx status
  fi
  
  # 检查配置文件路径
  echo -e "\n${YELLOW}Nginx 配置文件位置：${NC}"
  echo -e "主配置文件: $(nginx -V 2>&1 | grep -o 'conf-path=[^ ]*' | cut -d= -f2)"
  echo -e "网站配置文件: $DEFAULT_SITE_CONFIG"
  
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
  local current_port=""
  
  # 确保配置文件存在
  if [[ ! -f "$DEFAULT_SITE_CONFIG" ]]; then
    echo -e "${YELLOW}Nginx配置文件 $DEFAULT_SITE_CONFIG 不存在，尝试查找或创建...${NC}"
    find_nginx_config_file
  fi
  
  # 获取当前端口
  current_port=$(grep -E "listen\s+[0-9]+" "$DEFAULT_SITE_CONFIG" 2>/dev/null | grep -oP "listen\s+\K[0-9]+" | head -1)
  
  # 如果找不到端口配置，检查是否有其他配置文件包含端口信息
  if [[ -z "$current_port" ]]; then
    for conf_file in /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/* /etc/nginx/sites-available/*; do
      if [[ -f "$conf_file" ]]; then
        local found_port=$(grep -E "listen\s+[0-9]+" "$conf_file" 2>/dev/null | grep -oP "listen\s+\K[0-9]+" | head -1)
        if [[ -n "$found_port" ]]; then
          current_port=$found_port
          DEFAULT_SITE_CONFIG=$conf_file
          echo -e "${YELLOW}在 $conf_file 中找到监听端口 $current_port${NC}"
          break
        fi
      fi
    done
  fi
  
  current_port=${current_port:-80}
  
  if [[ "$new_port" == "$current_port" ]]; then
    echo -e "${YELLOW}Nginx 已经运行在端口 ${BLUE}$new_port${NC}，无需修改。${NC}"
    return 0
  fi
  
  echo -e "${YELLOW}修改 Nginx 端口 ${current_port} -> ${new_port}...${NC}"
  
  # 备份配置文件
  local backup_file="${DEFAULT_SITE_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  if ! cp "$DEFAULT_SITE_CONFIG" "$backup_file" 2>/dev/null; then
    echo -e "${RED}无法备份配置文件 $DEFAULT_SITE_CONFIG${NC}"
    echo -e "${YELLOW}尝试直接修改...${NC}"
  else
    echo -e "${GREEN}配置文件已备份为：${backup_file}${NC}"
  fi
  
  # 如果是主配置文件，需要特殊处理
  if [[ "$DEFAULT_SITE_CONFIG" == "/etc/nginx/nginx.conf" ]]; then
    # 创建或修改默认站点配置
    local site_config="/etc/nginx/conf.d/default.conf"
    mkdir -p /etc/nginx/conf.d
    
    if [[ -f "$site_config" ]]; then
      # 修改现有站点配置
      sed -i -r "s/listen\s+[0-9]+;/listen $new_port;/" "$site_config" 2>/dev/null
      
      # 检查 IPv6 地址设置并更新
      if grep -q "listen \[\:\:\]" "$site_config" 2>/dev/null; then
        sed -i -r "s/listen\s+\[\:\:\]\:[0-9]+;/listen [::]:$new_port;/" "$site_config" 2>/dev/null
      fi
    else
      # 创建新的站点配置
      cat > "$site_config" <<EOF
server {
    listen $new_port;
    server_name localhost;
    
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
    }
}
EOF
      # 确保主配置文件包含conf.d目录
      if ! grep -q "include.*conf.d" "/etc/nginx/nginx.conf" 2>/dev/null; then
        local http_end_line=$(grep -n "}" "/etc/nginx/nginx.conf" 2>/dev/null | grep -B1 "http" | head -1 | cut -d: -f1)
        if [[ -n "$http_end_line" ]]; then
          sed -i "${http_end_line}i\\    include /etc/nginx/conf.d/*.conf;" "/etc/nginx/nginx.conf" 2>/dev/null
          echo -e "${GREEN}已将conf.d目录添加到主配置中${NC}"
        fi
      fi
    fi
    DEFAULT_SITE_CONFIG="$site_config"
  else
    # 修改端口
    sed -i -r "s/listen\s+[0-9]+;/listen $new_port;/" "$DEFAULT_SITE_CONFIG" 2>/dev/null
    
    # 检查 IPv6 地址设置并更新
    if grep -q "listen \[\:\:\]" "$DEFAULT_SITE_CONFIG" 2>/dev/null; then
      sed -i -r "s/listen\s+\[\:\:\]\:[0-9]+;/listen [::]:$new_port;/" "$DEFAULT_SITE_CONFIG" 2>/dev/null
    fi
  fi

  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}端口修改成功，正在重启 Nginx...${NC}"
    restart_nginx
  else
    echo -e "${RED}Nginx 配置语法错误，端口修改失败。${NC}"
    if [[ -f "$backup_file" ]]; then
      echo -e "${YELLOW}正在恢复备份文件...${NC}"
      cp -f "$backup_file" "$DEFAULT_SITE_CONFIG"
      echo -e "${YELLOW}已恢复到原始配置${NC}"
    fi
    return 1
  fi
}

# 在主函数中添加一个版本和环境信息展示
show_environment() {
  echo -e "\n${BLUE}系统环境信息:${NC}"
  echo -e "操作系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
  echo -e "内核版本: $(uname -r)"
  echo -e "CPU架构: $(uname -m)"
  echo -e "可用内存: $(free -h | grep Mem | awk '{print $4}')"
  echo -e "可用磁盘空间: $(df -h / | grep / | awk '{print $4}')"
  
  if command -v nginx &>/dev/null; then
    echo -e "Nginx版本: $(nginx -v 2>&1)"
  else
    echo -e "Nginx: ${RED}未安装${NC}"
  fi
  
  echo -e "${YELLOW}脚本版本: v${SCRIPT_VERSION}${NC}"
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
  show_environment
  
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
