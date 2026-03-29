#!/usr/bin/env bash
set -euo pipefail

DEPLOY="${DEPLOY:-$HOME/cliproxyapi}"
SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/875706361/875706361/master/manage-cliproxyapi.sh}"
TARGET="$DEPLOY/manage-cliproxyapi.sh"

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

ensure_curl() {
  command -v curl >/dev/null 2>&1 && return 0
  echo "未检测到 curl，尝试自动安装..."
  if command -v apt-get >/dev/null 2>&1; then
    install_pkg_apt
  elif command -v dnf >/dev/null 2>&1; then
    install_pkg_dnf
  elif command -v yum >/dev/null 2>&1; then
    install_pkg_yum
  elif command -v apk >/dev/null 2>&1; then
    install_pkg_apk
  else
    echo "无法识别包管理器，请先手动安装 curl"
    exit 1
  fi
}

mkdir -p "$DEPLOY"
ensure_curl
curl -fsSL "$SCRIPT_URL" -o "$TARGET"
chmod +x "$TARGET"
exec "$TARGET"
