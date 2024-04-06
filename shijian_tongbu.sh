#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "请以管理员权限运行此脚本"
    exit 1
fi

# 设置时间同步脚本路径
TIME_SYNC_SCRIPT="/path/to/time_sync_setup.sh"

# 如果脚本不存在，则创建
if [ ! -f "$TIME_SYNC_SCRIPT" ]; then
    cat <<EOF > "$TIME_SYNC_SCRIPT"
#!/bin/bash

# 安装 NTP 服务并设置时间和时区
install_ntp() {
    # CentOS 安装 NTP
    if [ -f /etc/redhat-release ]; then
        echo "检测到 CentOS，正在安装 NTP 服务..."
        yum install -y ntp
        NTP_SERVER="ntp1.aliyun.com"
        systemctl stop chronyd
        systemctl disable chronyd
        systemctl enable ntpd
        systemctl start ntpd
        ntpdate \$NTP_SERVER
        hwclock --systohc
        timedatectl set-timezone Asia/Shanghai
        echo "NTP 服务已安装并配置完成。"
    # Ubuntu 安装 NTP
    elif [ -f /etc/os-release ]; then
        echo "检测到 Ubuntu，正在安装 NTP 服务..."
        apt-get update
        apt-get install -y ntp
        NTP_SERVER="ntp.ubuntu.com"
        systemctl stop systemd-timesyncd
        systemctl disable systemd-timesyncd
        systemctl enable ntp
        systemctl start ntp
        ntpdate \$NTP_SERVER
        hwclock --systohc
        timedatectl set-timezone Asia/Shanghai
        echo "NTP 服务已安装并配置完成。"
    else
        echo "不支持的操作系统。"
        exit 1
    fi
}

# 添加定时任务到 crontab
add_cron_job() {
    echo "正在添加定时任务到 crontab，每天凌晨1点30分自动执行时间同步脚本..."
    (crontab -l | grep -v "$TIME_SYNC_SCRIPT" ; echo "30 1 * * * $TIME_SYNC_SCRIPT") | crontab -
    echo "定时任务已添加完成。"
}

# 安装 NTP
install_ntp

# 添加定时任务到 crontab
add_cron_job
EOF
fi

# 赋予时间同步脚本执行权限
chmod +x "$TIME_SYNC_SCRIPT"

# 以管理员权限运行时间同步脚本
sudo bash "$TIME_SYNC_SCRIPT"
