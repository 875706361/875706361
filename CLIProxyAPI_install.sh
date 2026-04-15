#!/usr/bin/env bash
# Version: 2024-04-15-02

set -e

# ------------------- 颜色定义 -------------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error(){ echo -e "${RED}[ERROR]${NC} $*" >&2; }
success(){ echo -e "${GREEN}[OK]${NC} $*"; }

# ------------------- 标题 -------------------
print_header(){
cat <<'EOF'
  ____ _     ___   ____            _ ____                  
 / ___| |   |_ _| |  _ \ ___  __ _| |  _ \ ___  ___ ___    
| |   | |    | |  | |_) / _ \/ _` | | |_) / _ \/ __/ __|   
| |___| |___ | |  |  __/  __/ (_| | |  __/ (_) \__ \__ \   
 \____|_____|___| |_|   \___|\__,_|_|_|   \___/|___/___/   
                                                         
EOF
echo -e "${MAGENTA}CLIProxyAPI Interactive Installer${NC}"
echo -e "${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo "------------------------------------------------------------"
}

# ------------------- 安装 Python 依赖（含自动系统依赖） -------------------
install_python_requirements(){
    # 常见的系统构建依赖，防止编译 C 扩展失败
    local sys_deps=(build-essential libssl-dev libffi-dev python3-dev)
    info "检查并安装系统依赖: ${sys_deps[*]}"
    $SUDO apt-get update -y
    $SUDO apt-get install -y "${sys_deps[@]}"

    info "安装 Python 依赖 (requirements.txt)"
    # 使用 pip 安装，如果失败则尝试重新安装系统依赖后再重试一次
    if ! pip install -r requirements.txt; then
        warn "第一次 pip 安装失败，重新安装系统依赖后再尝试一次"
        $SUDO apt-get install -y "${sys_deps[@]}"
        pip install -r requirements.txt || error "pip 安装仍失败，请检查 requirements.txt 内容"
    fi
    success "Python 依赖已成功安装"
}

# ------------------- UI \u52a9\u7684\u51fd\u6570 -------------------
print_separator(){ echo -e "${MAGENTA}----------------------------------------${NC}"; }
run_step(){
    local desc="$1"
    shift
    info "${desc}..."
    "$@"
    local status=$?
    if [ $status -eq 0 ]; then
        success "${desc} \u5b8c\u6210"
    else
        error "${desc} \u5931\u8d25 (code $status)"
        exit $status
    fi
}

check_requirements(){
    local missing=()
    for cmd in git python3 python3-venv; do
        command -v $cmd >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ ${#missing[@]} -ne 0 ]; then
        info "即将安装缺失的依赖：${missing[*]}"
        $SUDO apt-get update -y
        $SUDO apt-get install -y "${missing[@]}"
    else
        success "所有必备工具已就绪"
    fi
}

# ------------------- 安装主流程 -------------------
install_cli_proxy(){
    # 1. 安装目录
    read -rp "请输入安装目录 [/opt/CLIProxyAPI]: " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/opt/CLIProxyAPI}
    if [[ ! "$INSTALL_DIR" =~ ^/ ]]; then
        error "必须使用绝对路径"
        return 1
    fi

    # 2. 是否需要 sudo
    if [[ "$INSTALL_DIR" == /opt/* && $EUID -ne 0 ]]; then
        SUDO='sudo'
    else
        SUDO=''
    fi

    # 3. 检查依赖
    check_requirements

    # 4. 克隆或更新仓库
    if [[ -d "$INSTALL_DIR" ]]; then
        info "目录已存在，拉取最新代码..."
        cd "$INSTALL_DIR"
        git pull origin main
    else
        info "克隆仓库到 $INSTALL_DIR"
        $SUDO git clone https://github.com/router-for-me/Cli-Proxy-API-Management-Center "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi

    # 5. 创建虚拟环境
    VENV_DIR="$INSTALL_DIR/.venv"
    if [[ -d "$VENV_DIR" ]]; then
        success "虚拟环境已存在"
    else
        info "创建 Python 虚拟环境..."
        python3 -m venv "$VENV_DIR"
    fi

    # 6. 安装 Python 依赖（自动系统依赖）
    source "$VENV_DIR/bin/activate"
    if [[ -f requirements.txt ]]; then
        run_step "安装 Python 依赖" install_python_requirements
    else
        warn "未找到 requirements.txt，跳过 pip 安装"
    fi

    # 7. 配置参数
    read -rp "Web 登录密码 (默认 admin): " WEB_PASS
    WEB_PASS=${WEB_PASS:-admin}
    read -rp "API 监听端口 (默认 8000): " API_PORT
    API_PORT=${API_PORT:-8000}

    cat > "$INSTALL_DIR/config.yaml" <<EOF
# 自动生成的 CLIProxyAPI 配置文件
router:
  host: 192.168.1.1
  username: admin
  password: $WEB_PASS
api:
  listen: 0.0.0.0:$API_PORT
  token: changeme
EOF
    success "配置已写入 $INSTALL_DIR/config.yaml"

    # 8. 是否创建 systemd 服务
    read -rp "是否创建 systemd 服务并开机自启？(y/N): " ANSWER
    if [[ $ANSWER =~ ^[Yy]$ ]]; then
        SERVICE_FILE="/etc/systemd/system/cli-proxy-api.service"
        info "写入 service 文件 $SERVICE_FILE"
        $SUDO bash -c "cat > $SERVICE_FILE <<'EOT'
[Unit]
Description=CLIProxyAPI Service
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python -m cli_proxy_api
Restart=on-failure
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOT"
        $SUDO systemctl daemon-reload
        $SUDO systemctl enable cli-proxy-api.service
        $SUDO systemctl start cli-proxy-api.service
        success "systemd 服务已启动"
    fi
}

# ------------------- 重启服务 -------------------
restart_service(){
    if [[ -f /etc/systemd/system/cli-proxy-api.service ]]; then
        $SUDO systemctl restart cli-proxy-api.service && success "服务已重启"
    else
        warn "systemd 服务文件不存在，无法重启"
    fi
}

# ------------------- 查看信息 -------------------
show_info(){
    echo -e "${CYAN}--- 当前安装信息 ---${NC}"
    echo "安装目录   : ${INSTALL_DIR:-未安装}"
    echo "虚拟环境   : ${VENV_DIR:-未安装}"
    echo "Web 密码   : ${WEB_PASS:-未设置}"
    echo "API 端口   : ${API_PORT:-未设置}"
    if systemctl is-active --quiet cli-proxy-api.service; then
        echo -e "Systemd 服务 : ${GREEN}已安装并运行${NC}"
    else
        echo -e "Systemd 服务 : ${RED}未安装或未运行${NC}"
    fi
}

# ------------------- 卸载 -------------------
uninstall_cli(){
    info "开始卸载 CLIProxyAPI..."
    if [[ -f /etc/systemd/system/cli-proxy-api.service ]]; then
        $SUDO systemctl stop cli-proxy-api.service || true
        $SUDO systemctl disable cli-proxy-api.service || true
        $SUDO rm -f /etc/systemd/system/cli-proxy-api.service
        $SUDO systemctl daemon-reload
        success "systemd 服务已删除"
    fi
    if [[ -n "$INSTALL_DIR" && -d "$INSTALL_DIR" ]]; then
        $SUDO rm -rf "$INSTALL_DIR"
        success "删除目录 $INSTALL_DIR"
    fi
}

# ------------------- 主菜单 -------------------
main_menu(){
    while true; do
        print_separator
        echo -e "${MAGENTA}请选择操作:${NC}"
        echo -e "${CYAN}1)${NC} 安装 CLIProxyAPI"
        echo -e "${CYAN}2)${NC} 重启 CLIProxyAPI 服务"
        echo -e "${CYAN}3)${NC} 查看安装信息"
        echo -e "${CYAN}4)${NC} 卸载 CLIProxyAPI"
        echo -e "${CYAN}0)${NC} 退出"
        read -rp "输入选项 [0-4]: " CHOICE
        case $CHOICE in
            1) install_cli_proxy ;;
            2) restart_service ;;
            3) show_info ;;
            4) uninstall_cli ;;
            0) echo "祝使用愉快！"; break ;;
            *) warn "无效选项，请重新输入" ;;
        esac
        pause
    done
}

pause(){ read -rp "按回车键继续..."; }

# 入口
print_header
main_menu
