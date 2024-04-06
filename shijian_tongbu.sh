#!/bin/bash

# 创建脚本文件并写入内容
cat <<'EOF' > /home/shijian.sh
#!/bin/bash

# 设置时区为中国
timedatectl set-timezone Asia/Shanghai

# 检查系统是否为 CentOS 或 Ubuntu
if [[ -f /etc/redhat-release ]]; then
    OS="centos"
elif [[ -f /etc/lsb-release ]]; then
    OS="ubuntu"
else
    echo "不支持的操作系统"
    exit 1
fi

# 根据操作系统安装必要的软件包
if [[ "$OS" == "centos" ]]; then
    yum install -y ntp
elif [[ "$OS" == "ubuntu" ]]; then
    apt-get update
    apt-get install -y ntp
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
