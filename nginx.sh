#!/bin/bash
# Nginx全自动管理脚本 v4.0 - 支持全Linux发行版，自动卸载防火墙，显示网站目录信息

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化日志文件
LOG_FILE="/var/log/nginx-manager.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# 错误处理
set -eo pipefail
trap "echo -e '${RED}脚本异常退出! 查看日志: $LOG_FILE${NC}'" ERR

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}请使用root权限运行此脚本${NC}"
        exit 1
    fi
}

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
        ubuntu|debian|linuxmint|kali)
            PKG_MANAGER="apt"
            INSTALL_CMD="apt update && apt install -y"
            REMOVE_CMD="apt purge -y"
            ;;
        centos|rhel|fedora|amazon|rocky|alma|ol)
            if [ -n "$VER" ] && [ "$VER" -ge 8 ]; then
                PKG_MANAGER="dnf"
                INSTALL_CMD="dnf install -y"
                REMOVE_CMD="dnf remove -y"
            else
                PKG_MANAGER="yum"
                INSTALL_CMD="yum install -y"
                REMOVE_CMD="yum remove -y"
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
        void)
            PKG_MANAGER="xbps"
            INSTALL_CMD="xbps-install -y"
            REMOVE_CMD="xbps-remove -y"
            ;;
        *)
            echo -e "${RED}不支持的Linux发行版: $OS${NC}"
            exit 1
            ;;
    esac
    echo -e "${BLUE}使用包管理器: $PKG_MANAGER${NC}"
}

# 自动检测并卸载防火墙
detect_remove_firewall() {
    echo -e "${BLUE}检测并卸载防火墙...${NC}"
    
    local fw_removed=0
    
    # 检测常见防火墙软件
    if command -v ufw >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到UFW防火墙，正在卸载...${NC}"
        ufw disable
        $REMOVE_CMD ufw
        fw_removed=1
    fi
    
    if command -v firewall-cmd >/dev/null 2>&1 || systemctl list-unit-files | grep -q firewalld; then
        echo -e "${YELLOW}检测到firewalld防火墙，正在卸载...${NC}"
        systemctl stop firewalld
        systemctl disable firewalld
        $REMOVE_CMD firewalld
        fw_removed=1
    fi
    
    # 检测iptables服务
    if systemctl list-unit-files | grep -q iptables; then
        echo -e "${YELLOW}检测到iptables服务，正在禁用...${NC}"
        systemctl stop iptables
        systemctl disable iptables
        if [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
            $REMOVE_CMD iptables-services
        fi
        fw_removed=1
    fi
    
    # 检测nftables
    if command -v nft >/dev/null 2>&1 || systemctl list-unit-files | grep -q nftables; then
        echo -e "${YELLOW}检测到nftables防火墙，正在卸载...${NC}"
        systemctl stop nftables
        systemctl disable nftables
        $REMOVE_CMD nftables
        fw_removed=1
    fi
    
    if [ $fw_removed -eq 1 ]; then
        echo -e "${GREEN}已卸载所有检测到的防火墙软件${NC}"
    else
        echo -e "${GREEN}未检测到防火墙软件${NC}"
    fi
    
    # 清除所有iptables规则
    if command -v iptables >/dev/null 2>&1; then
        echo -e "${BLUE}清除所有iptables规则...${NC}"
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -t nat -F
        iptables -t mangle -F
        iptables -F
        iptables -X
        echo -e "${GREEN}已清除所有iptables规则${NC}"
    fi
}

# 证书路径自动配置
auto_cert_path() {
    local domain=$1
    local cert_dir="/etc/nginx/ssl"
    
    # 创建SSL目录
    mkdir -p "$cert_dir"
    
    # 优先检测Let's Encrypt证书
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        SSL_CERT="/etc/letsencrypt/live/$domain/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$domain/privkey.pem"
        echo -e "${GREEN}使用Let's Encrypt证书: $SSL_CERT${NC}"
    elif [ -f "$cert_dir/$domain.crt" ] && [ -f "$cert_dir/$domain.key" ]; then
        SSL_CERT="$cert_dir/$domain.crt"
        SSL_KEY="$cert_dir/$domain.key"
        echo -e "${GREEN}使用已存在的证书: $SSL_CERT${NC}"
    else
        echo -e "${YELLOW}未找到现有证书，生成自签名证书...${NC}"
        generate_selfsigned_cert "$domain"
    fi
}

# 生成自签名证书
generate_selfsigned_cert() {
    local domain=$1
    local cert_dir="/etc/nginx/ssl"
    
    mkdir -p "$cert_dir"
    
    echo -e "${BLUE}正在生成自签名证书...${NC}"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$cert_dir/$domain.key" \
        -out "$cert_dir/$domain.crt" \
        -subj "/CN=$domain" \
        -addext "subjectAltName=DNS:$domain"
    
    # 设置正确的权限
    chmod 600 "$cert_dir/$domain.key"
    chmod 644 "$cert_dir/$domain.crt"
    
    SSL_CERT="$cert_dir/$domain.crt"
    SSL_KEY="$cert_dir/$domain.key"
    
    echo -e "${GREEN}自签名证书生成完成:${NC}"
    echo -e "证书路径: $SSL_CERT"
    echo -e "私钥路径: $SSL_KEY"
}

# 安全配置函数
secure_nginx_config() {
    local nginx_conf="/etc/nginx/nginx.conf"
    
    echo -e "${BLUE}应用Nginx安全配置...${NC}"
    
    # 备份配置文件
    cp "$nginx_conf" "$nginx_conf.bak"
    
    # 隐藏服务器版本信息
    if ! grep -q "server_tokens off" "$nginx_conf"; then
        sed -i '/http {/a \    server_tokens off;' "$nginx_conf"
    fi
    
    # 禁用目录列表
    if ! grep -q "autoindex off" "$nginx_conf"; then
        sed -i '/http {/a \    autoindex off;' "$nginx_conf"
    fi
    
    # 设置安全头
    if ! grep -q "X-Frame-Options" "$nginx_conf"; then
        sed -i '/http {/a \    add_header X-Frame-Options "SAMEORIGIN";' "$nginx_conf"
        sed -i '/http {/a \    add_header X-Content-Type-Options "nosniff";' "$nginx_conf"
        sed -i '/http {/a \    add_header X-XSS-Protection "1; mode=block";' "$nginx_conf"
    fi
    
    # 设置客户端超时
    if ! grep -q "client_body_timeout" "$nginx_conf"; then
        sed -i '/http {/a \    client_body_timeout 10;' "$nginx_conf"
        sed -i '/http {/a \    client_header_timeout 10;' "$nginx_conf"
        sed -i '/http {/a \    keepalive_timeout 65;' "$nginx_conf"
        sed -i '/http {/a \    send_timeout 10;' "$nginx_conf"
    fi
    
    # 限制缓冲区大小
    if ! grep -q "client_body_buffer_size" "$nginx_conf"; then
        sed -i '/http {/a \    client_body_buffer_size 1k;' "$nginx_conf"
        sed -i '/http {/a \    client_header_buffer_size 1k;' "$nginx_conf"
        sed -i '/http {/a \    client_max_body_size 10m;' "$nginx_conf"
    fi
    
    echo -e "${GREEN}安全配置已应用: 隐藏版本号/禁用目录列表/安全头${NC}"
}

# 生成安全默认页面
generate_safe_index() {
    local index_path="$1"
    local dir_path=$(dirname "$index_path")
    
    # 确保目录存在
    mkdir -p "$dir_path"
    
    cat > "$index_path" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Welcome</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            text-align: center; 
            padding: 50px; 
            background-color: #f8f9fa;
            color: #333;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            border-radius: 5px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #0056b3; 
            margin-bottom: 20px;
        }
        p { 
            color: #555; 
            line-height: 1.5;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome</h1>
        <p>Server is running normally</p>
    </div>
</body>
</html>
EOF
    chmod 644 "$index_path"
    echo -e "${GREEN}已生成安全默认页面: $index_path${NC}"
}

# Nginx安装函数
install_nginx() {
    echo -e "${GREEN}开始安装Nginx...${NC}"
    
    # 安装前检查
    if command -v nginx >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到Nginx已安装, 版本: $(nginx -v 2>&1 | cut -d/ -f2)${NC}"
        read -p "是否继续安装/升级? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}安装已取消${NC}"
            return
        fi
    fi
    
    # 检测并卸载防火墙
    detect_remove_firewall
    
    # 根据不同系统安装Nginx
    case $PKG_MANAGER in
        apt)
            apt update
            apt install -y nginx
            ;;
        yum)
            # 添加EPEL仓库
            if ! rpm -qa | grep -q epel-release; then
                yum install -y epel-release
            fi
            yum install -y nginx
            ;;
        dnf)
            # 添加EPEL仓库
            if ! rpm -qa | grep -q epel-release; then
                dnf install -y epel-release
            fi
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
        xbps)
            xbps-install -y nginx
            ;;
    esac
    
    # 检查安装结果
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "${RED}Nginx安装失败!${NC}"
        return 1
    fi
    
    # 启动Nginx服务
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable nginx
        systemctl start nginx
    elif command -v service >/dev/null 2>&1; then
        service nginx start
        # 添加开机自启
        if [ -f /etc/init.d/nginx ]; then
            update-rc.d nginx defaults
        fi
    else
        echo -e "${YELLOW}无法找到systemctl或service命令, 请手动启动Nginx${NC}"
        nginx
    fi
    
    # 应用安全配置
    secure_nginx_config
    
    # 生成安全默认页面
    generate_safe_index "/usr/share/nginx/html/index.html"
    generate_safe_index "/var/www/html/index.html"
    
    echo -e "${GREEN}Nginx安装完成并应用安全配置${NC}"
    echo -e "${BLUE}Nginx版本: $(nginx -v 2>&1 | cut -d/ -f2)${NC}"
}

# Nginx卸载函数
uninstall_nginx() {
    echo -e "${YELLOW}警告: 即将卸载Nginx及其所有配置文件${NC}"
    read -p "确认卸载? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}卸载已取消${NC}"
        return
    fi
    
    echo -e "${BLUE}停止Nginx服务...${NC}"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop nginx
        systemctl disable nginx
    elif command -v service >/dev/null 2>&1; then
        service nginx stop
        # 移除开机自启
        if [ -f /etc/init.d/nginx ]; then
            update-rc.d -f nginx remove
        fi
    else
        killall nginx 2>/dev/null || true
    fi
    
    echo -e "${BLUE}卸载Nginx软件包...${NC}"
    case $PKG_MANAGER in
        apt)
            apt purge -y nginx nginx-common nginx-full nginx-core
            apt autoremove -y
            ;;
        yum|dnf)
            $PKG_MANAGER remove -y nginx
            ;;
        pacman)
            pacman -Rns --noconfirm nginx
            ;;
        apk)
            apk del nginx
            ;;
        zypper)
            zypper remove -y nginx
            ;;
        xbps)
            xbps-remove -y nginx
            ;;
    esac
    
    echo -e "${BLUE}删除Nginx配置文件...${NC}"
    rm -rf /etc/nginx /usr/share/nginx /var/log/nginx /var/cache/nginx
    
    echo -e "${BLUE}删除Nginx用户...${NC}"
    if id -u nginx >/dev/null 2>&1; then
        userdel -r nginx 2>/dev/null || true
    fi
    
    # 刷新systemd配置
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
    fi
    
    echo -e "${GREEN}Nginx已完全卸载${NC}"
}

# HTTPS配置函数
configure_https() {
    echo -e "${BLUE}配置HTTPS访问...${NC}"
    
    # 验证Nginx安装
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "${RED}错误: 未检测到Nginx安装, 请先安装Nginx${NC}"
        return 1
    fi
    
    read -p "请输入域名: " domain
    if [ -z "$domain" ]; then
        echo -e "${RED}错误: 域名不能为空${NC}"
        return 1
    fi
    
    # 检查域名格式
    if ! echo "$domain" | grep -qP '(?=^.{4,253}$)(^(?:[a-zA-Z0-9](?:(?:[a-zA-Z0-9\-]){0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$)'; then
        echo -e "${YELLOW}警告: 域名格式可能不正确, 继续操作...${NC}"
    fi
    
    # 自动配置证书路径
    auto_cert_path "$domain"
    
    # 确定配置目录
    local conf_dir
    if [ -d "/etc/nginx/conf.d" ]; then
        conf_dir="/etc/nginx/conf.d"
    elif [ -d "/etc/nginx/sites-available" ]; then
        conf_dir="/etc/nginx/sites-available"
    else
        mkdir -p "/etc/nginx/conf.d"
        conf_dir="/etc/nginx/conf.d"
    fi
    
    # 生成Nginx HTTPS配置
    local conf_file="$conf_dir/${domain}.conf"
    
    echo -e "${BLUE}创建Nginx HTTPS配置: $conf_file${NC}"
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
    
    # SSL配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    
    # 安全头设置
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; img-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'; frame-src 'none'; object-src 'none'";
    
    # 日志设置
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
    
    # 网站根目录
    root /var/www/$domain;
    index index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    # 创建网站目录和默认页面
    mkdir -p "/var/www/$domain"
    generate_safe_index "/var/www/$domain/index.html"
    
    # 对于Debian/Ubuntu系统, 创建软链接到sites-enabled
    if [ -d "/etc/nginx/sites-available" ] && [ -d "/etc/nginx/sites-enabled" ]; then
        ln -sf "$conf_file" "/etc/nginx/sites-enabled/$(basename "$conf_file")"
    fi
    
    # 检查配置
    echo -e "${BLUE}检查Nginx配置...${NC}"
    nginx -t
    
    # 重新加载Nginx
    echo -e "${BLUE}重新加载Nginx...${NC}"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl reload nginx
    elif command -v service >/dev/null 2>&1; then
        service nginx reload
    else
        nginx -s reload
    fi
    
    echo -e "${GREEN}HTTPS配置完成!${NC}"
    echo -e "${BLUE}网站URL: https://$domain${NC}"
    echo -e "${BLUE}网站目录: /var/www/$domain${NC}"
    echo -e "${BLUE}配置文件: $conf_file${NC}"
    
    # 证书提醒
    if [[ "$SSL_CERT" == *"/etc/nginx/ssl/"* ]]; then
        echo -e "${YELLOW}注意: 当前使用的是自签名证书, 浏览器会显示安全警告${NC}"
        echo -e "${YELLOW}建议使用Let's Encrypt等服务获取受信任的SSL证书${NC}"
    fi
}

# 查找所有网站目录
find_website_roots() {
    echo -e "${BLUE}正在查找所有网站目录...${NC}"
    
    local roots=()
    
    # 检查常见网站目录
    local common_dirs=("/var/www" "/usr/share/nginx/html" "/srv/www" "/var/www/html")
    for dir in "${common_dirs[@]}"; do
        if [ -d "$dir" ]; then
            roots+=("$dir")
        fi
    done
    
    # 从Nginx配置中查找root指令
    if command -v nginx >/dev/null 2>&1; then
        local config_roots=$(grep -r "root" /etc/nginx/ 2>/dev/null | grep -v "#" | sed -e 's/.*root\s\+\([^;]\+\);.*/\1/' | sort | uniq)
        if [ -n "$config_roots" ]; then
            while IFS= read -r line; do
                roots+=("$line")
            done <<< "$config_roots"
        fi
    fi
    
    # 从sites-enabled中查找
    if [ -d "/etc/nginx/sites-enabled" ]; then
        local enabled_sites=$(find /etc/nginx/sites-enabled -type f -o -type l)
        for site in $enabled_sites; do
            local site_root=$(grep "root" "$site" | grep -v "#" | head -1 | sed -e 's/.*root\s\+\([^;]\+\);.*/\1/')
            if [ -n "$site_root" ]; then
                roots+=("$site_root")
            fi
        done
    fi
    
    # 从conf.d中查找
    if [ -d "/etc/nginx/conf.d" ]; then
        local conf_sites=$(find /etc/nginx/conf.d -name "*.conf" -type f)
        for site in $conf_sites; do
            local site_root=$(grep "root" "$site" | grep -v "#" | head -1 | sed -e 's/.*root\s\+\([^;]\+\);.*/\1/')
            if [ -n "$site_root" ]; then
                roots+=("$site_root")
            fi
        done
    fi
    
    # 去重并排序
    local unique_roots=$(printf '%s\n' "${roots[@]}" | sort | uniq)
    
    echo "$unique_roots"
}

# 获取网站域名和目录映射
get_website_mappings() {
    echo -e "${BLUE}获取网站域名和目录映射...${NC}"
    
    local mappings=()
    
    # 从sites-enabled中查找
    if [ -d "/etc/nginx/sites-enabled" ]; then
        local enabled_sites=$(find /etc/nginx/sites-enabled -type f -o -type l)
        for site in $enabled_sites; do
            local server_names=$(grep -E "server_name" "$site" | grep -v "#" | sed -e 's/.*server_name\s\+\([^;]\+\);.*/\1/')
            local site_root=$(grep "root" "$site" | grep -v "#" | head -1 | sed -e 's/.*root\s\+\([^;]\+\);.*/\1/')
            
            if [ -n "$server_names" ] && [ -n "$site_root" ]; then
                mappings+=("域名: $server_names -> 目录: $site_root")
            fi
        done
    fi
    
    # 从conf.d中查找
    if [ -d "/etc/nginx/conf.d" ]; then
        local conf_sites=$(find /etc/nginx/conf.d -name "*.conf" -type f)
        for site in $conf_sites; do
            local server_names=$(grep -E "server_name" "$site" | grep -v "#" | sed -e 's/.*server_name\s\+\([^;]\+\);.*/\1/')
            local site_root=$(grep "root" "$site" | grep -v "#" | head -1 | sed -e 's/.*root\s\+\([^;]\+\);.*/\1/')
            
            if [ -n "$server_names" ] && [ -n "$site_root" ]; then
                mappings+=("域名: $server_names -> 目录: $site_root")
            fi
        done
    fi
    
    # 输出映射
    printf '%s\n' "${mappings[@]}" | sort | uniq
}

# 显示Nginx信息
show_nginx_info() {
    echo -e "${BLUE}=== Nginx状态信息 ===${NC}"
    
    # 检查Nginx安装
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "${RED}错误: 未检测到Nginx安装${NC}"
        return 1
    fi
    
    # 版本信息
    echo -e "${GREEN}版本信息:${NC}"
    nginx -v 2>&1
    
    # 服务状态
    echo -e "\n${GREEN}服务状态:${NC}"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status nginx --no-pager | head -n 3
    elif command -v service >/dev/null 2>&1; then
        service nginx status
    else
        ps aux | grep -v grep | grep nginx
    fi
    
    # 配置文件
    echo -e "\n${GREEN}配置文件:${NC}"
    nginx -T 2>/dev/null | grep -E '^# configuration file' | head -n 5
    
    # 监听端口
    echo -e "\n${GREEN}监听端口:${NC}"
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn | grep nginx
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulpn | grep nginx
    else
        echo "无法获取端口信息 (需要ss或netstat命令)"
    fi
    
    # 网站配置
    echo -e "\n${GREEN}配置的网站:${NC}"
    if [ -d "/etc/nginx/conf.d" ]; then
        ls -la /etc/nginx/conf.d/*.conf 2>/dev/null || echo "无配置文件"
    fi
    
    if [ -d "/etc/nginx/sites-enabled" ]; then
        ls -la /etc/nginx/sites-enabled/* 2>/dev/null || echo "无配置文件"
    fi
    
    # 网站域名和目录映射
    echo -e "\n${GREEN}网站域名和目录映射:${NC}"
    local mappings=$(get_website_mappings)
    if [ -n "$mappings" ]; then
        echo "$mappings"
    else
        echo "未找到域名和目录映射信息"
    fi
    
    # 网站目录信息
    echo -e "\n${GREEN}网站根目录:${NC}"
    local roots=$(find_website_roots)
    if [ -n "$roots" ]; then
        echo "$roots"
    else
        echo "未找到网站根目录信息"
    fi
    
    # SSL证书
    echo -e "\n${GREEN}SSL证书:${NC}"
    if [ -d "/etc/nginx/ssl" ]; then
        ls -la /etc/nginx/ssl/*.crt 2>/dev/null || echo "无SSL证书"
    fi
    if [ -d "/etc/letsencrypt/live" ]; then
        ls -la /etc/letsencrypt/live/*/cert.pem 2>/dev/null || echo "无Let's Encrypt证书"
    fi
    
    # 日志文件
    echo -e "\n${GREEN}日志文件:${NC}"
    ls -la /var/log/nginx/* 2>/dev/null | head -n 5
    
    # 配置测试
    echo -e "\n${GREEN}配置语法检查:${NC}"
    nginx -t
    
    echo -e "${BLUE}=====================${NC}"
}

# 启动Nginx
start_nginx() {
    echo -e "${BLUE}启动Nginx服务...${NC}"
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start nginx
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Nginx启动成功${NC}"
        else
            echo -e "${RED}Nginx启动失败${NC}"
            return 1
        fi
    elif command -v service >/dev/null 2>&1; then
        service nginx start
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Nginx启动成功${NC}"
        else
            echo -e "${RED}Nginx启动失败${NC}"
            return 1
        fi
    else
        nginx
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Nginx启动成功${NC}"
        else
            echo -e "${RED}Nginx启动失败${NC}"
            return 1
        fi
    fi
}

# 停止Nginx
stop_nginx() {
    echo -e "${BLUE}停止Nginx服务...${NC}"
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop nginx
    elif command -v service >/dev/null 2>&1; then
        service nginx stop
    else
        nginx -s stop
    fi
    
    # 验证是否停止
    if pgrep -x "nginx" >/dev/null; then
        echo -e "${RED}Nginx未能完全停止, 尝试强制终止...${NC}"
        killall -9 nginx 2>/dev/null || true
    fi
    
    echo -e "${GREEN}Nginx已停止${NC}"
}

# 重启Nginx
restart_nginx() {
    echo -e "${BLUE}重启Nginx服务...${NC}"
    
    # 先检查配置语法
    echo -e "${BLUE}检查配置语法...${NC}"
    if ! nginx -t; then
        echo -e "${RED}配置有错误, 请修复后再重启${NC}"
        return 1
    fi
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart nginx
    elif command -v service >/dev/null 2>&1; then
        service nginx restart
    else
        nginx -s stop
        sleep 1
        nginx
    fi
    
    echo -e "${GREEN}Nginx已重启${NC}"
}

# 主菜单
main_menu() {
    clear
    echo -e "${GREEN}===================================${NC}"
    echo -e "${GREEN}=== Nginx安全管理脚本 v4.0 ===${NC}"
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

# 主函数
main() {
    check_root
    detect_system
    detect_pkg_manager
    
    # 安装前卸载防火墙
    detect_remove_firewall
    
    while true; do
        main_menu
        read choice
        case $choice in
            1) install_nginx ;;
            2) uninstall_nginx ;;
            3) restart_nginx ;;
            4) stop_nginx ;;
            5) configure_https ;;
            6) show_nginx_info ;;
            0) echo -e "${BLUE}退出系统${NC}"; break ;;
            *) echo -e "${RED}无效选项!${NC}" ;;
        esac
        echo
        read -n 1 -s -r -p "按任意键继续..."
        echo
    done
}

# 执行主函数
main
