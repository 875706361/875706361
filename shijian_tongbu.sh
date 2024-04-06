#!/bin/bash

# 创建脚本文件并写入内容
cat <<'EOF' > /home/shijian.sh
#!/bin/bash

# 使用dos2unix命令确保脚本文件格式正确
yum install dos2unix -y
apt-get install -y dos2unix
dos2unix /home/shijian_tongbu.sh

# 设置时区为中国
timedatectl set-timezone Asia/Shanghai

# 检查系统是否为 CentOS 或 Ubuntu
if [[ -f /etc/redhat-release ]]; then
    OS="centos"
    # 安装dos2unix和ntp服务
    yum install -y dos2unix ntp
elif [[ -f /etc/lsb-release ]]; then
    OS="ubuntu"
    # 安装dos2unix和ntp服务
    apt-get update
    apt-get install -y dos2unix ntp
else
    echo "不支持的操作系统"
    exit 1
fi

# 同步时间
ntpdate cn.pool.ntp.org

# 将同步后的时间加入系统时间中
hwclock -w

# 输出提示信息
echo "时间已同步"
EOF

# 添加执行权限
chmod +x /home/shijian.sh

# 检查是否存在定时任务，如果不存在则添加到 cron 任务中
if ! crontab -l | grep -q '/home/shijian.sh'; then
    # 将脚本添加到 cron 任务中，每天1:30自动执行
    (crontab -l 2>/dev/null; echo "30 1 * * * /home/shijian.sh") | crontab -
    echo "定时任务已创建"
else
    echo "定时任务已存在，无需创建"
fi

echo "脚本已创建：/home/shijian.sh，并添加到每天1:30自动运行任务中"
