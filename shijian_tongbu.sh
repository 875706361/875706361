#!/bin/bash

# 检查是否为 CentOS 或 Ubuntu 系统
if grep -qi "CentOS Linux release 7" /etc/redhat-release; then
    echo "Detected CentOS 7"
    
    # 安装ntp服务
    yum install -y ntp

    # 配置NTP服务器
    NTP_SERVER="ntp1.aliyun.com"

    # 停止并禁用chronyd服务（CentOS 7默认的时间同步服务）
    systemctl stop chronyd
    systemctl disable chronyd

    # 启用并启动ntp服务
    systemctl enable ntpd
    systemctl start ntpd

    # 更新系统时间
    ntpdate $NTP_SERVER

    # 将系统时间同步到硬件时钟
    hwclock --systohc

    # 修改服务器时区为中国上海
    timedatectl set-timezone Asia/Shanghai

    # 输出同步完成信息
    echo "系统时间和时区已同步完成。"
elif grep -qi "CentOS Linux release 8" /etc/redhat-release; then
    echo "Detected CentOS 8"
    
    # 设置时间同步脚本路径
    TIME_SYNC_SCRIPT="/path/to/centos8_time_sync.sh"

    # 直接执行 CentOS 8 时间同步脚本
    bash "$TIME_SYNC_SCRIPT"
elif [[ -f /etc/os-release && "$(grep -Eoi 'ID=\K\w+' /etc/os-release)" == "ubuntu" ]]; then
    echo "Detected Ubuntu"

    # 安装ntp服务
    apt-get update
    apt-get install -y ntp

    # 配置NTP服务器
    NTP_SERVER="ntp.ubuntu.com"

    # 停止并禁用 systemd-timesyncd 服务（Ubuntu 18.04及更新版本默认的时间同步服务）
    systemctl stop systemd-timesyncd
    systemctl disable systemd-timesyncd

    # 启用并启动ntp服务
    systemctl enable ntp
    systemctl start ntp

    # 更新系统时间
    ntpdate $NTP_SERVER

    # 将系统时间同步到硬件时钟
    hwclock --systohc

    # 修改服务器时区为中国上海
    timedatectl set-timezone Asia/Shanghai

    # 输出同步完成信息
    echo "系统时间已同步完成。"
else
    echo "Unsupported operating system."
    exit 1
fi

# 添加定时任务到 crontab
(crontab -l ; echo "30 1 * * * /path/to/time_sync.sh") | crontab -
