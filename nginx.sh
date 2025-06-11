#!/bin/bash

# 脚本版本
SCRIPT_VERSION="1.9"

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

# 函数：输出脚本信息
script_info() {
  echo -e "${BLUE}Nginx 管理脚本 v${SCRIPT_VERSION}${NC}"
  echo "-------------------------"
  echo "本脚本用于管理 Nginx 服务和配置。"
  echo "-------------------------"
}

# 函数：检测操作系统及设置变量
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

# 安装 Nginx
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

# 修改默认端口
change_port() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装，请先安装。${NC}"
    return
  fi

  # 尝试用 ss 查找当前端口，兼容性更好
  current_port=$(ss -tuln | grep -E 'nginx|:80' | awk '{print $5}' | cut -d':' -f2 | head -n1)
  if [[ -z "$current_port" ]]; then
    current_port="80"
  fi

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

  echo -e "${YELLOW}正在修改 Nginx 默认端口为 ${BLUE}$new_port${NC}...${NC}"

  # 只修改默认站点配置文件中的 listen 指令
  sed -i -r "s/listen\s+[0-9]+;/listen $new_port;/" "$DEFAULT_SITE_CONFIG"

  # 检查配置是否正确
  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}端口修改成功，正在重启 Nginx...${NC}"
    restart_nginx
  else
    echo -e "${RED}错误：Nginx 配置语法错误，端口修改失败。请检查配置文件。${NC}"
  fi
}

# 修改默认网站根目录及创建示例首页
change_web_root() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装，请先安装。${NC}"
    return
  fi

  read -p "是否将默认网站根目录更改为 /CLAY 并创建示例首页？（yes/no）：" confirm
  if [[ "$confirm" =~ ^(yes|y)$ ]]; then
    if [[ ! -d "/CLAY" ]]; then
      echo -e "${YELLOW}目录 /CLAY 不存在，正在创建...${NC}"
      mkdir -p /CLAY || { echo -e "${RED}错误：创建目录失败。${NC}"; return; }
    fi

    echo -e "${YELLOW}正在创建示例首页 /CLAY/index.html ...${NC}"
    cat > /CLAY/index.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>欢迎</title>
<style>
  body { font-family: sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; background-color: #f0f0f0; margin: 0; }
  .container { text-align: center; background-color: #fff; padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
  #time { font-size: 2em; color: #333; }
</style>
</head>
<body>
<div class="container">
  <h1>欢迎光临</h1>
  <div id="time"></div>
</div>
<script>
  function updateTime() {
    const now = new Date();
    const h = String(now.getHours()).padStart(2, '0');
    const m = String(now.getMinutes()).padStart(2, '0');
    const s = String(now.getSeconds()).padStart(2, '0');
    document.getElementById('time').textContent = `当前时间：${h}:${m}:${s}`;
  }
  setInterval(updateTime, 1000);
  updateTime();
</script>
</body>
</html>
EOF

    # 修改默认站点配置文件 root 路径
    sed -i -r "s#root\s+[^;]+;#root /CLAY;#" "$DEFAULT_SITE_CONFIG"

    nginx -t
    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}默认网站根目录已修改为 /CLAY，示例首页已创建。${NC}"
      restart_nginx
    else
      echo -e "${RED}错误：Nginx 配置语法错误，根目录修改失败。请检查配置文件。${NC}"
    fi
  else
    echo -e "${YELLOW}取消更改网站根目录。${NC}"
  fi
}

# 配置 HTTPS (SSL)
configure_https() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装，请先安装。${NC}"
    return
  fi

  read -p "是否为网站配置 HTTPS？（yes/no）：" confirm_ssl
  if [[ ! "$confirm_ssl" =~ ^(yes|y)$ ]]; then
    echo -e "${YELLOW}取消配置 HTTPS。${NC}"
    return
  fi

  # 让用户输入域名或 IP
  read -p "请输入您的域名（或服务器 IP，建议使用域名）： " domain
  if [[ -z "$domain" ]]; then
    echo -e "${RED}错误：域名不能为空。${NC}"
    return
  fi

  # 让用户输入证书路径
  read -p "请输入 SSL 证书文件路径（PEM 格式）： " cert_path
  if [[ ! -f "$cert_path" ]]; then
    echo -e "${RED}错误：证书文件不存在。${NC}"
    return
  fi

  read -p "请输入 SSL 私钥文件路径（KEY 格式）： " key_path
  if [[ ! -f "$key_path" ]]; then
    echo -e "${RED}错误：私钥文件不存在。${NC}"
    return
  fi

  read -p "是否启用 HTTP 自动重定向到 HTTPS？（yes/no）：" redirect_http

  # 创建单独的 HTTPS 配置文件，避免直接修改默认配置文件导致混乱
  ssl_conf_file="${SITES_AVAILABLE_DIR}/ssl_${domain}.conf"

  cat > "$ssl_conf_file" <<EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};

    ssl_certificate ${cert_path};
    ssl_certificate_key ${key_path};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    root /CLAY;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

  # 启用该站点配置（如果有 sites-enabled 目录）
  if [[ -d "$SITES_ENABLED_DIR" ]]; then
    ln -sf "$ssl_conf_file" "${SITES_ENABLED_DIR}/ssl_${domain}.conf"
  fi

  # 配置 HTTP 重定向（修改默认站点配置文件）
  if [[ "$redirect_http" =~ ^(yes|y)$ ]]; then
    # 备份默认配置文件
    cp "$DEFAULT_SITE_CONFIG" "${DEFAULT_SITE_CONFIG}.bak"

    # 修改默认配置文件，添加重定向 server 块
    cat > "$DEFAULT_SITE_CONFIG" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    return 301 https://\$host\$request_uri;
}
EOF
  fi

  # 检查配置语法
  nginx -t
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}HTTPS 配置成功，正在重启 Nginx...${NC}"
    restart_nginx
  else
    echo -e "${RED}错误：Nginx 配置语法错误，请检查证书路径和配置文件。${NC}"
    # 恢复默认配置文件（如果备份存在）
    [[ -f "${DEFAULT_SITE_CONFIG}.bak" ]] && mv -f "${DEFAULT_SITE_CONFIG}.bak" "$DEFAULT_SITE_CONFIG"
  fi
}

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
    6) change_port ;;
    7) change_web_root ;;
    8) configure_https ;;
    0) echo -e "${YELLOW}正在退出...${NC}" && exit 0 ;;
    *) echo -e "${RED}无效选择，请重试。${NC}" ;;
  esac
done
