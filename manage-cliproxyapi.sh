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

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令: $1"
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

  echo "检测到缺少依赖，尝试自动安装..."
  if command -v apt-get >/dev/null 2>&1; then
    install_pkg_apt
  elif command -v dnf >/dev/null 2>&1; then
    install_pkg_dnf
  elif command -v yum >/dev/null 2>&1; then
    install_pkg_yum
  elif command -v apk >/dev/null 2>&1; then
    install_pkg_apk
  else
    echo "无法识别包管理器，请手动安装：curl tar findutils procps coreutils grep sed"
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

latest_tag() {
  curl -fsSL "$API_LATEST" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n1 | cut -d'"' -f4
}

backup_dir() {
  echo "$HOME/cliproxyapi-backup-$(_timestamp)"
}

full_backup_file() {
  echo "$HOME/cliproxyapi-full-backup-$(_timestamp).tar.gz"
}

status_info() {
  echo "== 部署目录 =="
  echo "$DEPLOY"
  echo

  echo "== 当前版本 =="
  if [ -f "$VERSION_PATH" ]; then
    cat "$VERSION_PATH"
  else
    echo "未找到 version.txt"
  fi
  echo

  echo "== 进程 =="
  pgrep -af "$BIN_NAME" || echo "未运行"
  echo

  echo "== 二进制 =="
  ls -lh "$BIN_PATH" 2>/dev/null || echo "未找到 $BIN_PATH"
  echo

  echo "== 最近备份 =="
  ls -dt "$HOME"/cliproxyapi-backup-* 2>/dev/null | head -n 5 || echo "暂无"
  echo
}

restart_app() {
  echo "重启中..."
  pkill -f "/root/cliproxyapi/${BIN_NAME}|./${BIN_NAME}" || true
  cd "$DEPLOY"
  nohup "./${BIN_NAME}" > "$LOG_PATH" 2>&1 &
  disown || true
  sleep 2
  echo "已重启"
  pgrep -af "$BIN_NAME" || true
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

  echo "$backup"
}

create_full_backup() {
  local tarball
  tarball="$(full_backup_file)"
  tar -czf "$tarball" -C "$HOME" "$(basename "$DEPLOY")"
  echo "$tarball"
}

update_latest() {
  local tag ver url tmp backup newbin newstatic
  tag="$(latest_tag)"
  ver="${tag#v}"
  url="https://github.com/${REPO}/releases/download/${tag}/CLIProxyAPI_${ver}_linux_amd64.tar.gz"

  echo "准备更新到: $tag"
  backup="$(create_backup)"
  echo "已创建备份: $backup"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  cd "$tmp"
  echo "下载: $url"
  curl -fL "$url" -o release.tar.gz
  tar -xzf release.tar.gz

  newbin="$(find . -type f \( -name cli-proxy-api -o -name CLIProxyAPI -o -name cliproxyapi \) | head -n1)"
  if [ -z "${newbin:-}" ]; then
    echo "未找到新二进制"
    exit 1
  fi

  install -m 755 "$newbin" "$BIN_PATH.new"

  newstatic="$(find . -type d -name static | head -n1 || true)"
  if [ -n "${newstatic:-}" ]; then
    mv "$DEPLOY/static" "$DEPLOY/static.bak.$(date +%s)" 2>/dev/null || true
    cp -a "$newstatic" "$DEPLOY/static"
  fi

  mv "$BIN_PATH.new" "$BIN_PATH"
  printf "%s\n" "$ver" > "$VERSION_PATH"

  restart_app
  echo "更新完成: $tag"
  echo "备份目录: $backup"
}

rollback_menu() {
  local selected idx confirm
  echo "可用备份："
  ls -dt "$HOME"/cliproxyapi-backup-* 2>/dev/null | nl -w2 -s'. ' || {
    echo "没有可回滚的备份"
    return
  }
  echo
  read -r -p "输入要回滚的序号: " idx

  selected="$(ls -dt "$HOME"/cliproxyapi-backup-* 2>/dev/null | sed -n "${idx}p" || true)"
  if [ -z "${selected:-}" ]; then
    echo "无效序号"
    return
  fi

  echo "将回滚到: $selected"
  read -r -p "确认回滚？[y/N]: " confirm
  case "${confirm:-N}" in
    y|Y)
      [ -f "$selected/$BIN_NAME" ] && cp -a "$selected/$BIN_NAME" "$BIN_PATH"
      [ -f "$selected/version.txt" ] && cp -a "$selected/version.txt" "$VERSION_PATH" || true
      if [ -d "$selected/static" ]; then
        mv "$DEPLOY/static" "$DEPLOY/static.rollback.bak.$(date +%s)" 2>/dev/null || true
        cp -a "$selected/static" "$DEPLOY/static"
      fi
      restart_app
      echo "回滚完成"
      ;;
    *)
      echo "已取消"
      ;;
  esac
}

show_logs() {
  if [ -f "$LOG_PATH" ]; then
    tail -n 80 "$LOG_PATH"
  else
    echo "未找到日志: $LOG_PATH"
  fi
}

main_menu() {
  while true; do
    echo
    echo "==== CLIProxyAPI 管理菜单 ===="
    echo "1) 更新到最新版本（保留数据）"
    echo "2) 回滚到备份版本"
    echo "3) 重启当前服务"
    echo "4) 查看当前状态"
    echo "5) 查看最近日志"
    echo "6) 创建整目录压缩备份"
    echo "0) 退出"
    echo

    read -r -p "请选择: " choice
    case "$choice" in
      1) update_latest ;;
      2) rollback_menu ;;
      3) restart_app ;;
      4) status_info ;;
      5) show_logs ;;
      6)
        f="$(create_full_backup)"
        echo "已创建整目录备份: $f"
        ;;
      0)
        echo "退出"
        exit 0
        ;;
      *)
        echo "无效选项"
        ;;
    esac
  done
}

if [ ! -d "$DEPLOY" ]; then
  echo "部署目录不存在: $DEPLOY"
  exit 1
fi

main_menu
