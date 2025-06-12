#!/bin/bash
# Nginx全自动管理脚本 v2.0 - 支持全Linux发行版和HTTPS智能配置

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化日志文件
LOG_FILE="/var/log/nginx-manager.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 错误处理
set -eo pipefail
trap "echo -e '${RED}脚本异常退出! 查看日志: $LOG_FILE${NC}'" ERR

# 系统检测函数
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VER=$(lsb_release -sr)
    elif [ -f /etc/centos-release ]; then
        OS=centos
        VER=$(sed 's/.* \([0-9]\).*/\1/' /etc/centos-release)
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    echo -e "${BLUE}检测到系统: $OS $VER${NC}"
}

# 包管理器检测
detect_pkg_manager() {
    case $OS in
        ubuntu|debian|linuxmint)
            PKG_MANAGER="apt"
            INSTALL_CMD="apt update && apt install -y"
            REMOVE_CMD="apt purge -y"
            ;;
        centos|rhel|fedora|amazon|rocky)
            if [ "$OS" = "centos" ] && [ "$VER" -lt 8 ]; then
                PKG_MANAGER="yum"
                INSTALL_CMD="yum install -y"
                REMOVE_CMD="yum remove -y"
            else
                PKG_MANAGER="dnf"
                INSTALL_CMD="dnf install -y"
                REMOVE_CMD="dnf remove -y"
            fi
            ;;
        alpine)
            PKG_MANAGER="apk"
            INSTALL_CMD="apk add"
            REMOVE_CMD="apk del"
            ;;
        arch|manjaro|endeavouros)
            PKG_MANAGER="pacman"
            INSTALL_CMD="pacman -Syu --noconfirm"
            REMOVE_CMD="pacman -R --noconfirm"
            ;;
        opensuse*|sled|sles)
            PKG_MANAGER="zypper"
            INSTALL_CMD="zypper install -y"
            REMOVE_CMD="zypper remove -y"
            ;;
        *)
            echo -e "${RED}不支持的Linux发行版: $OS${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${BLUE}使用包管理器: $PKG_MANAGER${NC}"
}

# 证书路径自动配置
auto_cert_path() {
    local domain=$1
    local cert_dir="/etc/nginx/ssl"
    
    # 优先检测Let's Encrypt证书
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        SSL_CERT="/etc/letsencrypt/live/$domain/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$domain/privkey.pem"
        echo -e "${GREEN}使用Let's Encrypt证书: $SSL_CERT${NC}"
    elif [ -f "$cert_dir/$domain.crt" ]; then
        SSL_CERT="$cert_dir/$domain.crt"
        SSL_KEY="$cert_dir/$domain.key"
        echo -e "${GREEN}使用已存在的证书: $SSL_CERT${NC}"
    else
        echo -e "${YELLOW}未找到现有证书，生成自签名证书${NC}"
        generate_selfsigned_cert "$domain"
    fi
}

# 生成自签名证书
generate_selfsigned_cert() {
    local domain=$1
    mkdir -p /etc/nginx/ssl
    
    echo -e "${BLUE}生成自签名证书...${NC}"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/$domain.key \
        -out /etc/nginx/ssl/$domain.crt \
        -subj "/CN=$domain" 2>/dev/null
        
    chmod 600 /etc/nginx/ssl/$domain.key
    chmod 644 /etc/nginx/ssl/$domain.crt
    
    SSL_CERT="/etc/nginx/ssl/$domain.crt"
    SSL_KEY="/etc/nginx/ssl/$domain.key"
    
    echo -e "${GREEN}自签名证书已生成: $SSL_CERT${NC}"
}

# 防火墙配置
configure_firewall() {
    echo -e "${BLUE}配置防火墙...${NC}"
    
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 'Nginx Full'
        ufw reload
        echo -e "${GREEN}UFW防火墙已配置${NC}"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        echo -e "${GREEN}Firewalld防火墙已配置${NC}"
    elif command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        if command -v iptables-save >/dev/null 2>&1; then
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/iptables.rules
        fi
        echo -e "${GREEN}iptables防火墙已配置${NC}"
    else
        echo -e "${YELLOW}未检测到防火墙，跳过配置${NC}"
    fi
}

# Nginx安装函数
install_nginx() {
    echo -e "${GREEN}开始安装Nginx...${NC}"
    
    case $PKG_MANAGER in
        apt)
            apt update
            apt install -y nginx
            ;;
        yum)
            if [ "$OS" = "centos" ]; then
                yum install -y epel-release
            fi
            yum install -y nginx
            ;;
        dnf)
            dnf install -y nginx
            ;;
        pacman)
            pacman -Syu --noconfirm nginx
            ;;
        apk)
            apk add nginx
            ;;
        zypper)
            zypper install -y nginx
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Nginx安装成功!${NC}"
        systemctl start nginx
        systemctl enable nginx
        configure_firewall
        
        # 创建默认主页
        echo "<h1>Nginx已成功安装</h1><p>由自动管理脚本部署</p>" > /usr/share/nginx/html/index.html
    else
        echo -e "${RED}Nginx安装失败!${NC}"
        exit 1
    fi
}

# Nginx卸载函数
uninstall_nginx() {
    echo -e "${YELLOW}确认要卸载Nginx吗? [y/N]: ${NC}"
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}开始卸载Nginx...${NC}"
        
        # 停止服务
        systemctl stop nginx
        systemctl disable nginx
        
        # 卸载软件包
        case $PKG_MANAGER in
            apt)
                apt purge -y nginx nginx-common nginx-full
                apt autoremove -y
                ;;
            yum|dnf)
                $PKG_MANAGER remove -y nginx
                ;;
            pacman)
                pacman -R --noconfirm nginx
                ;;
            apk)
                apk del nginx
                ;;
            zypper)
                zypper remove -y nginx
                ;;
        esac
        
        # 清理配置文件
        rm -rf /etc/nginx /var/log/nginx /var/cache/nginx /usr/share/nginx
        
        # 重载systemd
        systemctl daemon-reload
        
        echo -e "${GREEN}Nginx已完全卸载${NC}"
    else
        echo -e "${BLUE}已取消卸载操作${NC}"
    fi
}

# HTTPS配置函数
configure_https() {
    echo -e "${GREEN}HTTPS配置向导${NC}"
    read -p "请输入域名: " domain
    
    if [ -z "$domain" ]; then
        echo -e "${RED}错误: 域名不能为空${NC}"
        return 1
    fi
    
    # 检查Nginx是否安装
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "${RED}错误: Nginx未安装${NC}"
        return 1
    fi
    
    # 自动配置证书路径
    auto_cert_path "$domain"
    
    # 生成Nginx配置
    local conf_dir
    
    # 检测配置目录
    if [ -d "/etc/nginx/conf.d" ]; then
        conf_dir="/etc/nginx/conf.d"
    elif [ -d "/etc/nginx/sites-available" ]; then
        conf_dir="/etc/nginx/sites-available"
    else
        mkdir -p /etc/nginx/conf.d
        conf_dir="/etc/nginx/conf.d"
    fi
    
    local conf_file="$conf_dir/${domain}.conf"
    
    echo -e "${BLUE}创建Nginx配置: $conf_file${NC}"
    
    cat > "$conf_file" <<EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domain;
    
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    
    # 安全头设置
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        root /var/www/$domain;
        index index.html;
    }
}
EOF

    # 创建网站目录
    echo -e "${BLUE}创建网站目录: /var/www/$domain${NC}"
    mkdir -p "/var/www/$domain"
    echo "<h1>$domain 已成功启用HTTPS</h1><p>配置时间: $(date)</p>" > "/var/www/$domain/index.html"
    
    # 如果使用sites-available目录，创建符号链接到sites-enabled
    if [ -d "/etc/nginx/sites-available" ] && [ -d "/etc/nginx/sites-enabled" ]; then
        ln -sf "$conf_file" "/etc/nginx/sites-enabled/$(basename "$conf_file")"
    fi
    
    # 检查配置并重启Nginx
    echo -e "${BLUE}检查Nginx配置...${NC}"
    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}HTTPS配置已完成，网站已启用${NC}"
        echo -e "${GREEN}现在可以通过 https://$domain 访问您的网站${NC}"
    else
        echo -e "${RED}Nginx配置有误，请检查配置文件${NC}"
        return 1
    fi
}

# 服务管理函数
restart_nginx() {
    echo -e "${BLUE}重启Nginx服务...${NC}"
    systemctl restart nginx
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Nginx已重启${NC}"
    else
        echo -e "${RED}重启Nginx失败${NC}"
    fi
}

stop_nginx() {
    echo -e "${BLUE}停止Nginx服务...${NC}"
    systemctl stop nginx
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Nginx已停止${NC}"
    else
        echo -e "${RED}停止Nginx失败${NC}"
    fi
}

# 信息显示函数
show_info() {
    echo -e "${BLUE}=== Nginx状态信息 ===${NC}"
    
    # 检查Nginx是否安装
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "${RED}Nginx未安装${NC}"
        return 1
    fi
    
    # 获取Nginx版本
    NGINX_VER=$(nginx -v 2>&1 | cut -d/ -f2)
    echo -e "${GREEN}Nginx版本: $NGINX_VER${NC}"
    
    # 检查Nginx服务状态
    echo -e "${GREEN}运行状态: $(systemctl is-active nginx)${NC}"
    echo -e "${GREEN}启动配置: $(systemctl is-enabled nginx)${NC}"
    
    # 检查配置文件
    echo -e "${GREEN}配置文件:${NC}"
    nginx -T 2>/dev/null | grep -E '^# configuration file' | uniq
    
    # 检查端口监听情况
    echo -e "${GREEN}监听端口:${NC}"
    ss -tulpn | grep nginx
    
    # 检查网站目录
    echo -e "${GREEN}网站目录:${NC}"
    find /var/www -type d -maxdepth 1 -mindepth 1 2>/dev/null
    
    # 检查HTTPS配置
    echo -e "${GREEN}HTTPS配置:${NC}"
    find /etc/nginx -name "*.conf" -type f -exec grep -l "ssl_certificate" {} \; | while read -r file; do
        domain=$(basename "$file" | sed 's/\.conf$//')
        echo "域名: $domain, 配置文件: $file"
        grep -E "ssl_certificate|ssl_certificate_key" "$file" | sed 's/;//'
    done
    
    echo -e "${BLUE}=====================${NC}"
}

# 主菜单
main_menu() {
    clear
    echo -e "${GREEN}===================================${NC}"
    echo -e "${GREEN}=== Nginx一键管理脚本 v2.0 ===${NC}"
    echo -e "${GREEN}===================================${NC}"
    echo -e "${BLUE}1. 安装Nginx${NC}"
    echo -e "${BLUE}2. 卸载Nginx${NC}"
    echo -e "${BLUE}3. 重启Nginx${NC}"
    echo -e "${BLUE}4. 停止Nginx${NC}"
    echo -e "${BLUE}5. 配置HTTPS${NC}"
    echo -e "${BLUE}6. 显示Nginx信息${NC}"
    echo -e "${RED}0. 退出${NC}"
    echo
    echo -n -e "${YELLOW}请输入选择: ${NC}"
}

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 请使用root权限运行脚本${NC}"
        exit 1
    fi
}

# 主逻辑
check_root
detect_system
detect_pkg_manager

while true; do
    main_menu
    read -r choice
    
    case $choice in
        1) install_nginx ;;
        2) uninstall_nginx ;;
        3) restart_nginx ;;
        4) stop_nginx ;;
        5) configure_https ;;
        6) show_info ;;
        0) 
           echo -e "${BLUE}感谢使用Nginx一键管理脚本，再见！${NC}"
           exit 0 
           ;;
        *) echo -e "${RED}无效选项，请重新选择!${NC}" ;;
    esac
    
    echo
    read -n 1 -s -r -p "按任意键继续..."
    echo
done
