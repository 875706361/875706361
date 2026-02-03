#!/bin/bash

#===============================================================================
#
#          FILE:  qd_install.sh
#
#         USAGE:  bash qd_install.sh
#
#   DESCRIPTION:  QD 签到框架交互式安装与管理脚本
#                 基于 https://qd-today.github.io/qd/zh_CN/guide/deployment.html
#
#        AUTHOR:  QD Installation Script
#       VERSION:  1.2.0
#       CREATED:  2026-02-02
#       UPDATED:  2026-02-03 (增加开机自启管理功能)
#
#===============================================================================

set -e

# ================================ 颜色定义 ================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# ================================ 全局变量 ================================
QD_DIR=""
INSTALL_TYPE="none"
DOCKER_TAG="latest"
PORT=8923
ADMIN_EMAIL=""
USE_HOST_NETWORK=false

# ================================ 检测安装状态 ================================

# 检测当前系统中 QD 的安装类型和状态
check_install_status() {
    INSTALL_TYPE="none"
    QD_DIR=""
    
    # 定义可能的搜索目录
    local search_dirs=("$HOME/qd" "$(pwd)/qd" "/opt/qd" "/usr/local/qd")
    
    # 1. 优先检查正在运行的 Docker 容器
    if command_exists docker; then
        if docker ps -a --format '{{.Names}}' | grep -q "^qd$"; then
            # 检查是否有 docker-compose.yml 联动的容器
            local compose_project=$(docker inspect qd --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null)
            if [[ -n "$compose_project" && -f "$compose_project/docker-compose.yml" ]]; then
                INSTALL_TYPE="docker-compose"
                QD_DIR="$compose_project"
            else
                INSTALL_TYPE="docker-single"
                local mount_source=$(docker inspect qd --format '{{range .Mounts}}{{if eq .Destination "/usr/src/app/config"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)
                if [[ -n "$mount_source" ]]; then
                    QD_DIR=${mount_source%/config}
                fi
            fi
            
            local host_port=$(docker inspect qd --format '{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}' 2>/dev/null)
            if [[ -n "$host_port" ]]; then
                PORT="$host_port"
            fi
            return 0
        fi
    fi
    
    # 2. 检查静态目录中的 docker-compose
    for dir in "${search_dirs[@]}"; do
        if [ -f "$dir/docker-compose.yml" ]; then
            if grep -q "qdtoday/qd" "$dir/docker-compose.yml"; then
                INSTALL_TYPE="docker-compose"
                QD_DIR="$dir"
                local port_match=$(grep -oP '\d+(?=:80)' "$dir/docker-compose.yml" | head -n 1)
                [[ -n "$port_match" ]] && PORT="$port_match"
                return 0
            fi
        fi
    done
    
    # 3. 检查源码部署
    for dir in "${search_dirs[@]}"; do
        if [ -f "$dir/run.py" ] && [ -f "$dir/local_config.py" ]; then
            INSTALL_TYPE="source"
            QD_DIR="$dir"
            local port_match=$(grep "PORT =" "$dir/local_config.py" | grep -oP '\d+')
            [[ -n "$port_match" ]] && PORT="$port_match"
            return 0
        fi
    done
}

# ================================ 辅助函数 ================================

# 打印分隔线
print_line() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 打印双分隔线
print_double_line() {
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════════════${NC}"
}

# 打印 Logo
print_logo() {
    clear
    echo -e "${PURPLE}"
    cat << 'EOF'

     ██████╗ ██████╗     ███████╗██████╗  █████╗ ███╗   ███╗███████╗
    ██╔═══██╗██╔══██╗    ██╔════╝██╔══██╗██╔══██╗████╗ ████║██╔════╝
    ██║   ██║██║  ██║    █████╗  ██████╔╝███████║██╔████╔██║█████╗  
    ██║▄▄ ██║██║  ██║    ██╔══╝  ██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝  
    ╚██████╔╝██████╔╝    ██║     ██║  ██║██║  ██║██║ ╚═╝ ██║███████╗
     ╚══▀▀═╝ ╚═════╝     ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝
                                                                     
EOF
    echo -e "${NC}"
    echo -e "${WHITE}                    ✨ 签到框架 交互式安装管理脚本 ✨${NC}"
    echo -e "${CYAN}                   基于 qd-today.github.io 官方文档${NC}"
    echo ""
    print_double_line
}

# 打印成功消息
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# 打印错误消息
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 打印警告消息
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 打印信息消息
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# 打印步骤
print_step() {
    echo -e "${PURPLE}➤ $1${NC}"
}

# 等待用户按键继续
press_any_key() {
    echo ""
    echo -e "${YELLOW}按任意键继续...${NC}"
    read -n 1 -s -r
}

# 确认操作
confirm() {
    local prompt="$1"
    local default="${2:-N}"
    
    if [[ "$default" == "Y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    echo -ne "${YELLOW}$prompt${NC}"
    read -r response
    
    if [[ -z "$response" ]]; then
        response="$default"
    fi
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# ================================ 管理功能函数 ================================

# 查看状态
show_status() {
    print_logo
    echo -e "${GREEN}  🔍 查看面板运行状态${NC}"
    print_line
    echo ""
    
    check_install_status
    
    if [[ "$INSTALL_TYPE" == "none" ]]; then
        print_warning "未检测到已安装的 QD 实例"
    else
        echo -e "  安装类型: ${CYAN}$INSTALL_TYPE${NC}"
        echo -e "  安装目录: ${CYAN}$QD_DIR${NC}"
        echo -e "  当前端口: ${CYAN}$PORT${NC}"
        echo ""
        
        if [[ "$INSTALL_TYPE" == "docker-compose" || "$INSTALL_TYPE" == "docker-single" ]]; then
            if docker ps --format '{{.Names}}' | grep -q "^qd$"; then
                print_success "容器状态: 正在运行"
                echo ""
                docker ps -f name=qd --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            else
                print_error "容器状态: 已停止或未创建"
            fi
        elif [[ "$INSTALL_TYPE" == "source" ]]; then
            if systemctl is-active --quiet qd 2>/dev/null; then
                print_success "服务状态: 正在运行 (Systemd 管理)"
            elif ps aux | grep -v grep | grep -q "python.*run.py"; then
                print_success "进程状态: 正在运行 (通过命令启动)"
            else
                print_error "服务状态: 已停止"
            fi
        fi
    fi
    
    echo ""
    print_line
    press_any_key
}

# 查看与修改面板信息
manage_info() {
    while true; do
        check_install_status
        print_logo
        echo -e "${GREEN}  ℹ️  面板信息与配置管理${NC}"
        print_line
        echo ""
        
        if [[ "$INSTALL_TYPE" == "none" ]]; then
            print_warning "未检测到已安装的 QD 实例，无法管理信息"
            press_any_key
            return
        fi
        
        echo -e "  ${WHITE}当前部署架构：${NC}"
        echo -e "  • 类型: ${CYAN}$INSTALL_TYPE${NC}"
        echo -e "  • 目录: ${CYAN}$QD_DIR${NC}"
        echo -e "  • 端口: ${YELLOW}$PORT${NC}"
        echo -e "  • 地址: ${CYAN}http://localhost:$PORT${NC}"
        echo ""
        print_line
        echo -e "  ${GREEN}1)${NC} 修改访问端口"
        echo -e "  ${GREEN}2)${NC} 直接编辑配置代码 (${CYAN}local_config.py${NC})"
        echo -e "  ${GREEN}0)${NC} 返回主菜单"
        echo ""
        echo -ne "${YELLOW}请输入选项 [0-2]: ${NC}"
        read -r info_choice
        
        case $info_choice in
            1)
                echo ""
                echo -ne "${YELLOW}请输入新的端口号 (1-65535): ${NC}"
                read -r new_port
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                    apply_port_change "$new_port"
                else
                    print_error "无效的端口号"
                    sleep 2
                fi
                ;;
            2)
                edit_code
                ;;
            0) break ;;
            *) print_error "无效选项"; sleep 1 ;;
        esac
    done
}

# 应用端口修改
apply_port_change() {
    local new_port=$1
    print_step "正在更新端口为 $new_port..."
    
    if [[ "$INSTALL_TYPE" == "docker-compose" ]]; then
        sed -i "s/$PORT:80/$new_port:80/g" "$QD_DIR/docker-compose.yml"
        print_info "正在重启 Docker Compose..."
        cd "$QD_DIR" && (docker compose up -d || docker-compose up -d)
    elif [[ "$INSTALL_TYPE" == "docker-single" ]]; then
        print_warning "单容器模式需要删除重建容器以更改映射。正在准备..."
        local old_tag="latest" 
        old_tag=$(docker inspect qd --format '{{.Config.Image}}' | cut -d: -f2)
        DOCKER_TAG=$old_tag
        PORT=$new_port
        install_docker_single_logic 
    elif [[ "$INSTALL_TYPE" == "source" ]]; then
        sed -i "s/PORT = $PORT/PORT = $new_port/g" "$QD_DIR/local_config.py"
        if systemctl is-active --quiet qd 2>/dev/null; then
            print_info "正在重启 Systemd 服务..."
            sudo systemctl restart qd
        else
            print_info "已更新配置文件，请手动启动项目"
        fi
    fi
    
    PORT=$new_port
    print_success "端口已成功修改为 $PORT"
    sleep 2
}

# 修改代码 (定位配置文件)
edit_code() {
    local config_file=""
    if [[ "$INSTALL_TYPE" == "source" ]]; then
        config_file="$QD_DIR/local_config.py"
    elif [[ "$INSTALL_TYPE" == "docker-compose" || "$INSTALL_TYPE" == "docker-single" ]]; then
        if [[ -f "$QD_DIR/config/local_config.py" ]]; then
            config_file="$QD_DIR/config/local_config.py"
        elif [[ -f "$QD_DIR/local_config.py" ]]; then
            config_file="$QD_DIR/local_config.py"
        fi
    fi
    
    if [[ -n "$config_file" && -f "$config_file" ]]; then
        print_info "定位到配置: $config_file"
        local editor="vi"
        command_exists nano && editor="nano"
        
        echo -e "${YELLOW}提示: 修改 local_config.py 后需重启面板生效${NC}"
        press_any_key
        $editor "$config_file"
        
        if confirm "是否现在重启面板以应用修改？" "Y"; then
            if [[ "$INSTALL_TYPE" == "docker-compose" ]]; then
                cd "$QD_DIR" && (docker compose restart || docker-compose restart)
            elif [[ "$INSTALL_TYPE" == "docker-single" ]]; then
                docker restart qd
            elif [[ "$INSTALL_TYPE" == "source" ]]; then
                sudo systemctl restart qd 2>/dev/null || true
            fi
            print_success "重启指令已发送"
        fi
    else
        print_error "未找到可编辑的 local_config.py 文件"
        print_info "如果您刚安装完，请确保已经创建了该文件"
        sleep 3
    fi
}

# 开机自启设置
enable_autostart() {
    print_logo
    echo -e "${GREEN}  ⚡ 设置开机自启${NC}"
    print_line
    echo ""
    
    check_install_status
    
    if [[ "$INSTALL_TYPE" == "none" ]]; then
        print_warning "未检测到已安装的 QD 实例"
        press_any_key
        return
    fi
    
    print_step "正在为 ${CYAN}$INSTALL_TYPE${NC} 配置自启..."
    
    if [[ "$INSTALL_TYPE" == "docker-compose" ]]; then
        if [ -f "$QD_DIR/docker-compose.yml" ]; then
            if ! grep -q "restart:" "$QD_DIR/docker-compose.yml"; then
                sed -i '/image:/a \    restart: unless-stopped' "$QD_DIR/docker-compose.yml"
            else
                sed -i 's/restart: .*/restart: unless-stopped/' "$QD_DIR/docker-compose.yml"
            fi
            cd "$QD_DIR" && (docker compose up -d || docker-compose up -d)
            print_success "Docker Compose 已配置 restart: unless-stopped"
        fi
    elif [[ "$INSTALL_TYPE" == "docker-single" ]]; then
        docker update --restart unless-stopped qd
        print_success "Docker 容器 qd 已更新重启策略"
    elif [[ "$INSTALL_TYPE" == "source" ]]; then
        if [ ! -f "/etc/systemd/system/qd.service" ]; then
            print_info "正在创建 Systemd 服务..."
            sudo tee /etc/systemd/system/qd.service > /dev/null << EOF
[Unit]
Description=QD Framework
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$QD_DIR
ExecStart=$QD_DIR/venv/bin/python $QD_DIR/run.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
            sudo systemctl daemon-reload
        fi
        sudo systemctl enable qd
        sudo systemctl start qd
        print_success "Systemd 服务已启用并设置为开机自启"
    fi
    
    press_any_key
}

# 卸载 QD
uninstall_qd() {
    print_logo
    echo -e "${RED}  🗑️  安全卸载 QD 框架${NC}"
    print_line
    echo ""
    
    check_install_status
    
    if [[ "$INSTALL_TYPE" == "none" ]]; then
        print_warning "未检测到已安装的 QD，无需卸载"
        press_any_key
        return
    fi
    
    echo -e "  检测到安装: ${PURPLE}$INSTALL_TYPE${NC}"
    echo -e "  安装路径: ${CYAN}$QD_DIR${NC}"
    echo ""
    print_warning "警告: 卸载将删除所有配置、脚本和数据库！"
    
    if confirm "确定要彻底删除吗？" "N"; then
        print_step "正在停止并清理服务..."
        
        if [[ "$INSTALL_TYPE" == "docker-compose" ]]; then
            cd "$QD_DIR" && (docker compose down -v || docker-compose down -v)
        elif [[ "$INSTALL_TYPE" == "docker-single" ]]; then
            docker rm -f qd 2>/dev/null || true
        elif [[ "$INSTALL_TYPE" == "source" ]]; then
            sudo systemctl stop qd 2>/dev/null || true
            sudo systemctl disable qd 2>/dev/null || true
            sudo rm -f /etc/systemd/system/qd.service
            sudo systemctl daemon-reload
        fi
        
        print_step "正在删除物理文件..."
        if [[ -d "$QD_DIR" ]]; then
            rm -rf "$QD_DIR"
            print_success "安装目录已清理"
        fi
        
        print_success "QD 框架卸载完成"
    else
        print_info "操作已取消"
    fi
    
    press_any_key
}

# 重装 QD
reinstall_qd() {
    print_logo
    echo -e "${YELLOW}  🔄 面板重置/重装${NC}"
    print_line
    echo ""
    
    print_warning "重装会先完全卸载现有面板及数据！"
    if confirm "是否继续？" "N"; then
        uninstall_qd
        print_info "即将进入重新安装流程..."
        sleep 2
    else
        print_info "已取消重装"
        press_any_key
    fi
}

# ================================ 系统检测与环境安装 ================================

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        OS="unknown"
    fi
    echo "$OS"
}

command_exists() {
    command -v "$1" &> /dev/null
}

detect_package_manager() {
    if command_exists apt-get; then echo "apt";
    elif command_exists yum; then echo "yum";
    elif command_exists dnf; then echo "dnf";
    elif command_exists pacman; then echo "pacman";
    elif command_exists apk; then echo "apk";
    elif command_exists brew; then echo "brew";
    else echo "unknown"; fi
}

check_docker() {
    if command_exists docker; then
        print_success "Docker 已就绪"
        return 0
    fi
    return 1
}

check_docker_compose() {
    if command_exists docker-compose || docker compose version &> /dev/null; then
        print_success "Docker Compose 已就绪"
        return 0
    fi
    return 1
}

check_python() {
    local python_cmd="python3"
    command_exists python3 || python_cmd="python"
    if command_exists $python_cmd; then
        local version=$($python_cmd -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
        if [[ $(echo "$version" | cut -d. -f1) -ge 3 ]] && [[ $(echo "$version" | cut -d. -f2) -ge 9 ]]; then
            print_success "Python $version 已就绪"
            return 0
        fi
    fi
    return 1
}

check_git() {
    if command_exists git; then
        print_success "Git 已就绪"
        return 0
    fi
    return 1
}

install_docker() {
    print_step "正在安装 Docker..."
    local pkg_manager=$(detect_package_manager)
    case $pkg_manager in
        apt)
            sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg lsb-release
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$(detect_os)/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(detect_os) $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        yum|dnf)
            sudo yum install -y yum-utils && sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        *) print_warning "系统不支持自动安装，请参考官方文档安装 Docker"; return 1 ;;
    esac
    sudo systemctl start docker && sudo systemctl enable docker
}

install_python() {
    print_step "正在安装 Python 3.9+..."
    local pkg_manager=$(detect_package_manager)
    case $pkg_manager in
        apt) sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv ;;
        yum|dnf) sudo $pkg_manager install -y python39 python39-pip ;;
        *) print_error "不支持自动安装 Python，请手动安装"; return 1 ;;
    esac
}

# ================================ 安装逻辑 ================================

select_docker_tag() {
    while true; do
        print_logo
        echo -e "  ${WHITE}请选择镜像标签：${NC}"
        echo -e "  1) latest       ${CYAN}(最新正式版)${NC}"
        echo -e "  2) lite-latest  ${CYAN}(精简版, 无OCR)${NC}"
        echo -e "  3) ja3-latest   ${CYAN}(解决JA3指纹识别)${NC}"
        echo -e "  4) dev          ${CYAN}(最新开发版)${NC}"
        echo -e "  5) 自定义版本"
        echo -ne "${YELLOW}选择 [1-5]: ${NC}"
        read -r choice
        case $choice in
            1) DOCKER_TAG="latest"; break ;;
            2) DOCKER_TAG="lite-latest"; break ;;
            3) DOCKER_TAG="ja3-latest"; break ;;
            4) DOCKER_TAG="dev"; break ;;
            5) echo -n "输入版本号: "; read -r custom; DOCKER_TAG=$custom; break ;;
            *) print_error "选择无效" ;;
        esac
    done
}

install_docker_compose_method() {
    print_logo
    echo -e "${GREEN}  📦 Docker Compose 方式部署${NC}"
    check_docker || install_docker
    check_docker_compose || print_error "找不到 Docker Compose" || return 1
    select_docker_tag
    echo -e "1) 默认路径 (\$HOME/qd)\n2) 当前路径 ($(pwd)/qd)\n3) 自定义"
    read -r dir_choice
    [[ "$dir_choice" == "2" ]] && QD_DIR="$(pwd)/qd" || ([[ "$dir_choice" == "3" ]] && read -p "路径: " custom_dir && QD_DIR=$custom_dir || QD_DIR="$HOME/qd")
    read -p "映射端口 (默认8923): " custom_port
    PORT=${custom_port:-8923}
    mkdir -p "$QD_DIR/config" && cd "$QD_DIR"
    curl -sSLf -o docker-compose.yml "https://fastly.jsdelivr.net/gh/qd-today/qd@master/docker-compose.yml" || curl -sSLf -o docker-compose.yml "https://raw.githubusercontent.com/qd-today/qd/master/docker-compose.yml"
    sed -i "s|qdtoday/qd:latest|qdtoday/qd:$DOCKER_TAG|g" docker-compose.yml
    sed -i "s|8923:80|$PORT:80|g" docker-compose.yml
    if confirm "是否启动容器？" "Y"; then
        docker compose up -d || docker-compose up -d
        print_success "部署成功！访问地址: http://localhost:$PORT"
    fi
}

install_docker_single_logic() {
    check_docker || install_docker
    mkdir -p "$QD_DIR/config"
    docker rm -f qd 2>/dev/null || true
    if [ "$USE_HOST_NETWORK" = true ]; then
        docker run -d --name qd --restart unless-stopped --env PORT=$PORT --env TZ=Asia/Shanghai --net=host -v "$QD_DIR/config:/usr/src/app/config" "qdtoday/qd:$DOCKER_TAG"
    else
        docker run -d --name qd --restart unless-stopped --env TZ=Asia/Shanghai -p "$PORT:80" -v "$QD_DIR/config:/usr/src/app/config" "qdtoday/qd:$DOCKER_TAG"
    fi
    print_success "容器已启动"
}

install_docker_single() {
    print_logo
    echo -e "${GREEN}  🐋 Docker 单容器方式部署${NC}"
    select_docker_tag
    echo -e "1) 默认路径 (\$HOME/qd)\n2) 当前路径 ($(pwd)/qd)\n3) 自定义"
    read -r dir_choice
    [[ "$dir_choice" == "2" ]] && QD_DIR="$(pwd)/qd" || ([[ "$dir_choice" == "3" ]] && read -p "路径: " custom_dir && QD_DIR=$custom_dir || QD_DIR="$HOME/qd")
    read -p "映射端口 (默认8923): " custom_port
    PORT=${custom_port:-8923}
    echo -e "1) Bridge模式 (推荐)\n2) Host模式"
    read -r net_choice
    [[ "$net_choice" == "2" ]] && USE_HOST_NETWORK=true || USE_HOST_NETWORK=false
    install_docker_single_logic
}

install_source() {
    print_logo
    echo -e "${GREEN}  📦 源码编译部署${NC}"
    check_python || install_python
    check_git || (sudo apt install -y git)
    echo -e "1) 默认路径 (\$HOME/qd)\n2) 自定义"
    read -r dir_choice
    [[ "$dir_choice" == "2" ]] && read -p "路径: " custom_dir && QD_DIR=$custom_dir || QD_DIR="$HOME/qd"
    read -p "运行端口 (默认8923): " custom_port
    PORT=${custom_port:-8923}
    git clone https://github.com/qd-today/qd.git "$QD_DIR"
    cd "$QD_DIR"
    python3 -m venv venv && source venv/bin/activate
    pip install --upgrade pip && pip install -r requirements.txt
    cp config.py local_config.py
    sed -i "s/PORT = .*/PORT = $PORT/" local_config.py
    if confirm "是否创建 Systemd 服务并自启？" "Y"; then
        sudo tee /etc/systemd/system/qd.service > /dev/null << EOF
[Unit]
Description=QD Framework
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$QD_DIR
ExecStart=$QD_DIR/venv/bin/python $QD_DIR/run.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload && sudo systemctl enable qd && sudo systemctl start qd
        print_success "服务已启动"
    fi
}

# ================================ 主菜单 ================================

show_main_menu() {
    print_logo
    check_install_status
    echo ""
    if [[ "$INSTALL_TYPE" != "none" ]]; then
        echo -e "  ${WHITE}当前状态：${NC}检测到已安装 (${CYAN}$INSTALL_TYPE${NC})"
    else
        echo -e "  ${WHITE}当前状态：${NC}${YELLOW}未安装${NC}"
    fi
    echo ""
    echo -e "  ${WHITE}【面板安装】${NC}"
    echo -e "  ${GREEN}1)${NC} Docker Compose 部署 (推荐)"
    echo -e "  ${GREEN}2)${NC} Docker 单容器部署"
    echo -e "  ${GREEN}3)${NC} 源码部署 (Python 3.9+)"
    echo ""
    echo -e "  ${WHITE}【面板管理与维护】${NC}"
    echo -e "  ${GREEN}4)${NC} 查看运行状态 (Status)"
    echo -e "  ${GREEN}5)${NC} 修改端口 / 面板信息管理"
    echo -e "  ${GREEN}6)${NC} 修改代码 (直接编辑配置文件)"
    echo -e "  ${GREEN}7)${NC} 设置开机自启"
    echo -e "  ${GREEN}8)${NC} 卸载 QD 框架"
    echo -e "  ${GREEN}9)${NC} 重装/重置 QD 框架"
    echo ""
    echo -e "  ${WHITE}【其他工具】${NC}"
    echo -e "  ${GREEN}10)${NC} 系统环境自检"
    echo -e "  ${GREEN}11)${NC} 退出脚本"
    echo ""
    print_line
    echo -ne "${YELLOW}请输入选项 [1-11]: ${NC}"
}

main() {
    while true; do
        show_main_menu
        read -r choice
        case $choice in
            1) install_docker_compose_method; press_any_key ;;
            2) install_docker_single; press_any_key ;;
            3) install_source; press_any_key ;;
            4) show_status ;;
            5) manage_info ;;
            6) edit_code ;;
            7) enable_autostart ;;
            8) uninstall_qd ;;
            9) reinstall_qd ;;
            10) 
                print_logo
                echo -e "${GREEN}  🔧 系统环境自检${NC}"
                check_docker || print_warning "Docker: 未安装"
                check_docker_compose || print_warning "Compose: 未安装"
                check_python || print_warning "Python: 未就绪"
                check_git || print_warning "Git: 未安装"
                press_any_key
                ;;
            11) exit 0 ;;
            *) print_error "选择错误"; sleep 1 ;;
        esac
    done
}

main "$@"
