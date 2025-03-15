#!/bin/bash

# 获取系统信息
function get_system_info() {
    SYSTEM_TYPE=$(grep '^NAME=' /etc/os-release | cut -d '=' -f 2- | sed 's/"//g')
    VERSION_ID=$(grep '^VERSION_ID=' /etc/os-release | cut -d '=' -f 2- | sed 's/"//g')
    echo "$SYSTEM_TYPE $VERSION_ID"
}

# 安装依赖包（根据系统类型）
function install_dependencies() {
    local system_type=$1
    
    case $system_type in
        Ubuntu|Debian)
            sudo apt update && \
            sudo apt install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release \
                apt-transport-https \
                software-properties-common \
                git \
                wget \
                unzip
            ;;
            
        CentOS|RHEL)
            sudo dnf install -y \
                dnf-utils \
                device-mapper-persistent-data \
                lvm2 \
                yum-utils \
                git \
                wget \
                unzip
            ;;
            
        Fedora)
            sudo dnf install -y \
                dnf-utils \
                device-mapper-persistent-data \
                lvm2 \
                yum-utils \
                git \
                wget \
                unzip
            ;;
            
        Arch\ Linux)
            sudo pacman -S --noconfirm \
                base-devel \
                curl \
                gnupg \
                git \
                wget \
                unzip
            ;;
            
        openSUSE)
            sudo zypper refresh && \
            sudo zypper install -y \
                ca-certificates \
                curl \
                gnupg \
                git \
                wget \
                unzip
            ;;
    esac
}

# 安装Docker（根据系统类型）
function install_docker() {
    local system_type=$1
    
    case $system_type in
        Ubuntu|Debian)
            # 添加Docker官方GPG密钥
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            
            # 设置Docker稳定版仓库
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # 安装Docker引擎、containerd和Docker Compose
            sudo apt update && \
            sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
            
        CentOS|RHEL)
            # 添加Docker仓库
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # 安装Docker引擎、containerd和Docker Compose
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
            
        Fedora)
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo && \
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
            
        Arch\ Linux)
            sudo pacman -S --noconfirm docker docker-compose
            ;;
            
        openSUSE)
            sudo zypper addrepo https://download.docker.com/linux/opensuse/docker-ce.repo && \
            sudo zypper refresh && \
            sudo zypper install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
    esac
    
    # 启动Docker服务
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # 验证Docker安装
    echo "验证Docker安装..."
    sudo docker run hello-world
}

# 配置环境
function configure_environment() {
    # 添加当前用户到docker组
    sudo usermod -aG docker $USER
    
    # 设置镜像加速器（使用阿里云镜像）
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://<your-mirror-host>.mirror.aliyuncs.com"],
  "data-root": "/var/lib/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    
    # 重启Docker服务使配置生效
    sudo systemctl restart docker
}

# 创建并启动容器
function create_container() {
    echo "正在创建并启动容器..."
    
    # 拉取镜像
    docker pull jonssonyan/h-ui
    
    # 创建必要的目录结构
    sudo mkdir -p /h-ui/bin /h-ui/data /h-ui/export /h-ui/logs
    
    # 启动容器，使用高级配置参数
    docker run -d --cap-add=NET_ADMIN \
      --name h-ui --restart always \
      --network=host \
      -v /h-ui/bin:/h-ui/bin \
      -v /h-ui/data:/h-ui/data \
      -v /h-ui/export:/h-ui/export \
      -v /h-ui/logs:/h-ui/logs \
      -e TZ=Asia/Shanghai \
      jonssonyan/h-ui
      
    echo "容器创建完成！"
    read -n 1 -s -r -p "按任意键继续..."
}

# 删除容器
function delete_container() {
    echo "正在删除容器..."
    docker rm -f h-ui
    echo "容器已删除！"
    read -n 1 -s -r -p "按任意键继续..."
}

# 重启容器
function restart_container() {
    echo "正在重启容器..."
    docker restart h-ui
    echo "容器已重启！"
    read -n 1 -s -r -p "按任意键继续..."
}

# 进入容器
function enter_container() {
    echo "正在进入容器..."
    docker exec -it h-ui /bin/bash
}

# 安装H-ui v0.0.11
function install_hui() {
    echo "正在安装 H-ui v0.0.11..."
    docker exec hui-container apt update
    docker exec hui-container apt install -y git wget unzip
    docker exec hui-container wget https://github.com/jonssonyan/h-ui/archive/refs/tags/v0.0.11.zip
    docker exec hui-container unzip v0.0.11.zip
    echo "H-ui 安装完成！"
    read -n 1 -s -r -p "按任意键继续..."
}

# 修改端口
function modify_port() {
    echo "正在修改H-ui端口..."
    
    # 停止现有容器
    docker stop h-ui
    
    # 删除现有容器
    docker rm h-ui
    
    # 重新创建容器，使用新的端口
    read -p "请输入新的端口号 (默认8081): " new_port
    new_port=${new_port:-8081}
    
    # 创建新的容器
    docker run -d --cap-add=NET_ADMIN \
      --name h-ui --restart always \
      --network=host \
      -v /h-ui/bin:/h-ui/bin \
      -v /h-ui/data:/h-ui/data \
      -v /h-ui/export:/h-ui/export \
      -v /h-ui/logs:/h-ui/logs \
      -e TZ=Asia/Shanghai \
      -e PORT=$new_port \
      jonssonyan/h-ui
      
    echo "端口已修改为 $new_port！"
    read -n 1 -s -r -p "按任意键继续..."
}

# 显示主菜单
function show_menu() {
    clear
    echo "================== Docker与H-ui集成管理系统 =================="
    echo "1. 安装Docker及依赖包"
    echo "2. 配置Docker环境"
    echo "3. 创建并启动容器"
    echo "4. 删除容器"
    echo "5. 重启容器"
    echo "6. 进入容器"
    echo "7. 安装 H-ui v0.0.11"
    echo "8. 修改端口"
    echo "9. 退出"
    echo "============================================================"
}

# 主程序
echo "开始执行Docker和H-ui集成脚本..."

# 获取系统信息
SYSTEM_INFO=$(get_system_info)
SYSTEM_TYPE=$(echo "$SYSTEM_INFO" | cut -d ' ' -f 1)

# 安装依赖包
install_dependencies "$SYSTEM_TYPE"

# 安装Docker
install_docker "$SYSTEM_TYPE"

# 配置环境
configure_environment

# 显示完成信息
echo "================== 安装完成！ =================="
echo "请重新登录系统以应用新的Docker权限设置。"
echo "您可以通过以下命令测试Docker是否正常工作："
echo "sudo docker ps"
echo "==============================================="

# 显示H-ui默认账号密码信息
echo "================== H-ui默认账号信息 =================="
echo "默认用户名：sysadmin"
echo "默认密码：sysadmin"
echo "默认访问端口：8081"
echo "==============================================="

# 进入主菜单循环
while true
do
    show_menu
    read -p "请选择操作 (1-9): " choice
    
    case $choice in
        1) install_docker "$SYSTEM_TYPE" ;;
        2) configure_environment ;;
        3) create_container ;;
        4) delete_container ;;
        5) restart_container ;;
        6) enter_container ;;
        7) install_hui ;;
        8) modify_port ;;
        9) exit 0 ;;
        *) echo "无效选项，请重新选择..." ;;
    esac
done
