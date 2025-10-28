#!/bin/bash

#================================================================
# QD面板 Docker自动化安装管理脚本
# 支持所有主流Linux发行版
# 功能：安装、启动、停止、重启、卸载、查看日志、更新
# 作者：Automated Installation Script
# 版本：2.0
#================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置参数
QD_DIR="/opt/qd"
QD_CONFIG_DIR="${QD_DIR}/config"
QD_REDIS_DIR="${QD_DIR}/redis"
QD_COMPOSE_FILE="${QD_DIR}/docker-compose.yml"
QD_PORT=8923
REDIS_PORT=6379
QD_IMAGE="qdtoday/qd:latest"
QD_CONTAINER_NAME="qd"
REDIS_CONTAINER_NAME="qd_redis"

# 系统信息
OS=""
OS_VERSION=""
PACKAGE_MANAGER=""

#================================================================
# 辅助函数
#================================================================

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_step() {
    echo -e "${PURPLE}[>>]${NC} $1"
}

# 显示进度条
show_progress() {
    local duration=$1
    local message=$2
    echo -ne "${CYAN}${message}${NC} "
    for ((i=0; i<duration; i++)); do
        echo -n "."
        sleep 1
    done
    echo ""
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 检测操作系统
detect_os() {
    print_step "检测操作系统..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif command_exists lsb_release; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$(echo $DISTRIB_ID | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$DISTRIB_RELEASE
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(uname -r)
    fi

    print_success "系统: ${OS} ${OS_VERSION}"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "请使用root权限运行此脚本"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 确定包管理器
determine_package_manager() {
    if command_exists apt-get; then
        PACKAGE_MANAGER="apt"
    elif command_exists yum; then
        PACKAGE_MANAGER="yum"
    elif command_exists dnf; then
        PACKAGE_MANAGER="dnf"
    elif command_exists zypper; then
        PACKAGE_MANAGER="zypper"
    elif command_exists pacman; then
        PACKAGE_MANAGER="pacman"
    else
        print_error "无法确定包管理器"
        exit 1
    fi
    print_info "包管理器: ${PACKAGE_MANAGER}"
}

# 安装基础依赖
install_basic_dependencies() {
    print_step "安装基础依赖..."

    case "$PACKAGE_MANAGER" in
        apt)
            apt-get update -qq
            apt-get install -y wget curl git ca-certificates gnupg lsb-release >/dev/null 2>&1
            ;;
        yum)
            yum install -y wget curl git ca-certificates >/dev/null 2>&1
            ;;
        dnf)
            dnf install -y wget curl git ca-certificates >/dev/null 2>&1
            ;;
        zypper)
            zypper install -y wget curl git ca-certificates >/dev/null 2>&1
            ;;
        pacman)
            pacman -Sy --noconfirm wget curl git ca-certificates >/dev/null 2>&1
            ;;
    esac

    print_success "基础依赖安装完成"
}

# 安装Docker
install_docker() {
    if command_exists docker; then
        print_success "Docker已安装 ($(docker --version))"
        return 0
    fi

    print_step "开始安装Docker..."

    case "$PACKAGE_MANAGER" in
        apt)
            # 卸载旧版本
            apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true

            # 安装依赖
            apt-get update -qq
            apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1

            # 添加Docker官方GPG密钥
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/${OS}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >/dev/null 2>&1
            chmod a+r /etc/apt/keyrings/docker.gpg

            # 设置仓库
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} \
              $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

            # 安装Docker
            apt-get update -qq
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            ;;

        yum|dnf)
            # 卸载旧版本
            $PACKAGE_MANAGER remove -y docker docker-client docker-client-latest docker-common \
                docker-latest docker-latest-logrotate docker-logrotate docker-engine >/dev/null 2>&1 || true

            # 安装yum-utils
            $PACKAGE_MANAGER install -y yum-utils >/dev/null 2>&1

            # 添加Docker仓库
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1

            # 安装Docker
            $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            ;;

        zypper)
            zypper remove -y docker docker-engine >/dev/null 2>&1 || true
            zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo >/dev/null 2>&1
            zypper refresh >/dev/null 2>&1
            zypper install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            ;;

        pacman)
            pacman -Sy --noconfirm docker docker-compose >/dev/null 2>&1
            ;;
    esac

    # 启动Docker服务
    systemctl start docker
    systemctl enable docker >/dev/null 2>&1

    # 验证安装
    if docker --version >/dev/null 2>&1; then
        print_success "Docker安装成功 ($(docker --version | cut -d' ' -f3 | tr -d ','))"
    else
        print_error "Docker安装失败"
        exit 1
    fi
}

# 安装Docker Compose
install_docker_compose() {
    if command_exists docker && docker compose version >/dev/null 2>&1; then
        print_success "Docker Compose已安装 ($(docker compose version | cut -d' ' -f4))"
        return 0
    fi

    # 检查旧版docker-compose
    if command_exists docker-compose; then
        print_success "Docker Compose已安装 ($(docker-compose --version | cut -d' ' -f3 | tr -d ','))"
        return 0
    fi

    print_step "安装Docker Compose..."

    # 获取最新版本
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$COMPOSE_VERSION" ]; then
        COMPOSE_VERSION="v2.23.0"
    fi

    # 下载Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose >/dev/null 2>&1

    chmod +x /usr/local/bin/docker-compose

    # 创建软链接
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true

    if command_exists docker-compose; then
        print_success "Docker Compose安装成功"
    else
        print_warning "Docker Compose独立版本安装失败，将使用docker compose插件"
    fi
}

# 配置Docker镜像加速
configure_docker_mirror() {
    print_step "配置Docker镜像加速..."

    mkdir -p /etc/docker

    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://mirror.ccs.tencentyun.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    systemctl daemon-reload
    systemctl restart docker

    print_success "Docker镜像加速配置完成"
}

# 创建目录结构
create_directories() {
    print_step "创建目录结构..."

    mkdir -p "$QD_DIR"
    mkdir -p "$QD_CONFIG_DIR"
    mkdir -p "$QD_REDIS_DIR/data"

    chmod -R 755 "$QD_DIR"

    print_success "目录创建完成"
}

# 生成随机密钥
generate_random_key() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# 创建docker-compose配置文件
create_compose_file() {
    print_step "创建Docker Compose配置文件..."

    # 生成随机密钥
    COOKIE_SECRET=$(generate_random_key)
    AES_KEY=$(generate_random_key)

    cat > "$QD_COMPOSE_FILE" <<'EOF'
version: "3.8"

services:
  qd:
    image: qdtoday/qd:latest
    container_name: qd
    restart: always
    depends_on:
      - redis
    ports:
      - "8923:80"
    volumes:
      - ./config:/usr/src/app/config
    environment:
      # 基础配置
      - BIND=0.0.0.0
      - PORT=80
      - QD_DEBUG=False
      - MULTI_PROCESS=False
      - AUTO_RELOAD=False
      - GZIP=True
      - ACCESS_LOG=True

      # 域名配置（建议修改为实际域名）
      - DOMAIN=

      # 安全配置（强烈建议修改）
      - COOKIE_SECRET=CHANGE_ME_COOKIE_SECRET
      - AES_KEY=CHANGE_ME_AES_KEY
      - COOKIE_DAY=5
      - PBKDF2_ITERATIONS=400

      # 数据库配置（默认使用SQLite）
      - DB_TYPE=sqlite3

      # Redis配置
      - REDISCLOUD_URL=redis://redis:6379
      - REDIS_DB_INDEX=1

      # 安全配置
      - QD_EVIL=500
      - EVIL_PASS_LAN_IP=True

      # 任务配置
      - WORKER_METHOD=Queue
      - NEW_TASK_DELAY=1
      - TASK_WHILE_LOOP_TIMEOUT=900
      - TASK_REQUEST_LIMIT=1500
      - TASK_MAX_RETRY_COUNT=8

      # 网络配置
      - REQUEST_TIMEOUT=30.0
      - CONNECT_TIMEOUT=30.0
      - USE_PYCURL=True
      - ALLOW_RETRY=True
      - CURL_ENCODING=True

      # 推送配置
      - PUSH_BATCH_SW=True
      - PUSH_BATCH_DELTA=60

      # 用户配置
      - USER0ISADMIN=True

      # WebSocket配置
      - WS_PING_INTERVAL=5
      - WS_PING_TIMEOUT=30

      # 时区
      - TZ=Asia/Shanghai
    networks:
      - qd_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  redis:
    image: redis:7-alpine
    container_name: qd_redis
    restart: always
    command: 
      - redis-server
      - --appendonly yes
      - --appendfsync everysec
      - --maxmemory 256mb
      - --maxmemory-policy allkeys-lru
      - --loglevel warning
    volumes:
      - ./redis/data:/data
    networks:
      - qd_network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

networks:
  qd_network:
    driver: bridge

EOF

    # 替换密钥
    sed -i "s/CHANGE_ME_COOKIE_SECRET/${COOKIE_SECRET}/" "$QD_COMPOSE_FILE"
    sed -i "s/CHANGE_ME_AES_KEY/${AES_KEY}/" "$QD_COMPOSE_FILE"

    print_success "Docker Compose配置文件创建完成"
    print_info "配置文件位置: ${QD_COMPOSE_FILE}"
}

# 配置端口
configure_port() {
    print_info "当前QD访问端口: ${QD_PORT}"
    read -p "是否修改端口? (y/n，默认n): " change_port

    if [[ "$change_port" =~ ^[Yy]$ ]]; then
        read -p "请输入新端口号 (1024-65535): " new_port

        if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1024 ] && [ "$new_port" -le 65535 ]; then
            QD_PORT=$new_port
            sed -i "s/"8923:80"/"${QD_PORT}:80"/" "$QD_COMPOSE_FILE"
            print_success "端口已修改为: ${QD_PORT}"
        else
            print_warning "端口号无效，使用默认端口8923"
        fi
    fi
}

# 配置防火墙
configure_firewall() {
    print_step "配置防火墙..."

    # Firewalld
    if command_exists firewall-cmd && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${QD_PORT}/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        print_success "Firewalld规则已添加 (端口: ${QD_PORT})"
    fi

    # UFW
    if command_exists ufw && ufw status | grep -q "Status: active"; then
        ufw allow ${QD_PORT}/tcp >/dev/null 2>&1
        print_success "UFW规则已添加 (端口: ${QD_PORT})"
    fi

    # iptables
    if command_exists iptables && ! command_exists firewall-cmd && ! command_exists ufw; then
        iptables -I INPUT -p tcp --dport ${QD_PORT} -j ACCEPT >/dev/null 2>&1

        # 保存iptables规则
        if [ -d /etc/iptables ]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null
        elif [ -d /etc/sysconfig ]; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null
        fi
        print_success "Iptables规则已添加 (端口: ${QD_PORT})"
    fi
}

# 拉取Docker镜像
pull_docker_images() {
    print_step "拉取Docker镜像..."

    echo "正在拉取QD镜像..."
    docker pull ${QD_IMAGE} || {
        print_error "QD镜像拉取失败"
        exit 1
    }

    echo "正在拉取Redis镜像..."
    docker pull redis:7-alpine || {
        print_error "Redis镜像拉取失败"
        exit 1
    }

    print_success "Docker镜像拉取完成"
}

# 启动容器
start_containers() {
    print_step "启动Docker容器..."

    cd "$QD_DIR"

    if command_exists docker-compose; then
        docker-compose up -d
    else
        docker compose up -d
    fi

    show_progress 5 "等待容器启动"

    # 检查容器状态
    if docker ps | grep -q "$QD_CONTAINER_NAME"; then
        print_success "QD容器启动成功"
    else
        print_error "QD容器启动失败"
        docker logs "$QD_CONTAINER_NAME" 2>&1 | tail -20
        exit 1
    fi

    if docker ps | grep -q "$REDIS_CONTAINER_NAME"; then
        print_success "Redis容器启动成功"
    else
        print_warning "Redis容器可能未正常启动"
    fi
}

#================================================================
# 主要功能函数
#================================================================

# 完整安装流程
install_qd() {
    clear
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}   QD面板 Docker自动化安装${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""

    check_root
    detect_os
    determine_package_manager

    install_basic_dependencies
    install_docker
    install_docker_compose
    configure_docker_mirror

    # 检查是否已安装
    if [ -d "$QD_DIR" ] && [ -f "$QD_COMPOSE_FILE" ]; then
        print_warning "检测到QD已安装"
        read -p "是否重新安装? (y/n): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            print_info "取消安装"
            return
        fi
        stop_qd
        rm -rf "$QD_DIR"
    fi

    create_directories
    create_compose_file
    configure_port
    configure_firewall
    pull_docker_images
    start_containers

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}   QD面板安装成功！${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    print_success "访问地址: http://YOUR_SERVER_IP:${QD_PORT}"
    echo ""
    print_info "安装目录: ${QD_DIR}"
    print_info "配置文件: ${QD_COMPOSE_FILE}"
    print_info "数据目录: ${QD_CONFIG_DIR}"
    echo ""
    print_warning "首次注册的用户将自动成为管理员"
    print_warning "建议立即修改配置文件中的COOKIE_SECRET和AES_KEY"
    echo ""
    print_info "常用命令:"
    echo "  查看状态: docker ps"
    echo "  查看日志: docker logs -f qd"
    echo "  重启容器: docker restart qd"
    echo ""
}

# 启动QD
start_qd() {
    if [ ! -d "$QD_DIR" ]; then
        print_error "QD未安装，请先安装"
        return 1
    fi

    cd "$QD_DIR"

    if docker ps | grep -q "$QD_CONTAINER_NAME"; then
        print_warning "QD容器已在运行"
        return 0
    fi

    print_step "启动QD容器..."

    if command_exists docker-compose; then
        docker-compose start
    else
        docker compose start
    fi

    sleep 3

    if docker ps | grep -q "$QD_CONTAINER_NAME"; then
        print_success "QD容器启动成功"
    else
        print_error "QD容器启动失败"
        docker logs "$QD_CONTAINER_NAME" 2>&1 | tail -20
    fi
}

# 停止QD
stop_qd() {
    if [ ! -d "$QD_DIR" ]; then
        print_error "QD未安装"
        return 1
    fi

    cd "$QD_DIR"

    if ! docker ps | grep -q "$QD_CONTAINER_NAME"; then
        print_warning "QD容器未运行"
        return 0
    fi

    print_step "停止QD容器..."

    if command_exists docker-compose; then
        docker-compose stop
    else
        docker compose stop
    fi

    sleep 2

    if ! docker ps | grep -q "$QD_CONTAINER_NAME"; then
        print_success "QD容器已停止"
    else
        print_error "QD容器停止失败"
    fi
}

# 重启QD
restart_qd() {
    if [ ! -d "$QD_DIR" ]; then
        print_error "QD未安装"
        return 1
    fi

    cd "$QD_DIR"

    print_step "重启QD容器..."

    if command_exists docker-compose; then
        docker-compose restart
    else
        docker compose restart
    fi

    sleep 3

    if docker ps | grep -q "$QD_CONTAINER_NAME"; then
        print_success "QD容器重启成功"
    else
        print_error "QD容器重启失败"
    fi
}

# 查看状态
status_qd() {
    if [ ! -d "$QD_DIR" ]; then
        print_error "QD未安装"
        return 1
    fi

    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}   QD容器状态${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    docker ps -a --filter "name=qd" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}   容器健康状态${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    docker inspect --format='{{.Name}}: {{.State.Health.Status}}' qd 2>/dev/null || echo "健康检查未配置"

    echo ""
}

# 查看日志
logs_qd() {
    if [ ! -d "$QD_DIR" ]; then
        print_error "QD未安装"
        return 1
    fi

    print_info "显示QD容器日志 (Ctrl+C退出)..."
    echo ""
    docker logs -f --tail 100 "$QD_CONTAINER_NAME"
}

# 更新QD
update_qd() {
    if [ ! -d "$QD_DIR" ]; then
        print_error "QD未安装"
        return 1
    fi

    print_step "更新QD镜像..."

    cd "$QD_DIR"

    # 拉取最新镜像
    docker pull ${QD_IMAGE}
    docker pull redis:7-alpine

    print_step "重新创建容器..."

    if command_exists docker-compose; then
        docker-compose down
        docker-compose up -d
    else
        docker compose down
        docker compose up -d
    fi

    sleep 3

    if docker ps | grep -q "$QD_CONTAINER_NAME"; then
        print_success "QD更新成功"
    else
        print_error "QD更新失败"
    fi
}

# 卸载QD
uninstall_qd() {
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}   卸载QD面板${NC}"
    echo -e "${RED}=========================================${NC}"
    echo ""
    print_warning "此操作将删除所有数据，包括数据库和配置文件"
    echo ""
    read -p "确认卸载? 请输入 'YES' 确认: " confirm

    if [ "$confirm" != "YES" ]; then
        print_info "取消卸载"
        return
    fi

    if [ -d "$QD_DIR" ]; then
        cd "$QD_DIR"

        print_step "停止并删除容器..."
        if command_exists docker-compose; then
            docker-compose down -v
        else
            docker compose down -v
        fi

        print_step "删除安装目录..."
        rm -rf "$QD_DIR"
    fi

    print_step "删除Docker镜像..."
    docker rmi ${QD_IMAGE} >/dev/null 2>&1 || true
    docker rmi redis:7-alpine >/dev/null 2>&1 || true

    print_success "QD已完全卸载"
}

# 进入容器
enter_container() {
    if ! docker ps | grep -q "$QD_CONTAINER_NAME"; then
        print_error "QD容器未运行"
        return 1
    fi

    print_info "进入QD容器 (输入 'exit' 退出)..."
    docker exec -it "$QD_CONTAINER_NAME" /bin/sh
}

# 备份数据
backup_qd() {
    if [ ! -d "$QD_DIR" ]; then
        print_error "QD未安装"
        return 1
    fi

    BACKUP_DIR="/opt/qd_backup"
    BACKUP_FILE="qd_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    print_step "创建备份..."

    mkdir -p "$BACKUP_DIR"

    cd /opt
    tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" qd/ >/dev/null 2>&1

    if [ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]; then
        print_success "备份完成: ${BACKUP_DIR}/${BACKUP_FILE}"
        echo "备份大小: $(du -h ${BACKUP_DIR}/${BACKUP_FILE} | cut -f1)"
    else
        print_error "备份失败"
    fi
}

# 查看系统信息
show_system_info() {
    clear
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}   系统信息${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
    echo "操作系统: $(uname -s) $(uname -r)"
    echo "发行版: ${OS} ${OS_VERSION}"
    echo "架构: $(uname -m)"
    echo "CPU核心: $(nproc)"
    echo "内存: $(free -h | awk '/^Mem:/{print $2}')"
    echo "磁盘: $(df -h / | awk 'NR==2{print $2}')"
    echo ""

    if command_exists docker; then
        echo "Docker版本: $(docker --version | cut -d' ' -f3 | tr -d ',')"
    else
        echo "Docker: 未安装"
    fi

    if command_exists docker-compose; then
        echo "Docker Compose: $(docker-compose --version | cut -d' ' -f3 | tr -d ',')"
    elif docker compose version >/dev/null 2>&1; then
        echo "Docker Compose: $(docker compose version | cut -d' ' -f4)"
    else
        echo "Docker Compose: 未安装"
    fi

    echo ""

    if [ -d "$QD_DIR" ]; then
        echo "QD安装目录: ${QD_DIR}"
        echo "QD端口: ${QD_PORT}"

        if docker ps | grep -q "$QD_CONTAINER_NAME"; then
            echo "QD状态: 运行中"
        else
            echo "QD状态: 已停止"
        fi
    else
        echo "QD状态: 未安装"
    fi

    echo ""
}

#================================================================
# 菜单界面
#================================================================

show_menu() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
   ___  ____    ____                  __
  / _ \/ __ \  / __ \____ _____  ___  / /
 / , _/ / / / / /_/ / __ `/ __ \/ _ \/ / 
/ /\_/ /_/ / / ____/ /_/ / / / /  __/ /  
\_\/_____/ /_/    \__,_/_/ /_/\___/_/   

EOF
    echo -e "${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}   QD面板 Docker自动化管理脚本 v2.0${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "${BLUE}1.${NC}  安装 QD"
    echo -e "${BLUE}2.${NC}  启动 QD"
    echo -e "${BLUE}3.${NC}  停止 QD"
    echo -e "${BLUE}4.${NC}  重启 QD"
    echo -e "${BLUE}5.${NC}  查看状态"
    echo -e "${BLUE}6.${NC}  查看日志"
    echo -e "${BLUE}7.${NC}  更新 QD"
    echo -e "${BLUE}8.${NC}  卸载 QD"
    echo -e "${BLUE}9.${NC}  进入容器"
    echo -e "${BLUE}10.${NC} 备份数据"
    echo -e "${BLUE}11.${NC} 系统信息"
    echo -e "${BLUE}0.${NC}  退出脚本"
    echo ""
    echo -e "${GREEN}=========================================${NC}"
}

# 主程序
main() {
    while true; do
        show_menu
        read -p "请选择操作 [0-11]: " choice
        echo ""

        case $choice in
            1)
                install_qd
                ;;
            2)
                start_qd
                ;;
            3)
                stop_qd
                ;;
            4)
                restart_qd
                ;;
            5)
                status_qd
                ;;
            6)
                logs_qd
                ;;
            7)
                update_qd
                ;;
            8)
                uninstall_qd
                ;;
            9)
                enter_container
                ;;
            10)
                backup_qd
                ;;
            11)
                show_system_info
                ;;
            0)
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新选择"
                ;;
        esac

        echo ""
        read -p "按回车键继续..."
    done
}

# 执行主程序
main
