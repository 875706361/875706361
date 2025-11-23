#!/bin/bash

# ╔════════════════════════════════════════════╗
# ║     Squid 代理服务管理脚本 - 自定义版      ║
# ╚════════════════════════════════════════════╝
set -euo pipefail

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

SUCCESS='✓'
ERROR='✗'
WARNING='⚠'
INFO='ℹ'
ARROW='→'

SQUID_CONF="/etc/squid/squid.conf"
SQUID_SERVICE="squid"
LOG_FILE="/var/log/squid-manager.log"

# 用户要求的配置内容
CUSTOM_CONFIG=$(cat <<EOF
acl SSL_ports port 443
acl Safe_ports port 80          # http
acl Safe_ports port 21          # ftp
acl Safe_ports port 443         # https
acl Safe_ports port 70          # gopher
acl Safe_ports port 210         # wais
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280         # http-mgmt
acl Safe_ports port 488         # gss-http
acl Safe_ports port 591         # filemaker
acl Safe_ports port 777         # multiling http
acl CONNECT method CONNECT
via off

request_header_access X-Forwarded-For deny all
request_header_access user-agent  deny all
reply_header_access X-Forwarded-For deny all
reply_header_access user-agent  deny all
http_port 8080

http_access allow  all
access_log /var/log/squid/access.log
visible_hostname squid.david.dev
cache_mgr 1111111111@gmail.com
EOF
)

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

print_header() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}$1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
}

print_success() { echo -e "${GREEN}${SUCCESS} $1${NC}"; log_message "INFO" "$1"; }
print_error() { echo -e "${RED}${ERROR} $1${NC}"; log_message "ERROR" "$1"; }
print_warning() { echo -e "${YELLOW}${WARNING} $1${NC}"; log_message "WARN" "$1"; }
print_info() { echo -e "${BLUE}${INFO} $1${NC}"; }
print_arrow() { echo -e "${CYAN}${ARROW}${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以 root 身份运行"
        print_info "请使用: sudo $0"
        exit 1
    fi
}

detect_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        OS_VERSION=$(grep -oP '(?<=release )\\d+' /etc/redhat-release)
    else
        OS="unknown"
        OS_VERSION="unknown"
    fi
    print_info "检测到系统: $OS $OS_VERSION"
}

get_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        INSTALL_CMD="apt-get install -y"
        PURGE_CMD="apt-get purge -y && apt-get autoremove -y"
        UPDATE_CMD="apt-get update"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
        PURGE_CMD="dnf remove -y && dnf autoremove -y"
        UPDATE_CMD="dnf check-update"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        INSTALL_CMD="yum install -y"
        PURGE_CMD="yum remove -y && yum autoremove -y"
        UPDATE_CMD="yum check-update"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm"
        PURGE_CMD="pacman -Rns --noconfirm"
        UPDATE_CMD="pacman -Sy"
    else
        print_error "未能检测到支持的包管理器"
        exit 1
    fi
    print_info "检测到包管理器: $PKG_MANAGER"
}

install_squid() {
    print_header "🚀 安装 Squid 代理服务"
    if command -v squid &> /dev/null; then
        print_warning "Squid 已经安装"
        return 0
    fi
    print_arrow "更新系统包列表..."
    if ! eval "$UPDATE_CMD" &>/dev/null; then
        print_warning "包列表更新失败，继续安装"
    fi
    print_arrow "安装 Squid..."
    if eval "$INSTALL_CMD squid" &>/dev/null; then
        print_success "Squid 安装成功"
        set_custom_config
        print_arrow "启用 Squid 自启动..."
        systemctl enable $SQUID_SERVICE &>/dev/null
        print_arrow "启动 Squid 服务..."
        systemctl start $SQUID_SERVICE &>/dev/null
        print_success "Squid 已启动"
        sleep 2
        show_status
    else
        print_error "Squid 安装失败"
        exit 1
    fi
}

set_custom_config() {
    print_header "🔧 应用自定义 Squid 配置"
    if [[ -f "$SQUID_CONF" ]]; then
        cp "$SQUID_CONF" "$SQUID_CONF.bak.$(date +%s)"
    fi
    echo "$CUSTOM_CONFIG" > "$SQUID_CONF"
    print_success "已覆盖配置。"
    if squid -k check &>/dev/null; then
        print_success "Squid 配置验证通过"
    else
        print_warning "配置可能有问题，请手动检查"
    fi
}

uninstall_squid() {
    print_header "🗑️  卸载 Squid 代理服务"
    if ! command -v squid &> /dev/null; then
        print_warning "Squid 未安装"
        return 0
    fi
    read -p "$(echo -e ${YELLOW})确认卸载 Squid？(y/N): $(echo -e ${NC})" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "取消卸载"
        return 0
    fi
    print_arrow "停止 Squid 服务..."
    systemctl stop $SQUID_SERVICE &>/dev/null || true
    print_arrow "禁用自启动..."
    systemctl disable $SQUID_SERVICE &>/dev/null || true
    print_arrow "卸载 Squid..."
    if eval "$PURGE_CMD squid" &>/dev/null; then
        print_success "Squid 卸载成功"
    else
        print_error "Squid 卸载失败"
        exit 1
    fi
}

show_status() {
    print_header "📊 Squid 服务状态"
    if systemctl is-active --quiet $SQUID_SERVICE; then
        print_success "Squid 服务运行中"
    else
        print_error "Squid 服务未运行"
    fi
    echo
    print_info "服务信息:"
    systemctl status $SQUID_SERVICE --no-pager || true
    echo
    print_info "监听端口:"
    netstat -tlnp 2>/dev/null | grep squid || ss -tlnp 2>/dev/null | grep squid || print_warning "无法获取端口信息"
    echo
    print_info "当前配置端口:"
    grep "^http_port" "$SQUID_CONF" | head -1 || print_warning "未找到端口配置"
}

restart_squid() {
    print_header "🔄 重启 Squid 服务"
    print_arrow "正在重启..."
    if systemctl restart $SQUID_SERVICE; then
        print_success "Squid 已重启"
        sleep 2
        show_status
    else
        print_error "重启失败"
    fi
}

start_squid() {
    print_header "✅ 启动 Squid 服务"
    if systemctl start $SQUID_SERVICE; then
        print_success "Squid 服务已启动"
        sleep 1
        show_status
    else
        print_error "启动失败"
    fi
}

stop_squid() {
    print_header "🛑 停止 Squid 服务"
    if systemctl stop $SQUID_SERVICE; then
        print_success "Squid 服务已停止"
    else
        print_error "停止失败"
    fi
}

change_port() {
    print_header "🔌 修改代理端口"
    local current_port=$(grep "^http_port" "$SQUID_CONF" | grep -oP '\\d+' | head -1)
    print_info "当前端口: $current_port"
    read -p "$(echo -e ${CYAN})请输入新的端口号 (1024-65535): $(echo -e ${NC})" new_port
    if ! [[ $new_port =~ ^[0-9]+$ ]] || (( new_port < 1024 || new_port > 65535 )); then
        print_error "端口号无效"
        return 1
    fi
    if (( new_port == current_port )); then
        print_warning "新端口与当前端口相同"
        return 0
    fi
    cp "$SQUID_CONF" "$SQUID_CONF.bak.$(date +%s)"
    sed -i "s/^http_port.*/http_port $new_port/" "$SQUID_CONF"
    if squid -k check &>/dev/null; then
        systemctl restart $SQUID_SERVICE
        print_success "端口已修改为: $new_port"
        sleep 2
        show_status
    else
        print_error "配置验证失败，已恢复原配置"
        cp "$SQUID_CONF.bak.$(date +%s)" "$SQUID_CONF"
        return 1
    fi
}

view_logs() {
    print_header "📝 Squid 访问日志 (最近50条)"
    if [[ -f /var/log/squid/access.log ]]; then
        tail -n 50 /var/log/squid/access.log
    else
        print_warning "无法读取日志文件"
    fi
}

reconfigure_squid() {
    print_header "⚙️  重新配置 Squid"
    set_custom_config
    systemctl restart $SQUID_SERVICE
    print_success "自定义配置已应用并重启"
}

show_menu() {
    clear
    print_header "   Squid 代理管理脚本 v1.1 (自定义配置版)"
    echo
    echo -e "${BOLD}请选择操作:${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BLUE}1${NC})  ${BOLD}安装 Squid${NC}              - 安装并应用自定义配置"
    echo -e "  ${BLUE}2${NC})  ${BOLD}卸载 Squid${NC}              - 卸载 Squid 及配置"
    echo -e "  ${BLUE}3${NC})  ${BOLD}启动服务${NC}               - 启动 Squid 服务"
    echo -e "  ${BLUE}4${NC})  ${BOLD}停止服务${NC}               - 停止 Squid 服务"
    echo -e "  ${BLUE}5${NC})  ${BOLD}重启服务${NC}               - 重启 Squid"
    echo -e "  ${BLUE}6${NC})  ${BOLD}修改端口${NC}               - 动态修改监听端口"
    echo -e "  ${BLUE}7${NC})  ${BOLD}查看状态${NC}               - 显示服务状态"
    echo -e "  ${BLUE}8${NC})  ${BOLD}查看日志${NC}               - 查看访问日志"
    echo -e "  ${BLUE}9${NC})  ${BOLD}修改配置${NC}               - 应用自定义squid.conf"
    echo -e "  ${BLUE}0${NC})  ${BOLD}退出程序${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

main() {
    check_root
    touch "$LOG_FILE"
    detect_system
    get_package_manager
    while true; do
        show_menu
        read -p "$(echo -e ${MAGENTA})请输入选项 (0-9): $(echo -e ${NC})" choice
        echo
        case $choice in
            1) install_squid ;;
            2) uninstall_squid ;;
            3) start_squid ;;
            4) stop_squid ;;
            5) restart_squid ;;
            6) change_port ;;
            7) show_status ;;
            8) view_logs ;;
            9) reconfigure_squid ;;
            0) print_info "感谢使用 Squid 管理脚本"; exit 0 ;;
            *) print_error "无效的选项" ;;
        esac
        read -p "$(echo -e ${CYAN})按 Enter 继续...$(echo -e ${NC})"
    done
}

trap 'print_error "脚本执行出错"; exit 1' ERR

main "$@"