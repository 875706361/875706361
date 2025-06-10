#!/bin/bash

# 脚本版本
SCRIPT_VERSION="1.8"

# 颜色代码定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 函数：输出脚本信息
script_info() {
  echo -e "${BLUE}Nginx 管理脚本 v${SCRIPT_VERSION}${NC}"
  echo "-------------------------"
  echo "本脚本用于管理 Nginx 服务和配置。"
  echo "-------------------------"
}

# 函数：检测操作系统并设置包管理器及相关路径
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

# 函数：检查 Nginx 是否已安装
is_nginx_installed() {
  command -v nginx >/dev/null 2>&1
}

# 函数：安装 Nginx
install_nginx() {
  echo -e "${YELLOW}正在安装 Nginx...${NC}"
  if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    echo -e "${YELLOW}更新软件包列表...${NC}"
    sudo apt update
    echo -e "${YELLOW}使用 apt 安装 Nginx 及其依赖...${NC}"
    sudo apt install -y nginx
  elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
    echo -e "${YELLOW}使用 yum 安装 Nginx 及其依赖...${NC}"
    sudo yum install -y nginx
  elif [[ "$PACKAGE_MANAGER" == "zypper" ]]; then
    echo -e "${YELLOW}使用 zypper 安装 Nginx 及其依赖...${NC}"
    sudo zypper --non-interactive install nginx
  elif [[ "$PACKAGE_MANAGER" == "pacman" ]]; then
    echo -e "${YELLOW}使用 pacman 安装 Nginx 及其依赖...${NC}"
    sudo pacman -S --noconfirm nginx
  fi

  if is_nginx_installed; then
    echo -e "${GREEN}Nginx 安装成功。${NC}"
    start_nginx
  else
    echo -e "${RED}错误：Nginx 安装失败。请检查您的网络连接或软件源配置。${NC}"
  fi
}

# 函数：卸载 Nginx
uninstall_nginx() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 当前未安装。${NC}"
    return
  fi

  echo -e "${YELLOW}正在卸载 Nginx...${NC}"
  if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    echo -e "${YELLOW}移除 Nginx 软件包...${NC}"
    sudo apt purge -y nginx nginx-common nginx-core
    echo -e "${YELLOW}移除不再需要的依赖包...${NC}"
    sudo apt autoremove -y
  elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
    echo -e "${YELLOW}移除 Nginx 软件包...${NC}"
    sudo yum remove -y nginx
  elif [[ "$PACKAGE_MANAGER" == "zypper" ]]; then
    echo -e "${YELLOW}移除 Nginx 软件包...${NC}"
    sudo zypper --non-interactive remove nginx
  elif [[ "$PACKAGE_MANAGER" == "pacman" ]]; then
    echo -e "${YELLOW}移除 Nginx 软件包...${NC}"
    sudo pacman -R --noconfirm nginx
  fi
  echo -e "${GREEN}Nginx 卸载成功。${NC}"
}

# 函数：启动 Nginx
start_nginx() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装，请先安装。${NC}"
    return
  fi
  echo -e "${YELLOW}正在启动 Nginx 服务...${NC}"
  sudo "$SERVICE_MANAGER" start nginx
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 启动成功。${NC}"
  else
    echo -e "${RED}错误：启动 Nginx 失败。请检查您的 Nginx 配置或系统日志。${NC}"
  fi
}

# 函数：停止 Nginx
stop_nginx() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装。${NC}"
    return
  fi
  echo -e "${YELLOW}正在停止 Nginx 服务...${NC}"
  sudo "$SERVICE_MANAGER" stop nginx
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 停止成功。${NC}"
  else
    echo -e "${RED}错误：停止 Nginx 失败。${NC}"
  fi
}

# 函数：重启 Nginx
restart_nginx() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装。${NC}"
    return
  fi
  echo -e "${YELLOW}正在重启 Nginx 服务...${NC}"
  sudo "$SERVICE_MANAGER" restart nginx
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 重启成功。${NC}"
  else
    echo -e "${RED}错误：重启 Nginx 失败。请检查您的 Nginx 配置或系统日志。${NC}"
  fi
}

# 函数：修改 Nginx 默认端口
change_port() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装，请先安装。${NC}"
    return
  fi

  # 获取当前监听端口
  current_port=$(sudo netstat -tuln | grep LISTEN | grep nginx | awk '{print $4}' | cut -d':' -f2 | head -n 1)
  if [[ -z "$current_port" ]]; then
    current_port="80" # 默认值
  fi

  read -p "请输入新的 Nginx 端口号（当前端口：${BLUE}$current_port${NC}，默认：80）：" new_port
  if [[ -z "$new_port" ]]; then
    new_port="80"
  fi

  if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}错误：无效的端口号。${NC}"
    return
  fi

  if [[ "$new_port" -eq "$current_port" ]]; then
    echo -e "${YELLOW}Nginx 已经运行在端口 ${BLUE}$new_port${NC}，无需修改。${NC}"
    return
  fi

  echo -e "${YELLOW}正在将 Nginx 端口修改为 ${BLUE}$new_port${NC}，修改配置文件：${BLUE}$CONFIG_FILE${NC} ...${NC}"

  # 使用 sed 替换 listen 指令 - 这可能需要根据不同的配置进行调整
  sudo sed -i "s/listen[[:space:]]*[0-9]\+;/listen $new_port;/" "$CONFIG_FILE"

  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Nginx 主配置文件中的端口已成功尝试修改为 ${BLUE}$new_port${NC}。${NC}"
    echo -e "${YELLOW}请重启 Nginx 以应用更改。${NC}"
  else
    echo -e "${RED}错误：修改 Nginx 主配置文件中的端口失败。请检查文件权限或配置格式。${NC}"
  fi
}

# 函数：修改 Nginx 默认网站根目录
change_web_root() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装，请先安装。${NC}"
    return
  fi

  read -p "是否将 Nginx 默认网站根目录更改为 /CLAY 并创建示例首页？（yes/no）：" confirm
  if [[ "$confirm" == "yes" || "$confirm" == "y" ]]; then
    # 检查 /CLAY 是否存在，不存在则创建
    if [[ ! -d "/CLAY" ]]; then
      echo -e "${YELLOW}目录 /CLAY 不存在，正在创建...${NC}"
      sudo mkdir -p /CLAY
      if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误：创建目录 /CLAY 失败，请使用 sudo 运行脚本或检查权限。${NC}"
        return
      fi
    fi

    # 创建一个简单的 index.html 文件，包含居中显示和动态时钟
    echo -e "${YELLOW}正在创建示例首页文件 /CLAY/index.html ...${NC}"
    cat > /CLAY/index.html <<EOL
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>欢迎</title>
    <style>
        body {
            font-family: sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background-color: #f0f0f0;
            margin: 0;
        }
        .container {
            text-align: center;
            background-color: #fff;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }
        #time {
            font-size: 2em;
            color: #333;
        }
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
            const hours = String(now.getHours()).padStart(2, '0');
            const minutes = String(now.getMinutes()).padStart(2, '0');
            const seconds = String(now.getSeconds()).padStart(2, '0');
            document.getElementById('time').textContent = \`当前时间：\${hours}:\${minutes}:\${seconds}\`;
        }

        setInterval(updateTime, 1000);
        updateTime(); // 页面加载时立即显示时间
    </script>
</body>
</html>
EOL

    if [[ $? -ne 0 ]]; then
      echo -e "${RED}警告：创建首页文件 /CLAY/index.html 失败，请检查权限。${NC}"
    fi

    echo -e "${YELLOW}正在修改 Nginx 默认网站根目录到 /CLAY，修改配置文件：${BLUE}$DEFAULT_SITE_CONFIG${NC} ...${NC}"
    sudo sed -i "s/root[[:space:]]\+.\+;/root \/CLAY;/" "$DEFAULT_SITE_CONFIG"

    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}Nginx 默认网站根目录已成功修改为 /CLAY。${NC}"
      echo -e "${YELLOW}已在 /CLAY 目录下创建了一个简单的示例首页文件 index.html，包含动态时间显示。${NC}"
      echo -e "${YELLOW}正在重启 Nginx 服务以应用更改...${NC}"
      restart_nginx
    else
      echo -e "${RED}错误：修改 Nginx 默认站点配置文件中的根目录失败。请检查文件权限或配置格式。${NC}"
    fi
  else
    echo -e "${YELLOW}取消更改网站根目录。${NC}"
  fi
}

# 函数：配置 HTTPS (SSL)
configure_https() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 未安装，请先安装。${NC}"
    return
  fi

  read -p "是否要为您的网站配置 HTTPS 访问？（yes/no）：" confirm_ssl
  if [[ "$confirm_ssl" == "yes" || "$confirm_ssl" == "y" ]]; then
    read -p "是否要将 HTTP 流量自动重定向到 HTTPS？（yes/no）：" redirect_http
    echo -e "${YELLOW}正在配置 HTTPS 访问...${NC}"

    # 获取服务器 IP 地址
    server_ip=$(curl -s ifconfig.me)
    if [[ -z "$server_ip" ]]; then
      echo -e "${RED}错误：无法获取服务器 IP 地址，请检查网络连接。${NC}"
      return
    fi
    echo -e "${GREEN}获取到的服务器 IP 地址：${BLUE}$server_ip${NC}"

    # 构建 HTTPS 服务器块配置
    HTTPS_CONFIG="\nserver {\n    listen 443 ssl http2;\n    listen [::]:443 ssl http2;\n    server_name $server_ip;\n\n    ssl_certificate /etc/x-ui/888888666.xyz_chain.pem;\n    ssl_certificate_key /etc/x-ui/888888666.xyz.key;\n\n    ssl_protocols TLSv1.2 TLSv1.3;\n    ssl_prefer_server_ciphers off;\n\n    location / {\n        root /CLAY;\n        index index.html;\n    }\n}\n"

    # 将 HTTPS 配置添加到默认的站点配置文件中
    sudo sed -i "$ a $HTTPS_CONFIG" "$DEFAULT_SITE_CONFIG"

    if [[ "$redirect_http" == "yes" || "$redirect_http" == "y" ]]; then
      echo -e "${YELLOW}配置 HTTP 重定向到 HTTPS...${NC}"
      # 查找监听 80 的 server 块并添加重定向
      HTTP_BLOCK_START=$(grep -n "^server {$" "$DEFAULT_SITE_CONFIG" | grep "listen 80" | cut -d':' -f1)
      if [[ -n "$HTTP_BLOCK_START" ]]; then
        HTTP_BLOCK_END=$(awk "/^}/" "$DEFAULT_SITE_CONFIG" | tail -n +"$HTTP_BLOCK_START" | head -n 1 | cut -d':' -f1)
        if [[ -n "$HTTP_BLOCK_END" ]]; then
          # 在 HTTP server 块的末尾添加 return 指令
          sudo sed -i "${HTTP_BLOCK_END}i\    return 301 https://\$server_ip\$request_uri;\\n" "$DEFAULT_SITE_CONFIG"
        else
          echo -e "${RED}警告：无法准确找到 HTTP server 块的结束位置，请手动检查重定向配置。${NC}"
        fi
      else
        echo -e "${RED}警告：无法找到监听 80 的 HTTP server 块，请手动添加重定向配置。${NC}"
      fi
    fi

    echo -e "${YELLOW}HTTPS 配置已添加到 ${BLUE}$DEFAULT_SITE_CONFIG${NC}。\n正在重启 Nginx 服务...${NC}"
    restart_nginx
  else
    echo -e "${YELLOW}取消配置 HTTPS 访问。${NC}"
  fi
}

# 主菜单函数
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

# 主脚本执行
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
    *) echo -e "${RED}无效的选择，请重试。${NC}" ;;
  esac
done
