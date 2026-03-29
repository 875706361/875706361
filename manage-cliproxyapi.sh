#!/usr/bin/env bash
set -euo pipefail

DEPLOY="${DEPLOY:-$HOME/cliproxyapi}"
BIN_NAME="${BIN_NAME:-cli-proxy-api}"
BIN_PATH="$DEPLOY/$BIN_NAME"
CONFIG_PATH="$DEPLOY/config.yaml"
VERSION_PATH="$DEPLOY/version.txt"
SERVICE_PATH="$DEPLOY/cliproxyapi.service"
LOG_PATH="$DEPLOY/nohup.out"

REPO="router-for-me/CLIProxyAPI"
API_LATEST="https://api.github.com/repos/${REPO}/releases/latest"
TTY="/dev/tty"

if [ -t 1 ] || [ -w "$TTY" ]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_MAGENTA='\033[35m'
  C_CYAN='\033[36m'
  C_WHITE='\033[37m'
else
  C_RESET=''
  C_BOLD=''
  C_DIM=''
  C_RED=''
  C_GREEN=''
  C_YELLOW=''
  C_BLUE=''
  C_MAGENTA=''
  C_CYAN=''
  C_WHITE=''
fi

out() {
  if [ -w "$TTY" ]; then
    printf '%b\n' "$1" > "$TTY"
  else
    printf '%b\n' "$1"
  fi
}

inline() {
  if [ -w "$TTY" ]; then
    printf '%b' "$1" > "$TTY"
  else
    printf '%b' "$1"
  fi
}

line() {
  out "${C_DIM}============================================================${C_RESET}"
}

info() {
  out "${C_CYAN}[INFO]${C_RESET} $*"
}

ok() {
  out "${C_GREEN}[ OK ]${C_RESET} $*"
}

warn() {
  out "${C_YELLOW}[WARN]${C_RESET} $*"
}

err() {
  out "${C_RED}[ERR ]${C_RESET} $*"
}

step() {
  out "${C_BLUE}==>${C_RESET} $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "缺少命令: $1"
    exit 1
  }
}

install_pkg_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl tar findutils procps coreutils grep sed
}

install_pkg_dnf() {
  dnf install -y curl tar findutils procps-ng coreutils grep sed
}

install_pkg_yum() {
  yum install -y curl tar findutils procps-ng coreutils grep sed
}

install_pkg_apk() {
  apk add --no-cache curl tar findutils procps coreutils grep sed
}

auto_install_deps() {
  local missing=0
  for cmd in curl tar find pgrep pkill install grep sed; do
    command -v "$cmd" >/dev/null 2>&1 || missing=1
  done
  [ "$missing" -eq 0 ] && return 0

  warn "检测到缺少依赖，尝试自动安装..."
  if command -v apt-get >/dev/null 2>&1; then
    install_pkg_apt
  elif command -v dnf >/dev/null 2>&1; then
    install_pkg_dnf
  elif command -v yum >/dev/null 2>&1; then
    install_pkg_yum
  elif command -v apk >/dev/null 2>&1; then
    install_pkg_apk
  else
    err "无法识别包管理器，请手动安装：curl tar findutils procps coreutils grep sed"
    exit 1
  fi
}

auto_install_deps

need_cmd curl
need_cmd tar
need_cmd find
need_cmd pgrep
need_cmd pkill
need_cmd install
need_cmd grep
need_cmd sed

_timestamp() {
  date +%F-%H%M%S
}

press_enter() {
  if [ -r "$TTY" ] && [ -w "$TTY" ]; then
    inline "\n${C_DIM}按回车继续...${C_RESET}"
    read -r _ < "$TTY" || true
  fi
}

prompt_input() {
  local prompt="$1"
  local value=""
  if [ -r "$TTY" ] && [ -w "$TTY" ]; then
    inline "${C_BOLD}${prompt}${C_RESET}"
    read -r value < "$TTY" || true
  else
    printf '%s' "$prompt"
    read -r value || true
  fi
  printf '%s' "$value"
}

clear_screen() {
  if [ -w "$TTY" ]; then
    printf '\033[2J\033[H' > "$TTY"
  else
    clear 2>/dev/null || true
  fi
}

current_version() {
  if [ -f "$VERSION_PATH" ]; then
    tr -d '\r' < "$VERSION_PATH"
  else
    printf '%s' '未安装'
  fi
}

current_status() {
  if pgrep -af "$BIN_NAME" >/dev/null 2>&1; then
    printf '%s' '运行中'
  else
    printf '%s' '未运行'
  fi
}

print_header() {
  clear_screen
  line
  out "${C_BOLD}${C_MAGENTA}  CLIProxyAPI 管理中心${C_RESET}"
  out "${C_DIM}  部署目录:${C_RESET} $DEPLOY"
  out "${C_DIM}  当前版本:${C_RESET} ${C_BOLD}$(current_version)${C_RESET}"
  if [ "$(current_status)" = "运行中" ]; then
    out "${C_DIM}  运行状态:${C_RESET} ${C_GREEN}运行中${C_RESET}"
  else
    out "${C_DIM}  运行状态:${C_RESET} ${C_YELLOW}未运行${C_RESET}"
  fi
  line
}

latest_tag() {
  curl -fsSL "$API_LATEST" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n1 | cut -d'"' -f4
}

backup_dir() {
  echo "$HOME/cliproxyapi-backup-$(_timestamp)"
}

full_backup_file() {
  echo "$HOME/cliproxyapi-full-backup-$(_timestamp).tar.gz"
}

ensure_deploy_dir() {
  mkdir -p "$DEPLOY"
}

status_info() {
  print_header
  out "${C_BOLD}${C_BLUE}状态总览${C_RESET}"
  line
  out "${C_DIM}二进制路径:${C_RESET} $BIN_PATH"
  if [ -f "$BIN_PATH" ]; then
    ls -lh "$BIN_PATH"
  else
    warn "未找到二进制"
  fi
  out ""
  out "${C_DIM}配置文件:${C_RESET} $CONFIG_PATH"
  if [ -f "$CONFIG_PATH" ]; then
    ls -lh "$CONFIG_PATH"
  else
    warn "未找到 config.yaml（首次安装后可按需自行添加）"
  fi
  out ""
  out "${C_DIM}进程信息:${C_RESET}"
  pgrep -af "$BIN_NAME" || warn "未运行"
  out ""
  out "${C_DIM}最近备份:${C_RESET}"
  ls -dt "$HOME"/cliproxyapi-backup-* 2>/dev/null | head -n 5 || warn "暂无"
  press_enter
}

stop_app() {
  step "停止服务"
  pkill -f "/root/cliproxyapi/${BIN_NAME}|./${BIN_NAME}" || true
  sleep 1
  if pgrep -af "$BIN_NAME" >/dev/null 2>&1; then
    warn "仍检测到进程："
    pgrep -af "$BIN_NAME" || true
  else
    ok "已停止"
  fi
}

restart_app() {
  ensure_deploy_dir
  if [ ! -x "$BIN_PATH" ]; then
    err "未检测到已安装二进制：$BIN_PATH"
    info "请先执行“更新到最新版本（保留数据）”，脚本会自动完成首次安装。"
    return 1
  fi
  step "重启服务"
  stop_app || true
  cd "$DEPLOY"
  nohup "./${BIN_NAME}" > "$LOG_PATH" 2>&1 &
  disown || true
  sleep 2
  ok "已重启"
  pgrep -af "$BIN_NAME" || true
}

install_autostart() {
  step "配置开机自启"
  if ! command -v systemctl >/dev/null 2>&1; then
    err "当前系统没有 systemd/systemctl，无法配置开机自启"
    return 1
  fi
  if [ ! -x "$BIN_PATH" ]; then
    err "未检测到已安装二进制：$BIN_PATH"
    info "请先执行“更新到最新版本（保留数据）”，脚本会自动完成首次安装。"
    return 1
  fi

  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=CLIProxyAPI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$DEPLOY
ExecStart=$BIN_PATH
Restart=always
RestartSec=3
User=$(id -un)
Environment=HOME=$HOME

[Install]
WantedBy=multi-user.target
EOF

  cp -f "$SERVICE_PATH" /etc/systemd/system/cliproxyapi.service
  systemctl daemon-reload
  systemctl enable cliproxyapi.service
  systemctl restart cliproxyapi.service
  ok "已启用开机自启并重启服务"
  systemctl status cliproxyapi.service --no-pager -l | sed -n '1,20p' || true
}

create_backup() {
  local backup
  backup="$(backup_dir)"
  mkdir -p "$backup"

  [ -f "$BIN_PATH" ] && cp -a "$BIN_PATH" "$backup/" || true
  [ -f "$CONFIG_PATH" ] && cp -a "$CONFIG_PATH" "$backup/" || true
  [ -f "$VERSION_PATH" ] && cp -a "$VERSION_PATH" "$backup/" || true
  [ -f "$SERVICE_PATH" ] && cp -a "$SERVICE_PATH" "$backup/" || true
  [ -d "$DEPLOY/static" ] && cp -a "$DEPLOY/static" "$backup/static" || true

  printf '%s' "$backup"
}

create_full_backup() {
  local tarball
  ensure_deploy_dir
  tarball="$(full_backup_file)"
  tar -czf "$tarball" -C "$HOME" "$(basename "$DEPLOY")"
  printf '%s' "$tarball"
}

install_release_files() {
  local tag="$1" ver="$2" url="$3" tmp newbin newstatic
  ensure_deploy_dir

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  cd "$tmp"
  step "下载版本 $tag"
  curl -fL "$url" -o release.tar.gz
  tar -xzf release.tar.gz

  newbin="$(find . -type f \( -name cli-proxy-api -o -name CLIProxyAPI -o -name cliproxyapi \) | head -n1)"
  if [ -z "${newbin:-}" ]; then
    err "未找到新二进制"
    exit 1
  fi

  step "替换二进制"
  install -m 755 "$newbin" "$BIN_PATH.new"

  newstatic="$(find . -type d -name static | head -n1 || true)"
  if [ -n "${newstatic:-}" ]; then
    step "更新静态资源"
    if [ -d "$DEPLOY/static" ]; then
      mv "$DEPLOY/static" "$DEPLOY/static.bak.$(date +%s)" 2>/dev/null || true
    fi
    cp -a "$newstatic" "$DEPLOY/static"
  fi

  mv "$BIN_PATH.new" "$BIN_PATH"
  printf "%s\n" "$ver" > "$VERSION_PATH"
  ok "文件已更新到 $tag"
}

fresh_install() {
  local tag ver url
  tag="$(latest_tag)"
  ver="${tag#v}"
  url="https://github.com/${REPO}/releases/download/${tag}/CLIProxyAPI_${ver}_linux_amd64.tar.gz"

  print_header
  out "${C_BOLD}${C_GREEN}首次安装向导${C_RESET}"
  line
  info "检测到当前为全新环境，开始首次安装: $tag"
  install_release_files "$tag" "$ver" "$url"
  ok "首次安装完成: $tag"
  info "若后续需要自定义配置，可在 $CONFIG_PATH 自行添加 config.yaml"
  restart_app || true
}

update_latest() {
  local tag ver url backup
  tag="$(latest_tag)"
  ver="${tag#v}"
  url="https://github.com/${REPO}/releases/download/${tag}/CLIProxyAPI_${ver}_linux_amd64.tar.gz"

  if [ ! -x "$BIN_PATH" ]; then
    fresh_install
    return 0
  fi

  print_header
  out "${C_BOLD}${C_BLUE}升级向导${C_RESET}"
  line
  info "准备更新到: $tag"
  backup="$(create_backup)"
  ok "已创建备份: $backup"

  install_release_files "$tag" "$ver" "$url"
  restart_app
  ok "更新完成: $tag"
  info "备份目录: $backup"
}

rollback_menu() {
  local selected idx confirm
  print_header
  out "${C_BOLD}${C_YELLOW}回滚向导${C_RESET}"
  line
  out "可用备份："
  ls -dt "$HOME"/cliproxyapi-backup-* 2>/dev/null | nl -w2 -s'. ' || {
    warn "没有可回滚的备份"
    press_enter
    return
  }
  out ""
  idx="$(prompt_input '输入要回滚的序号: ')"

  selected="$(ls -dt "$HOME"/cliproxyapi-backup-* 2>/dev/null | sed -n "${idx}p" || true)"
  if [ -z "${selected:-}" ]; then
    err "无效序号"
    press_enter
    return
  fi

  info "将回滚到: $selected"
  confirm="$(prompt_input '确认回滚？[y/N]: ')"
  case "${confirm:-N}" in
    y|Y)
      [ -f "$selected/$BIN_NAME" ] && cp -a "$selected/$BIN_NAME" "$BIN_PATH"
      [ -f "$selected/version.txt" ] && cp -a "$selected/version.txt" "$VERSION_PATH" || true
      if [ -d "$selected/static" ]; then
        mv "$DEPLOY/static" "$DEPLOY/static.rollback.bak.$(date +%s)" 2>/dev/null || true
        cp -a "$selected/static" "$DEPLOY/static"
      fi
      restart_app
      ok "回滚完成"
      ;;
    *)
      warn "已取消"
      ;;
  esac
  press_enter
}

show_logs() {
  print_header
  out "${C_BOLD}${C_WHITE}最近日志${C_RESET}"
  line
  if [ -f "$LOG_PATH" ]; then
    tail -n 80 "$LOG_PATH"
  else
    warn "未找到日志: $LOG_PATH"
  fi
  press_enter
}

main_menu() {
  local choice f
  while true; do
    print_header
    out "${C_BOLD}1)${C_RESET} ${C_GREEN}更新到最新版本（保留数据）${C_RESET}"
    out "${C_BOLD}2)${C_RESET} ${C_YELLOW}回滚到备份版本${C_RESET}"
    out "${C_BOLD}3)${C_RESET} ${C_CYAN}重启当前服务${C_RESET}"
    out "${C_BOLD}4)${C_RESET} ${C_RED}停止当前服务${C_RESET}"
    out "${C_BOLD}5)${C_RESET} ${C_MAGENTA}安装/启用开机自启（systemd）${C_RESET}"
    out "${C_BOLD}6)${C_RESET} 查看当前状态"
    out "${C_BOLD}7)${C_RESET} 查看最近日志"
    out "${C_BOLD}8)${C_RESET} 创建整目录压缩备份"
    out "${C_BOLD}0)${C_RESET} 退出"
    out ""

    choice="$(prompt_input '请选择: ')"
    out ""
    case "$choice" in
      1) update_latest; press_enter ;;
      2) rollback_menu ;;
      3) restart_app; press_enter ;;
      4) stop_app; press_enter ;;
      5) install_autostart; press_enter ;;
      6) status_info ;;
      7) show_logs ;;
      8)
        print_header
        out "${C_BOLD}${C_BLUE}整目录备份${C_RESET}"
        line
        f="$(create_full_backup)"
        ok "已创建整目录备份: $f"
        press_enter
        ;;
      0)
        ok "退出"
        exit 0
        ;;
      *)
        err "无效选项"
        press_enter
        ;;
    esac
  done
}

ensure_deploy_dir
main_menu
