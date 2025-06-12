#!/bin/bash

# ===================================================================
# Nginx一键安装管理脚本
# 支持所有主流Linux发行版的交互式Nginx安装、配置和管理工具
# ===================================================================

set -e  # 遇到错误即退出

# 颜色定义
RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
BLUE='[0;34m'
CYAN='[0;36m'
NC='[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 错误处理函数
handle_error() {
    log_error "脚本执行失败，退出码: $1"
    exit $1
}

# 设置错误陷阱
trap 'handle_error $?' ERR

# 检测Linux发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
        VERSION=$(cat /etc/redhat-release | grep -o '[0-9]\+' | head -1)
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
        VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/arch-release ]; then
        DISTRO="arch"
        VERSION="rolling"
    else
        log_error "无法检测Linux发行版"
        exit 1
    fi

    log_info "检测到系统: $DISTRO $VERSION"
}

# 检测包管理器
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt install -y"
        PKG_UPDATE="apt update"
        PKG_REMOVE="apt remove --purge -y"
        PKG_AUTOREMOVE="apt autoremove -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf check-update"
        PKG_REMOVE="dnf remove -y"
        PKG_AUTOREMOVE="dnf autoremove -y"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum check-update"
        PKG_REMOVE="yum remove -y"
        PKG_AUTOREMOVE="yum autoremove -y"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="pacman -S --noconfirm"
        PKG_UPDATE="pacman -Sy"
        PKG_REMOVE="pacman -Rs --noconfirm"
        PKG_AUTOREMOVE="pacman -Rns --noconfirm"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="zypper install -y"
        PKG_UPDATE="zypper refresh"
        PKG_REMOVE="zypper remove -y"
        PKG_AUTOREMOVE="zypper remove -u -y"
    else
        log_error "未找到支持的包管理器"
        exit 1
    fi

    log_info "使用包管理器: $PKG_MANAGER"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
}

# 检查nginx是否已安装
check_nginx_installed() {
    if command -v nginx >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 更新系统包
update_system() {
    log_info "更新系统包列表..."
    case $PKG_MANAGER in
        "apt")
            $PKG_UPDATE && apt upgrade -y
            ;;
        "dnf"|"yum")
            $PKG_UPDATE || true  # yum check-update 返回非零值是正常的
            ;;
        "pacman")
            $PKG_UPDATE
            ;;
        "zypper")
            $PKG_UPDATE && zypper update -y
            ;;
    esac
    log_success "系统包更新完成"
}

# 安装nginx
install_nginx() {
    log_info "开始安装Nginx..."

    # 根据发行版进行特殊处理
    case $DISTRO in
        "ubuntu"|"debian")
            $PKG_INSTALL nginx
            ;;
        "centos"|"rhel"|"fedora")
            if [ "$PKG_MANAGER" = "yum" ]; then
                # CentOS 7 需要 EPEL 仓库
                $PKG_INSTALL epel-release
            fi
            $PKG_INSTALL nginx
            ;;
        "arch"|"manjaro")
            $PKG_INSTALL nginx
            ;;
        "opensuse"|"sles")
            $PKG_INSTALL nginx
            ;;
        *)
            $PKG_INSTALL nginx
            ;;
    esac

    # 启动并启用nginx服务
    systemctl start nginx
    systemctl enable nginx

    # 配置防火墙
    configure_firewall

    log_success "Nginx安装完成并已启动"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."

    # UFW (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 'Nginx HTTP' 2>/dev/null || ufw allow 80/tcp
        ufw allow 'Nginx HTTPS' 2>/dev/null || ufw allow 443/tcp
        ufw --force enable 2>/dev/null || true
    fi

    # Firewalld (CentOS/RHEL/Fedora)
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
    fi

    log_success "防火墙配置完成"
}

# 卸载nginx
uninstall_nginx() {
    log_warning "开始卸载Nginx..."

    # 停止nginx服务
    if systemctl is-active --quiet nginx; then
        systemctl stop nginx
    fi

    if systemctl is-enabled --quiet nginx 2>/dev/null; then
        systemctl disable nginx
    fi

    # 根据包管理器卸载
    case $PKG_MANAGER in
        "apt")
            $PKG_REMOVE nginx nginx-common nginx-core nginx-full nginx-light nginx-extras
            $PKG_AUTOREMOVE
            ;;
        "dnf"|"yum")
            $PKG_REMOVE nginx
            $PKG_AUTOREMOVE
            ;;
        "pacman")
            $PKG_REMOVE nginx
            ;;
        "zypper")
            $PKG_REMOVE nginx
            $PKG_AUTOREMOVE
            ;;
    esac

    # 删除配置文件和日志
    rm -rf /etc/nginx
    rm -rf /var/log/nginx
    rm -rf /var/cache/nginx
    rm -rf /usr/share/nginx

    # 删除systemd服务文件（如果存在）
    rm -f /lib/systemd/system/nginx.service
    rm -f /usr/lib/systemd/system/nginx.service

    systemctl daemon-reload

    log_success "Nginx卸载完成"
}

# 重启nginx
restart_nginx() {
    log_info "重启Nginx服务..."
    if systemctl restart nginx; then
        log_success "Nginx重启成功"
    else
        log_error "Nginx重启失败"
        return 1
    fi
}

# 停止nginx
stop_nginx() {
    log_info "停止Nginx服务..."
    if systemctl stop nginx; then
        log_success "Nginx已停止"
    else
        log_error "停止Nginx失败"
        return 1
    fi
}

# 启动nginx
start_nginx() {
    log_info "启动Nginx服务..."
    if systemctl start nginx; then
        log_success "Nginx启动成功"
    else
        log_error "Nginx启动失败"
        return 1
    fi
}

# 安装certbot
install_certbot() {
    log_info "安装Certbot..."

    case $PKG_MANAGER in
        "apt")
            $PKG_INSTALL snapd
            snap install core; snap refresh core
            snap install --classic certbot
            ln -sf /snap/bin/certbot /usr/bin/certbot
            ;;
        "dnf"|"yum")
            $PKG_INSTALL certbot python3-certbot-nginx
            ;;
        "pacman")
            $PKG_INSTALL certbot certbot-nginx
            ;;
        "zypper")
            $PKG_INSTALL certbot python3-certbot-nginx
            ;;
    esac

    log_success "Certbot安装完成"
}

# 配置HTTPS
configure_https() {
    if ! command -v certbot >/dev/null 2>&1; then
        log_warning "Certbot未安装，正在安装..."
        install_certbot
    fi

    echo
    log_info "配置HTTPS证书"
    echo "请选择证书获取方式:"
    echo "1) 自动配置Let's Encrypt证书（推荐）"
    echo "2) 仅获取证书（手动配置）"
    echo "3) 生成自签名证书（测试用）"
    echo "4) 返回主菜单"

    read -p "请选择 [1-4]: " ssl_choice

    case $ssl_choice in
        1)
            read -p "请输入您的域名: " domain
            read -p "请输入您的邮箱: " email

            if [ -z "$domain" ] || [ -z "$email" ]; then
                log_error "域名和邮箱不能为空"
                return 1
            fi

            certbot --nginx -d $domain --email $email --agree-tos --non-interactive
            log_success "HTTPS证书配置完成"
            ;;
        2)
            read -p "请输入您的域名: " domain
            read -p "请输入您的邮箱: " email

            if [ -z "$domain" ] || [ -z "$email" ]; then
                log_error "域名和邮箱不能为空"
                return 1
            fi

            certbot certonly --nginx -d $domain --email $email --agree-tos --non-interactive
            log_success "证书获取完成，请手动配置nginx"
            ;;
        3)
            generate_self_signed_cert
            ;;
        4)
            return 0
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac
}

# 生成自签名证书
generate_self_signed_cert() {
    log_info "生成自签名证书..."

    read -p "请输入域名或IP: " domain
    if [ -z "$domain" ]; then
        domain="localhost"
    fi

    mkdir -p /etc/nginx/ssl

    openssl req -x509 -nodes -days 365 -newkey rsa:2048         -keyout /etc/nginx/ssl/nginx.key         -out /etc/nginx/ssl/nginx.crt         -subj "/C=CN/ST=State/L=City/O=Organization/CN=$domain"

    # 创建简单的HTTPS配置
    cat > /etc/nginx/sites-available/default-ssl << EOF
server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/html;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    # 启用配置（如果有sites-enabled目录）
    if [ -d "/etc/nginx/sites-enabled" ]; then
        ln -sf /etc/nginx/sites-available/default-ssl /etc/nginx/sites-enabled/
    fi

    nginx -t && systemctl reload nginx

    log_success "自签名证书生成完成"
    log_warning "注意: 自签名证书会在浏览器中显示安全警告"
}

# 显示nginx信息
show_nginx_info() {
    echo
    echo -e "${CYAN}==================== Nginx信息 ====================${NC}"

    # 版本信息
    if command -v nginx >/dev/null 2>&1; then
        echo -e "${GREEN}版本信息:${NC}"
        nginx -v 2>&1 | sed 's/^/  /'
        echo

        # 编译信息
        echo -e "${GREEN}编译配置:${NC}"
        nginx -V 2>&1 | grep -o -- '--[^'"'"' ]*' | sed 's/^/  /'
        echo

        # 服务状态
        echo -e "${GREEN}服务状态:${NC}"
        if systemctl is-active --quiet nginx; then
            echo -e "  状态: ${GREEN}运行中${NC}"
        else
            echo -e "  状态: ${RED}已停止${NC}"
        fi

        if systemctl is-enabled --quiet nginx 2>/dev/null; then
            echo -e "  开机自启: ${GREEN}已启用${NC}"
        else
            echo -e "  开机自启: ${RED}未启用${NC}"
        fi
        echo

        # 配置文件路径
        echo -e "${GREEN}配置文件:${NC}"
        config_path=$(nginx -t 2>&1 | grep -o 'test is successful' && nginx -T 2>/dev/null | head -1 | awk '{print $NF}' || echo "/etc/nginx/nginx.conf")
        echo "  主配置: $config_path"

        if [ -d "/etc/nginx/sites-available" ]; then
            echo "  站点配置: /etc/nginx/sites-available/"
            echo "  启用站点: /etc/nginx/sites-enabled/"
        elif [ -d "/etc/nginx/conf.d" ]; then
            echo "  站点配置: /etc/nginx/conf.d/"
        fi
        echo

        # 日志文件
        echo -e "${GREEN}日志文件:${NC}"
        access_log=$(grep -h "access_log" /etc/nginx/nginx.conf /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf 2>/dev/null | head -1 | awk '{print $2}' | sed 's/;//g' || echo "/var/log/nginx/access.log")
        error_log=$(grep -h "error_log" /etc/nginx/nginx.conf /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf 2>/dev/null | head -1 | awk '{print $2}' | sed 's/;//g' || echo "/var/log/nginx/error.log")

        echo "  访问日志: $access_log"
        echo "  错误日志: $error_log"
        echo

        # 进程信息
        echo -e "${GREEN}进程信息:${NC}"
        ps aux | grep nginx | grep -v grep | sed 's/^/  /'
        echo

        # 监听端口
        echo -e "${GREEN}监听端口:${NC}"
        netstat -tlnp 2>/dev/null | grep nginx | sed 's/^/  /' || ss -tlnp | grep nginx | sed 's/^/  /'
        echo

        # 配置测试
        echo -e "${GREEN}配置测试:${NC}"
        if nginx -t 2>/dev/null; then
            echo -e "  配置语法: ${GREEN}正确${NC}"
        else
            echo -e "  配置语法: ${RED}错误${NC}"
            nginx -t 2>&1 | sed 's/^/  /'
        fi

    else
        echo -e "${RED}Nginx未安装${NC}"
    fi

    echo -e "${CYAN}=================================================${NC}"
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${CYAN}           Nginx 一键安装管理脚本              ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo
    echo "请选择要执行的操作:"
    echo
    echo "1) 安装 Nginx"
    echo "2) 卸载 Nginx"
    echo "3) 重启 Nginx"
    echo "4) 停止 Nginx"
    echo "5) 启动 Nginx"
    echo "6) 配置 HTTPS"
    echo "7) 显示 Nginx 信息"
    echo "8) 退出"
    echo
    echo -e "${CYAN}=================================================${NC}"
}

# 主函数
main() {
    # 检查root权限
    check_root

    # 检测系统信息
    detect_distro
    detect_package_manager

    while true; do
        show_menu
        read -p "请选择 [1-8]: " choice

        case $choice in
            1)
                if check_nginx_installed; then
                    log_warning "Nginx已经安装"
                    show_nginx_info
                else
                    update_system
                    install_nginx
                    show_nginx_info
                fi
                ;;
            2)
                if check_nginx_installed; then
                    read -p "确定要卸载Nginx吗? [y/N]: " confirm
                    if [[ $confirm =~ ^[Yy]$ ]]; then
                        uninstall_nginx
                    else
                        log_info "取消卸载"
                    fi
                else
                    log_warning "Nginx未安装"
                fi
                ;;
            3)
                if check_nginx_installed; then
                    restart_nginx
                else
                    log_warning "Nginx未安装"
                fi
                ;;
            4)
                if check_nginx_installed; then
                    stop_nginx
                else
                    log_warning "Nginx未安装"
                fi
                ;;
            5)
                if check_nginx_installed; then
                    start_nginx
                else
                    log_warning "Nginx未安装"
                fi
                ;;
            6)
                if check_nginx_installed; then
                    configure_https
                else
                    log_warning "请先安装Nginx"
                fi
                ;;
            7)
                show_nginx_info
                ;;
            8)
                log_info "感谢使用，再见!"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac

        echo
        read -p "按Enter键继续..."
    done
}

# 脚本入口点
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
