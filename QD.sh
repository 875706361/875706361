#!/bin/bash

# 创建并切换到 QD 目录
mkdir -p "$(pwd)/qd/config" && cd "$(pwd)/qd" || exit

# 下载 docker-compose.yml
wget https://fastly.jsdelivr.net/gh/qd-today/qd@master/docker-compose.yml

# 根据需求和配置说明修改配置环境变量
# (请手动修改配置，或者在这里添加自动化的修改代码)

# 执行 Docker Compose 命令
docker-compose up -d

# 提示安装完成
IP=$(hostname -I | awk '{print $1}')  # 获取当前机器的IP地址
echo "安装完成！您可以通过 http://$IP:8923 访问服务。"
