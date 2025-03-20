#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本"
  exit 1
fi

# 定义备份目录
BACKUP_DIR="/root/optimizer_backups"

# 定义需要备份的文件列表
FILES_TO_BACKUP=(
  "/etc/hosts"
  "/etc/resolv.conf"
  "/etc/sysctl.conf"
  "/etc/ssh/sshd_config"
  "/etc/fstab"
  "/etc/profile"
  "/etc/security/limits.conf"
)

# 检测包管理器
if [ -f /etc/debian_version ]; then
  PKG_MANAGER="apt"
elif [ -f /etc/redhat-release ]; then
  PKG_MANAGER="dnf"
else
  echo "不支持的发行版。退出。"
  exit 1
fi

# 备份文件的函数
backup_files() {
  mkdir -p "$BACKUP_DIR"
  for file in "${FILES_TO_BACKUP[@]}"; do
    if [ -f "$file" ]; then
      backup_file="$BACKUP_DIR/$(echo "$file" | sed 's/\//__/g').bak"
      cp "$file" "$backup_file"
      echo "已备份 $file 到 $backup_file"
    fi
  done
}

# 恢复文件的函数
restore_files() {
  if [ -d "$BACKUP_DIR" ]; then
    for backup_file in "$BACKUP_DIR"/*.bak; do
      original_file=$(echo "$backup_file" | sed 's/__/\//g' | sed 's/\.bak$//')
      if [ -f "$backup_file" ]; then
        mv "$backup_file" "$original_file"
        echo "已从 $backup_file 恢复 $original_file"
      fi
    done
    rm -rf "$BACKUP_DIR"
  else
    echo "未找到备份文件，无法恢复。"
  fi
}

# 安装优化的函数
install_optimizer() {
  # 在优化前备份文件
  backup_files

  # 下载并运行 Linux Optimizer 脚本
  echo "正在下载 Linux Optimizer 脚本..."
  wget -O /root/linux-optimizer.sh https://raw.githubusercontent.com/hawshemi/Linux-Optimizer/main/linux-optimizer.sh
  if [ $? -eq 0 ]; then
    chmod +x /root/linux-optimizer.sh
    echo "正在执行优化..."
    bash /root/linux-optimizer.sh
  else
    echo "下载失败，请检查网络连接。"
  fi
}

# 查看优化的函数
view_optimizer() {
  if [ -d "$BACKUP_DIR" ]; then
    echo "已优化的文件："
    for backup_file in "$BACKUP_DIR"/*.bak; do
      original_file=$(echo "$backup_file" | sed 's/__/\//g' | sed 's/\.bak$//')
      echo "- $original_file"
    done
  else
    echo "未应用优化或未找到备份。"
  fi
}

# 卸载优化的函数
uninstall_optimizer() {
  # 恢复备份文件
  restore_files

  # 应用恢复后的配置
  sysctl -p
  systemctl restart sshd

  # 删除交换文件
  if [ -f /swapfile ]; then
    swapoff -a
    rm -f /swapfile
    echo "已删除交换文件 /swapfile"
  fi

  # 根据包管理器移除安装的软件包（示例列表，可根据需要调整）
  if [ "$PKG_MANAGER" = "apt" ]; then
    apt remove -y apt-transport-https vim htop
    apt autoremove -y
  elif [ "$PKG_MANAGER" = "dnf" ]; then
    dnf remove -y epel-release vim htop
    dnf autoremove -y
  fi

  # 提示用户重启
  echo "优化已卸载。某些更改可能需要重启系统以生效。"
  read -p "是否立即重启？(y/n): " reboot_choice
  if [ "$reboot_choice" = "y" ]; then
    reboot
  fi
}

# 主菜单循环
while true; do
  echo ""
  echo "Linux 系统优化工具"
  echo "1. 安装优化"
  echo "2. 查看优化"
  echo "3. 卸载优化"
  echo "4. 退出"
  read -p "请选择一个选项: " choice

  case $choice in
    1)
      install_optimizer
      ;;
    2)
      view_optimizer
      ;;
    3)
      uninstall_optimizer
      ;;
    4)
      echo "退出脚本。"
      exit 0
      ;;
    *)
      echo "无效选项，请重试。"
      ;;
  esac
done