#!/bin/bash

QD_ROOT="$PWD/qd"
CONFIG_DIR="$QD_ROOT/config"
YML_URL="https://fastly.jsdelivr.net/gh/qd-today/qd@master/docker-compose.yml"
YML_FILE="$QD_ROOT/docker-compose.yml"
RED='\033[0;31m'
GRN='\033[0;32m'
YELL='\033[1;33m'
NC='\033[0m'

print() { echo -e "${GRN}[$(date +%H:%M:%S)]${NC} $*"; }
error() { echo -e "${RED}[ERROR] $*${NC}"; }
warn()  { echo -e "${YELL}[WARN ] $*${NC}"; }

# 安装docker函数
install_docker() {
  if command -v docker >/dev/null 2>&1; then print "Docker已安装"; return; fi
  print "安装Docker..."
  curl -fsSL https://get.docker.com | bash || { error "Docker安装失败"; exit 2; }
  systemctl enable docker && systemctl start docker
}

# 安装docker-compose
install_compose() {
  if command -v docker-compose >/dev/null 2>&1; then print "docker-compose已安装"; return; fi
  if docker compose version >/dev/null 2>&1; then print "docker compose插件已支持"; return; fi
  VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f4)
  curl -L "https://github.com/docker/compose/releases/download/$VER/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
  print "docker-compose安装完成"
}

# 下载YML文件
fetch_yml() {
  mkdir -p "$CONFIG_DIR"
  cd "$QD_ROOT" || exit 1
  wget -O docker-compose.yml "$YML_URL"
  print "docker-compose.yml已下载到$QD_ROOT"
}

# 一键启动
qd_up()   { cd "$QD_ROOT" && (docker-compose up -d || docker compose up -d); }
qd_stop() { cd "$QD_ROOT" && (docker-compose stop   || docker compose stop); }
qd_down() { cd "$QD_ROOT" && (docker-compose down   || docker compose down); }
qd_log()  { cd "$QD_ROOT" && (docker-compose logs -f || docker compose logs -f); }
qd_pull() { cd "$QD_ROOT" && (docker-compose pull   || docker compose pull); }

menu() {
  while true; do
    echo -e "${GRN}\n========== QD Docker 运维菜单 ==========${NC}"
    echo "1. 安装docker+compose"
    echo "2. 创建/同步目录并下载 docker-compose.yml"
    echo "3. 编辑配置文件"
    echo "4. 启动QD"
    echo "5. 停止QD"
    echo "6. 查看日志"
    echo "7. 更新镜像并重启QD"
    echo "8. 卸载（停止并清空目录）"
    echo "0. 退出"
    read -rp "请选择[0-8]：" n
    case "$n" in
      1) install_docker; install_compose; ;;
      2) fetch_yml ;;
      3) vi "$YML_FILE" ;;
      4) qd_up; print "启动完成: http://<你的IP>:8923"; ;;
      5) qd_stop; print "已停止"; ;;
      6) qd_log ;;
      7) qd_pull; qd_up; print "已更新并重启"; ;;
      8) qd_down; rm -rf "$QD_ROOT"; print "已全部卸载"; ;;
      0) exit 0 ;;
      *) warn "输入错误";;
    esac
  done
}

# 主流程
menu
