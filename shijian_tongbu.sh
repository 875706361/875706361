#!/bin/bash

# 设置时间同步脚本路径
TIME_SYNC_SCRIPT="/path/to/time_sync.sh"

# 创建时间同步脚本文件
cat <<EOF > "$TIME_SYNC_SCRIPT"
#!/bin/bash

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
ntpdate \$NTP_SERVER

# 将系统时间同步到硬件时钟
hwclock --systohc

# 输出同步完成信息
echo "系统时间已同步完成。"
EOF

# 赋予时间同步脚本执行权限
chmod +x "$TIME_SYNC_SCRIPT"

# 执行时间同步脚本
"$TIME_SYNC_SCRIPT"

# 将定时任务添加到crontab中
(crontab -l ; echo "30 1 * * * $TIME_SYNC_SCRIPT") | crontab -
