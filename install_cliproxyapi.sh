#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="CLIProxyAPI"
REPO_URL="https://github.com/router-for-me/CLIProxyAPI.git"
GITHUB_API_LATEST="https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest"
MIN_GO_VERSION="1.26.0"
DEFAULT_INSTALL_DIR="/opt/cliproxyapi"
DEFAULT_CONFIG_DIR="/etc/cliproxyapi"
DEFAULT_DATA_DIR="/var/lib/cliproxyapi"
DEFAULT_LOG_DIR="/var/log/cliproxyapi"
DEFAULT_BIN_PATH="/usr/local/bin/cliproxyapi"
DEFAULT_SERVICE_NAME="cliproxyapi"
DEFAULT_USER="root"
DEFAULT_GROUP="root"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

TMP_DIR=""
INSTALL_METHOD=""
RELEASE_TAG=""
RELEASE_JSON=""
RELEASE_ASSET_NAME=""
RELEASE_ASSET_URL=""

INSTALL_DIR=""
CONFIG_DIR=""
DATA_DIR=""
LOG_DIR=""
BIN_PATH=""
SERVICE_NAME=""
RUN_USER=""
RUN_GROUP=""
HOST_VALUE=""
PORT_VALUE=""
AUTH_DIR=""
API_KEY=""
ENABLE_WS_AUTH="false"
ENABLE_REMOTE_MGMT="true"
ENABLE_MGMT="true"
MGMT_KEY=""
ENABLE_TLS="false"
TLS_CERT=""
TLS_KEY=""
ENABLE_SERVICE="true"
START_NOW="true"

DISTRO_ID="unknown"
DISTRO_LIKE=""
PKG_MANAGER="unknown"
INIT_SYSTEM="unknown"
SERVICE_SUPPORTED="false"

STEP_NO=0

info() { echo -e "${BLUE}[信息]${RESET} $*"; }
warn() { echo -e "${YELLOW}[警告]${RESET} $*"; }
error() { echo -e "${RED}[错误]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[完成]${RESET} $*"; }
line() { printf '%b\n' "${DIM}────────────────────────────────────────────────────────────${RESET}"; }
headline() { echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"; line; }
kv() { printf "${BOLD}%-20s${RESET} %s\n" "$1" "$2"; }
section() { echo -e "\n${MAGENTA}${BOLD}$1${RESET}"; }
step() { STEP_NO=$((STEP_NO+1)); echo -e "\n${BOLD}${GREEN}[步骤 ${STEP_NO}]${RESET} $*"; }
reset_steps() { STEP_NO=0; }
show_box() {
  local title="$1"
  shift
  echo -e "${CYAN}${BOLD}┌─ ${title} ─${RESET}"
  while (($#)); do
    echo -e "${CYAN}${BOLD}│${RESET} $1"
    shift
  done
  echo -e "${CYAN}${BOLD}└────────────────────────────────────────────${RESET}"
}
show_warn_box() {
  local title="$1"
  shift
  echo -e "${YELLOW}${BOLD}┌─ ${title} ─${RESET}"
  while (($#)); do
    echo -e "${YELLOW}${BOLD}│${RESET} $1"
    shift
  done
  echo -e "${YELLOW}${BOLD}└────────────────────────────────────────────${RESET}"
}
show_banner() {
  clear 2>/dev/null || true
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}${BOLD}║      CLIProxyAPI 通用 Linux 管理脚本        ║${RESET}"
  echo -e "${CYAN}${BOLD}║    安装 / 更新 / 服务管理 / 日志 / 卸载     ║${RESET}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
  echo -e "${DIM}项目: ${PROJECT_NAME}    默认服务名: ${DEFAULT_SERVICE_NAME}${RESET}"
  line
}

trap 'ret=$?; if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then rm -rf "$TMP_DIR"; fi; exit $ret' EXIT

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    error "请使用 root 运行此脚本。"
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    DISTRO_ID="$(. /etc/os-release; printf '%s' "${ID:-unknown}")"
    DISTRO_LIKE="$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")"
  else
    DISTRO_ID="unknown"
    DISTRO_LIKE=""
  fi
}

detect_pkg_manager() {
  if command_exists apt-get; then
    PKG_MANAGER="apt"
  elif command_exists dnf; then
    PKG_MANAGER="dnf"
  elif command_exists yum; then
    PKG_MANAGER="yum"
  elif command_exists zypper; then
    PKG_MANAGER="zypper"
  elif command_exists apk; then
    PKG_MANAGER="apk"
  elif command_exists pacman; then
    PKG_MANAGER="pacman"
  else
    PKG_MANAGER="unknown"
  fi
}

detect_init_system() {
  if command_exists systemctl && [[ -d /run/systemd/system || "$(ps -p 1 -o comm= 2>/dev/null || true)" == "systemd" ]]; then
    INIT_SYSTEM="systemd"
    SERVICE_SUPPORTED="true"
  elif command_exists rc-service || [[ -d /run/openrc ]]; then
    INIT_SYSTEM="openrc"
    SERVICE_SUPPORTED="false"
  else
    INIT_SYSTEM="unknown"
    SERVICE_SUPPORTED="false"
  fi
}

show_platform_info() {
  detect_distro
  detect_pkg_manager
  detect_init_system
  show_box "系统环境检测" \
    "发行版：${DISTRO_ID}${DISTRO_LIKE:+ (like: ${DISTRO_LIKE})}" \
    "包管理器：${PKG_MANAGER}" \
    "Init 系统：${INIT_SYSTEM}" \
    "是否支持 systemd 服务：${SERVICE_SUPPORTED}"
}

prompt() {
  local text="$1"
  local default="${2-}"
  local ans
  if [[ -n "$default" ]]; then
    read -r -p "$text [$default]: " ans
    ans="${ans:-$default}"
  else
    read -r -p "$text: " ans
  fi
  printf '%s' "$ans"
}

prompt_secret() {
  local text="$1"
  local ans1=""
  local ans2=""
  while true; do
    read -r -s -p "$text: " ans1
    echo
    if [[ -z "$ans1" ]]; then
      warn "密码不能为空，请重新输入。"
      continue
    fi
    read -r -s -p "请再次输入以确认: " ans2
    echo
    if [[ "$ans1" != "$ans2" ]]; then
      warn "两次输入不一致，请重新输入。"
      continue
    fi
    printf '%s' "$ans1"
    return 0
  done
}

confirm() {
  local text="$1"
  local default="${2:-Y}"
  local hint ans
  if [[ "$default" =~ ^[Yy]$ ]]; then
    hint="Y/n"
  else
    hint="y/N"
  fi
  read -r -p "$text [$hint]: " ans
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy]$ ]]
}

rand_key() {
  if command_exists openssl; then
    openssl rand -hex 24
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48
  fi
}

version_ge() {
  local a="$1" b="$2"
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1)" == "$a" ]]
}

install_packages() {
  detect_pkg_manager
  local pkgs=()

  case "$PKG_MANAGER" in
    apt)
      pkgs=(curl git tar sed gawk grep coreutils ca-certificates jq unzip)
      info "使用 apt 安装依赖..."
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      pkgs=(curl git tar sed gawk grep coreutils ca-certificates jq unzip)
      info "使用 dnf 安装依赖..."
      dnf install -y "${pkgs[@]}"
      ;;
    yum)
      pkgs=(curl git tar sed gawk grep coreutils ca-certificates jq unzip)
      info "使用 yum 安装依赖..."
      yum install -y "${pkgs[@]}"
      ;;
    zypper)
      pkgs=(curl git tar sed gawk grep coreutils ca-certificates jq unzip)
      info "使用 zypper 安装依赖..."
      zypper --non-interactive install "${pkgs[@]}"
      ;;
    apk)
      pkgs=(curl git tar sed gawk grep coreutils ca-certificates jq unzip)
      info "使用 apk 安装依赖..."
      apk add --no-cache "${pkgs[@]}"
      ;;
    pacman)
      pkgs=(curl git tar sed gawk grep coreutils ca-certificates jq unzip)
      info "使用 pacman 安装依赖..."
      pacman -Sy --noconfirm "${pkgs[@]}"
      ;;
    *)
      warn "未识别到包管理器，请手动确保已安装：curl git tar sed awk grep ca-certificates jq"
      ;;
  esac
}

ensure_go() {
  local current=""
  local need_install="false"

  if command_exists go; then
    current="$(go version | awk '{print $3}' | sed 's/^go//')"
    if version_ge "$current" "$MIN_GO_VERSION"; then
      success "已检测到 Go $current"
      return 0
    fi
    warn "当前 Go 版本为 $current，但项目要求至少 $MIN_GO_VERSION"
    need_install="true"
  else
    warn "未检测到 Go 环境"
    need_install="true"
  fi

  if [[ "$need_install" == "true" ]]; then
    if ! confirm "是否自动安装/升级 Go（会覆盖 /usr/local/go）？" Y; then
      error "没有满足要求的 Go，无法继续源码编译安装。"
      exit 1
    fi

    local arch os go_arch latest_json version tarball url
    os="linux"
    arch="$(uname -m)"
    case "$arch" in
      x86_64|amd64) go_arch="amd64" ;;
      aarch64|arm64) go_arch="arm64" ;;
      armv7l) go_arch="armv6l" ;;
      *) error "暂不支持的架构：$arch"; exit 1 ;;
    esac

    latest_json="$(curl -fsSL https://go.dev/dl/?mode=json)"
    version="$(printf '%s' "$latest_json" | jq -r '.[0].version')"
    tarball="${version}.${os}-${go_arch}.tar.gz"
    url="https://go.dev/dl/${tarball}"

    info "正在下载并安装 $version ($go_arch)..."
    TMP_DIR="$(mktemp -d)"
    curl -fL "$url" -o "$TMP_DIR/go.tgz"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "$TMP_DIR/go.tgz"
    export PATH="/usr/local/go/bin:$PATH"

    if ! command_exists go; then
      error "Go 安装后仍不可用。"
      exit 1
    fi

    current="$(go version | awk '{print $3}' | sed 's/^go//')"
    if ! version_ge "$current" "$MIN_GO_VERSION"; then
      error "安装后的 Go 版本($current)仍低于要求($MIN_GO_VERSION)。"
      exit 1
    fi
    success "Go 安装完成：$current"
  fi
}

choose_install_method() {
  echo "请选择安装方式："
  echo "  1) 源码编译安装（推荐，兼容性最好）"
  echo "  2) GitHub Release 二进制安装（如果存在适配资产）"
  local choice
  choice="$(prompt '请输入编号' '1')"
  case "$choice" in
    1) INSTALL_METHOD="source" ;;
    2) INSTALL_METHOD="release" ;;
    *) warn "输入无效，默认使用源码编译安装。"; INSTALL_METHOD="source" ;;
  esac
}

fetch_latest_release_meta() {
  RELEASE_JSON="$(curl -fsSL "$GITHUB_API_LATEST")"
  RELEASE_TAG="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name // empty')"
  [[ -n "$RELEASE_TAG" ]]
}

resolve_release_asset() {
  local arch patterns re
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) patterns=('linux.*amd64' 'amd64.*linux') ;;
    aarch64|arm64) patterns=('linux.*arm64' 'arm64.*linux') ;;
    *) error "暂不支持的架构：$arch"; return 1 ;;
  esac

  fetch_latest_release_meta || return 1

  for re in "${patterns[@]}"; do
    RELEASE_ASSET_URL="$(printf '%s' "$RELEASE_JSON" | jq -r --arg re "$re" '.assets[] | select((.name|test($re; "i")) and (.name|test("tar\\.gz|tgz|zip|linux"; "i"))) | .browser_download_url' | head -n1)"
    RELEASE_ASSET_NAME="$(printf '%s' "$RELEASE_JSON" | jq -r --arg re "$re" '.assets[] | select((.name|test($re; "i")) and (.name|test("tar\\.gz|tgz|zip|linux"; "i"))) | .name' | head -n1)"
    if [[ -n "$RELEASE_ASSET_URL" && -n "$RELEASE_ASSET_NAME" ]]; then
      return 0
    fi
  done
  return 1
}

collect_install_settings() {
  reset_steps
  headline "收集安装参数"
  show_platform_info
  show_box "安装向导" \
    "接下来会引导你完成 CLIProxyAPI 安装。" \
    "建议优先选择本机监听，确认稳定后再开放公网访问。"
  INSTALL_DIR="$(prompt '源码/程序目录' "$DEFAULT_INSTALL_DIR")"
  CONFIG_DIR="$(prompt '配置目录' "$DEFAULT_CONFIG_DIR")"
  DATA_DIR="$(prompt '认证/数据目录' "$DEFAULT_DATA_DIR")"
  LOG_DIR="$(prompt '日志目录' "$DEFAULT_LOG_DIR")"
  BIN_PATH="$(prompt '二进制安装路径' "$DEFAULT_BIN_PATH")"
  SERVICE_NAME="$(prompt 'systemd 服务名' "$DEFAULT_SERVICE_NAME")"
  RUN_USER="$(prompt '运行用户' "$DEFAULT_USER")"
  RUN_GROUP="$(prompt '运行组' "$DEFAULT_GROUP")"

  echo "监听地址选项："
  echo "  1) 仅本机（127.0.0.1，更安全，推荐）"
  echo "  2) 全网卡（0.0.0.0，对外开放）"
  local host_choice
  host_choice="$(prompt '请选择' '1')"
  case "$host_choice" in
    1) HOST_VALUE="127.0.0.1" ;;
    2) HOST_VALUE="" ;;
    *) HOST_VALUE="127.0.0.1" ;;
  esac

  PORT_VALUE="$(prompt '服务监听端口 / Web 后台端口（两者共用同一个端口）' '8317')"
  AUTH_DIR="$DATA_DIR/auths"
  API_KEY="$(prompt '客户端 API Key（留空自动生成）' '')"
  API_KEY="${API_KEY:-$(rand_key)}"

  ENABLE_WS_AUTH="$(confirm '是否启用 WebSocket 鉴权（ws-auth）？' N && echo true || echo false)"
  ENABLE_REMOTE_MGMT="$(confirm '是否允许远程访问 Web 后台 / 管理接口？' Y && echo true || echo false)"
  ENABLE_MGMT="true"

  echo ""
  show_warn_box "后台安全提示" \
    "现在需要设置 Web 后台登录密码（即 Management API 密钥）。" \
    "这个密码用于后台/管理接口登录，请务必自己保存好。"
  MGMT_KEY="$(prompt_secret '请输入 Web 后台登录密码')"

  ENABLE_TLS="$(confirm '是否启用内置 TLS/HTTPS（需提前准备证书）？' N && echo true || echo false)"
  TLS_CERT=""
  TLS_KEY=""
  if [[ "$ENABLE_TLS" == "true" ]]; then
    TLS_CERT="$(prompt 'TLS 证书路径' '/etc/ssl/certs/cliproxyapi.crt')"
    TLS_KEY="$(prompt 'TLS 私钥路径' '/etc/ssl/private/cliproxyapi.key')"
  fi

  detect_init_system
  if [[ "$SERVICE_SUPPORTED" == "true" ]]; then
    ENABLE_SERVICE="true"
    START_NOW="true"
    info "检测到 systemd，默认创建服务、设置开机自启，并在安装完成后立即启动。"
  else
    ENABLE_SERVICE="false"
    START_NOW="false"
    warn "当前系统未检测到可用的 systemd，将跳过服务创建。安装完成后请手动前台运行程序。"
  fi
}

prepare_dirs() {
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$AUTH_DIR" "$LOG_DIR" "$DATA_DIR"
  chmod 700 "$DATA_DIR" "$AUTH_DIR" || true
  chmod 755 "$INSTALL_DIR" "$CONFIG_DIR" || true
}

download_source() {
  headline "获取源码"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "检测到已有源码目录，正在更新..."
    git -C "$INSTALL_DIR" fetch --tags --force
    git -C "$INSTALL_DIR" pull --ff-only
  else
    rm -rf "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
}

install_from_source() {
  headline "执行源码编译安装"
  step "安装基础依赖"
  install_packages
  step "检查 Go 环境"
  ensure_go
  step "获取项目源码"
  download_source
  step "编译二进制文件"
  export PATH="/usr/local/go/bin:$PATH"
  pushd "$INSTALL_DIR" >/dev/null
  info "开始编译二进制..."
  CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$BIN_PATH" ./cmd/server
  popd >/dev/null
  chmod 755 "$BIN_PATH"
  success "二进制已安装到：$BIN_PATH"
}

install_from_release() {
  headline "执行 Release 二进制安装"
  step "安装基础依赖"
  install_packages
  step "解析 Release 资产"
  if ! resolve_release_asset; then
    warn "没有找到适合当前系统架构的发布资产，自动回退到源码安装。"
    INSTALL_METHOD="source"
    install_from_source
    return
  fi

  info "使用发布版本：${RELEASE_TAG:-latest}"
  info "匹配到的资产：$RELEASE_ASSET_NAME"
  TMP_DIR="$(mktemp -d)"
  curl -fL "$RELEASE_ASSET_URL" -o "$TMP_DIR/asset"

  case "$RELEASE_ASSET_NAME" in
    *.tar.gz|*.tgz)
      tar -xzf "$TMP_DIR/asset" -C "$TMP_DIR"
      ;;
    *.zip)
      if ! command_exists unzip; then
        warn "当前系统缺少 unzip，尝试自动安装。"
        install_packages
      fi
      if ! command_exists unzip; then
        error "当前系统仍缺少 unzip，无法解压 zip 资产。"
        exit 1
      fi
      unzip -q "$TMP_DIR/asset" -d "$TMP_DIR/unpacked"
      ;;
    *)
      warn "未知资产格式，将尝试直接作为二进制使用。"
      ;;
  esac

  local found_bin
  found_bin="$(find "$TMP_DIR" -type f \( -name 'cliproxyapi' -o -name 'CLIProxyAPI' -o -perm -111 \) | head -n1 || true)"
  if [[ -z "$found_bin" ]]; then
    warn "未在 release 包中找到可执行文件，自动回退到源码安装。"
    INSTALL_METHOD="source"
    install_from_source
    return
  fi

  install -m 0755 "$found_bin" "$BIN_PATH"
  success "二进制已安装到：$BIN_PATH"
}

write_config() {
  headline "生成配置文件"
  step "写入配置文件"
  local cfg="$CONFIG_DIR/config.yaml"
  cat >"$cfg" <<EOF
host: "${HOST_VALUE}"
port: ${PORT_VALUE}

tls:
  enable: ${ENABLE_TLS}
  cert: "${TLS_CERT}"
  key: "${TLS_KEY}"

remote-management:
  allow-remote: ${ENABLE_REMOTE_MGMT}
  secret-key: "${MGMT_KEY}"
  disable-control-panel: false
  panel-github-repository: "https://github.com/router-for-me/Cli-Proxy-API-Management-Center"

auth-dir: "${AUTH_DIR}"

api-keys:
  - "${API_KEY}"

debug: false
pprof:
  enable: false
  addr: "127.0.0.1:8316"

commercial-mode: false
logging-to-file: true
logs-max-total-size-mb: 512
error-logs-max-files: 10
usage-statistics-enabled: true
proxy-url: ""
force-model-prefix: false
passthrough-headers: false
request-retry: 3
max-retry-credentials: 0
max-retry-interval: 30

quota-exceeded:
  switch-project: true
  switch-preview-model: true

routing:
  strategy: "round-robin"

ws-auth: ${ENABLE_WS_AUTH}
nonstream-keepalive-interval: 0
EOF
  chmod 600 "$cfg"
  success "配置文件已写入：$cfg"
}

write_env_file() {
  local envf="$CONFIG_DIR/${SERVICE_NAME}.env"
  cat >"$envf" <<EOF
CONFIG_PATH=${CONFIG_DIR}/config.yaml
EOF
  chmod 600 "$envf"
}

write_service_file() {
  headline "创建 systemd 服务"
  step "创建并启用 systemd 服务"
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
  cat >"$service_file" <<EOF
[Unit]
Description=CLIProxyAPI 服务
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${CONFIG_DIR}/${SERVICE_NAME}.env
ExecStart=${BIN_PATH} -config \$CONFIG_PATH
Restart=always
RestartSec=3
LimitNOFILE=65535
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=false
ReadWritePaths=${CONFIG_DIR} ${DATA_DIR} ${LOG_DIR} ${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  success "systemd 服务已创建，并已设为开机自启：$service_file"

  if [[ "$START_NOW" == "true" ]]; then
    systemctl restart "$SERVICE_NAME"
    sleep 2
    systemctl --no-pager --full status "$SERVICE_NAME" || true
  fi
}

show_oauth_help() {
  headline "后续 OAuth 登录命令示例"
  cat <<EOF
如需登录不同 provider，可按需执行：

  ${BIN_PATH} -config ${CONFIG_DIR}/config.yaml -login
  ${BIN_PATH} -config ${CONFIG_DIR}/config.yaml -codex-login
  ${BIN_PATH} -config ${CONFIG_DIR}/config.yaml -codex-device-login
  ${BIN_PATH} -config ${CONFIG_DIR}/config.yaml -claude-login
  ${BIN_PATH} -config ${CONFIG_DIR}/config.yaml -qwen-login
  ${BIN_PATH} -config ${CONFIG_DIR}/config.yaml -iflow-login
  ${BIN_PATH} -config ${CONFIG_DIR}/config.yaml -kimi-login

如果当前环境没有图形浏览器，可在命令后追加：-no-browser
EOF
}

show_install_summary() {
  headline "安装完成"
  local display_host local_url
  display_host="${HOST_VALUE:-0.0.0.0}"
  local_url="http://127.0.0.1:${PORT_VALUE}"

  show_box "安装结果总览" \
    "项目名称：${PROJECT_NAME}" \
    "安装方式：${INSTALL_METHOD}" \
    "服务名称：${SERVICE_NAME}" \
    "监听地址：${display_host}" \
    "监听端口：${PORT_VALUE}" \
    "Web 后台端口：${PORT_VALUE}（与服务端口共用）"

  section "路径信息"
  kv "二进制路径" "${BIN_PATH}"
  kv "配置文件" "${CONFIG_DIR}/config.yaml"
  kv "环境文件" "${CONFIG_DIR}/${SERVICE_NAME}.env"
  kv "程序目录" "${INSTALL_DIR}"
  kv "数据目录" "${DATA_DIR}"
  kv "认证目录" "${AUTH_DIR}"
  kv "日志目录" "${LOG_DIR}"

  section "认证与服务"
  kv "客户端 API Key" "${API_KEY}"
  kv "后台登录密码" "${MGMT_KEY}"
  kv "Web 后台启用" "${ENABLE_MGMT}"
  kv "允许远程后台" "${ENABLE_REMOTE_MGMT}"
  kv "开机自启" "${ENABLE_SERVICE}"
  kv "安装后启动" "${START_NOW}"

  section "访问提示"
  kv "本机访问地址" "${local_url}"
  kv "后台访问地址" "${local_url}"
  kv "接口测试地址" "${local_url}/v1/models"

  line
  echo -e "${BOLD}OpenAI 兼容接口测试示例${RESET}"
  echo "  curl ${local_url}/v1/models \\
    -H \"Authorization: Bearer ${API_KEY}\""
  echo
  if [[ "$ENABLE_SERVICE" == "true" ]]; then
    echo -e "${BOLD}常用服务管理命令${RESET}"
    echo "  systemctl status ${SERVICE_NAME}"
    echo "  systemctl restart ${SERVICE_NAME}"
    echo "  journalctl -u ${SERVICE_NAME} -f"
  else
    echo -e "${BOLD}当前系统未启用 systemd 服务${RESET}"
    echo "  请手动运行：${BIN_PATH} -config ${CONFIG_DIR}/config.yaml"
  fi
  line

  if [[ -z "$HOST_VALUE" ]]; then
    warn "当前配置为对外监听（0.0.0.0/全部网卡）。请务必搭配防火墙、反向代理或 TLS。"
  else
    info "当前仅监听本机地址，安全性更高。"
  fi

  if [[ "$ENABLE_REMOTE_MGMT" == "true" ]]; then
    warn "你已开启远程 Web 后台/管理接口。建议尽量配合 HTTPS 或仅在可信网络中使用。"
  fi
}

collect_existing_install_info() {
  SERVICE_NAME="$(prompt '请输入已安装的 systemd 服务名' "$DEFAULT_SERVICE_NAME")"
  CONFIG_DIR="$(prompt '请输入配置目录' "$DEFAULT_CONFIG_DIR")"
  INSTALL_DIR="$(prompt '请输入程序目录' "$DEFAULT_INSTALL_DIR")"
  DATA_DIR="$(prompt '请输入数据目录' "$DEFAULT_DATA_DIR")"
  LOG_DIR="$(prompt '请输入日志目录' "$DEFAULT_LOG_DIR")"
  BIN_PATH="$(prompt '请输入二进制路径' "$DEFAULT_BIN_PATH")"
}

read_config_value() {
  local key="$1"
  local file="$2"
  awk -F': ' -v k="$key" '$1==k {gsub(/^"|"$/, "", $2); print $2; exit}' "$file" 2>/dev/null || true
}

read_first_api_key() {
  local file="$1"
  awk '
    $1=="api-keys:" {in_keys=1; next}
    in_keys && $1=="-" {gsub(/"/, "", $2); print $2; exit}
    in_keys && $0 !~ /^  - / && $0 !~ /^api-keys:/ {in_keys=0}
  ' "$file" 2>/dev/null || true
}

get_lan_ip() {
  if command_exists ip; then
    ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' || true
  elif command_exists hostname; then
    hostname -I 2>/dev/null | awk '{print $1}' || true
  else
    true
  fi
}

get_public_ip() {
  curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true
}

show_current_params() {
  headline "显示当前安装参数"
  collect_existing_install_info

  local cfg="$CONFIG_DIR/config.yaml"
  local host port auth_dir api_key allow_remote secret_key ws_auth
  local enabled_state active_state service_exists lan_ip public_ip

  service_exists="否"
  enabled_state="未知"
  active_state="未知"

  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    service_exists="是"
    enabled_state="$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true)"
    active_state="$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)"
  fi

  if [[ -f "$cfg" ]]; then
    host="$(read_config_value 'host' "$cfg")"
    port="$(read_config_value 'port' "$cfg")"
    auth_dir="$(read_config_value 'auth-dir' "$cfg")"
    allow_remote="$(read_config_value '  allow-remote' "$cfg")"
    secret_key="$(read_config_value '  secret-key' "$cfg")"
    ws_auth="$(read_config_value 'ws-auth' "$cfg")"
    api_key="$(read_first_api_key "$cfg")"
  else
    host=""
    port=""
    auth_dir=""
    allow_remote=""
    secret_key=""
    ws_auth=""
    api_key=""
  fi

  lan_ip="$(get_lan_ip)"
  public_ip="$(get_public_ip)"

  section "服务状态"
  kv "服务名" "${SERVICE_NAME}"
  kv "服务文件存在" "${service_exists}"
  kv "开机自启状态" "${enabled_state}"
  kv "当前运行状态" "${active_state}"

  section "路径信息"
  kv "二进制路径" "${BIN_PATH}"
  kv "程序目录" "${INSTALL_DIR}"
  kv "配置目录" "${CONFIG_DIR}"
  kv "数据目录" "${DATA_DIR}"
  kv "日志目录" "${LOG_DIR}"
  kv "配置文件" "${cfg}"

  section "运行参数"
  kv "监听地址" "${host:-未读取到}"
  kv "监听端口" "${port:-未读取到}"
  kv "Web 后台端口" "${port:-未读取到}（与服务端口共用）"
  kv "认证目录" "${auth_dir:-未读取到}"
  kv "客户端 API Key" "${api_key:-未读取到}"
  kv "Web 后台远程访问" "${allow_remote:-未读取到}"
  kv "Web 后台登录密码" "${secret_key:-未读取到}"
  kv "WebSocket 鉴权" "${ws_auth:-未读取到}"

  section "访问地址"
  kv "本机访问地址" "http://127.0.0.1:${port:-未读取到}"
  kv "局域网访问地址" "${lan_ip:+http://${lan_ip}:${port}}${lan_ip:-未获取到}"
  kv "公网访问地址" "${public_ip:+http://${public_ip}:${port}}${public_ip:-未获取到}"
  line
}

start_service() {
  headline "启动服务"
  detect_init_system
  if [[ "$SERVICE_SUPPORTED" != "true" ]]; then
    warn "当前系统未检测到 systemd，无法通过菜单启动服务。"
    info "请手动运行：${BIN_PATH} -config ${CONFIG_DIR}/config.yaml"
    return 1
  fi

  collect_existing_install_info
  if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    error "未检测到 systemd 服务：${SERVICE_NAME}"
    return 1
  fi

  systemctl daemon-reload
  systemctl start "$SERVICE_NAME"
  sleep 2
  systemctl --no-pager --full status "$SERVICE_NAME" || true
}

stop_service() {
  headline "停止服务"
  detect_init_system
  if [[ "$SERVICE_SUPPORTED" != "true" ]]; then
    warn "当前系统未检测到 systemd，无法通过菜单停止服务。"
    return 1
  fi

  collect_existing_install_info
  if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    error "未检测到 systemd 服务：${SERVICE_NAME}"
    return 1
  fi

  systemctl stop "$SERVICE_NAME"
  sleep 2
  systemctl --no-pager --full status "$SERVICE_NAME" || true
}

restart_service() {
  headline "重启服务"
  detect_init_system
  if [[ "$SERVICE_SUPPORTED" != "true" ]]; then
    warn "当前系统未检测到 systemd，无法通过菜单重启服务。"
    info "请手动停止并重新运行：${BIN_PATH} -config ${CONFIG_DIR}/config.yaml"
    return 1
  fi

  collect_existing_install_info
  if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    error "未检测到 systemd 服务：${SERVICE_NAME}"
    return 1
  fi

  systemctl daemon-reload
  systemctl restart "$SERVICE_NAME"
  sleep 2
  systemctl --no-pager --full status "$SERVICE_NAME" || true
}

show_service_status() {
  headline "查看服务状态"
  detect_init_system
  if [[ "$SERVICE_SUPPORTED" != "true" ]]; then
    warn "当前系统未检测到 systemd，无法通过菜单查看 systemd 服务状态。"
    info "请手动检查进程或直接前台运行：${BIN_PATH} -config ${CONFIG_DIR}/config.yaml"
    return 1
  fi

  collect_existing_install_info
  if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    error "未检测到 systemd 服务：${SERVICE_NAME}"
    return 1
  fi

  systemctl --no-pager --full status "$SERVICE_NAME" || true
}

show_service_logs() {
  headline "查看实时日志"
  detect_init_system
  if [[ "$SERVICE_SUPPORTED" != "true" ]]; then
    warn "当前系统未检测到 systemd，无法通过 journalctl 查看服务日志。"
    info "如果你是手动前台运行，请直接查看当前终端输出。"
    return 1
  fi

  collect_existing_install_info
  if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    error "未检测到 systemd 服务：${SERVICE_NAME}"
    return 1
  fi

  info "按 Ctrl+C 退出日志查看。"
  journalctl -u "$SERVICE_NAME" -f --no-pager || true
}

update_program() {
  headline "更新 CLIProxyAPI"
  collect_existing_install_info

  if [[ ! -x "$BIN_PATH" ]]; then
    warn "未找到可执行文件：$BIN_PATH"
    if ! confirm "仍然继续更新吗？" N; then
      return
    fi
  fi

  if [[ -f "$CONFIG_DIR/config.yaml" ]]; then
    info "检测到现有配置文件：$CONFIG_DIR/config.yaml"
  else
    warn "未找到配置文件：$CONFIG_DIR/config.yaml"
  fi

  choose_install_method
  case "$INSTALL_METHOD" in
    source) install_from_source ;;
    release) install_from_release ;;
    *) error "未知安装方式：$INSTALL_METHOD"; exit 1 ;;
  esac

  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    if confirm "检测到 systemd 服务 ${SERVICE_NAME}，是否现在重启服务？" Y; then
      systemctl daemon-reload
      systemctl restart "$SERVICE_NAME"
      systemctl --no-pager --full status "$SERVICE_NAME" || true
    fi
  else
    warn "未检测到 systemd 服务 ${SERVICE_NAME}，已仅完成程序更新。"
  fi

  success "更新完成。"
}

uninstall_program() {
  headline "卸载 CLIProxyAPI"
  collect_existing_install_info

  show_warn_box "即将卸载以下内容" \
    "服务名：$SERVICE_NAME" \
    "二进制：$BIN_PATH" \
    "配置目录：$CONFIG_DIR" \
    "程序目录：$INSTALL_DIR" \
    "数据目录：$DATA_DIR" \
    "日志目录：$LOG_DIR"
  warn "卸载操作可能删除配置、认证信息和日志，请确认后继续。"

  local remove_config remove_data remove_logs remove_program
  remove_config="$(confirm '是否删除配置目录？' N && echo true || echo false)"
  remove_data="$(confirm '是否删除数据目录（含 auth/token 等）？' N && echo true || echo false)"
  remove_logs="$(confirm '是否删除日志目录？' N && echo true || echo false)"
  remove_program="$(confirm '是否删除程序目录？' N && echo true || echo false)"

  if ! confirm '确认开始卸载？' N; then
    echo '已取消卸载。'
    return
  fi

  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    info "停止并禁用 systemd 服务：$SERVICE_NAME"
    systemctl stop "$SERVICE_NAME" || true
    systemctl disable "$SERVICE_NAME" || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    systemctl reset-failed || true
  else
    warn "未检测到 systemd 服务 ${SERVICE_NAME}"
  fi

  rm -f "$BIN_PATH"
  rm -f "$CONFIG_DIR/${SERVICE_NAME}.env"

  [[ "$remove_config" == "true" ]] && rm -rf "$CONFIG_DIR"
  [[ "$remove_data" == "true" ]] && rm -rf "$DATA_DIR"
  [[ "$remove_logs" == "true" ]] && rm -rf "$LOG_DIR"
  [[ "$remove_program" == "true" ]] && rm -rf "$INSTALL_DIR"

  success "卸载完成。"
}

do_install() {
  headline "安装 CLIProxyAPI"
  choose_install_method
  collect_install_settings
  step "准备目录结构"
  prepare_dirs

  case "$INSTALL_METHOD" in
    source) install_from_source ;;
    release) install_from_release ;;
    *) error "未知安装方式：$INSTALL_METHOD"; exit 1 ;;
  esac

  write_config
  write_env_file
  if [[ "$ENABLE_SERVICE" == "true" ]]; then
    write_service_file
  fi
  show_oauth_help
  show_install_summary
}

show_menu() {
  show_banner
  echo -e "${BOLD}请选择操作：${RESET}"
  echo -e "  ${GREEN}1)${RESET} 安装 CLIProxyAPI"
  echo -e "  ${GREEN}2)${RESET} 更新 CLIProxyAPI"
  echo -e "  ${GREEN}3)${RESET} 启动 CLIProxyAPI 服务"
  echo -e "  ${GREEN}4)${RESET} 停止 CLIProxyAPI 服务"
  echo -e "  ${GREEN}5)${RESET} 重启 CLIProxyAPI 服务"
  echo -e "  ${GREEN}6)${RESET} 查看服务状态"
  echo -e "  ${GREEN}7)${RESET} 查看实时日志"
  echo -e "  ${GREEN}8)${RESET} 显示当前安装参数"
  echo -e "  ${GREEN}9)${RESET} 卸载 CLIProxyAPI"
  echo -e "  ${GREEN}0)${RESET} 退出脚本"
  line
}

main() {
  require_root
  while true; do
    show_menu
    local choice
    choice="$(prompt '请输入菜单编号' '1')"
    case "$choice" in
      1) do_install ;;
      2) update_program ;;
      3) start_service ;;
      4) stop_service ;;
      5) restart_service ;;
      6) show_service_status ;;
      7) show_service_logs ;;
      8) show_current_params ;;
      9) uninstall_program ;;
      0)
        success "已退出脚本。"
        exit 0
        ;;
      *) warn "无效选项，请重新输入。" ;;
    esac
    echo
    read -r -p "按回车键返回主菜单..." _ || true
  done
}

main "$@"
