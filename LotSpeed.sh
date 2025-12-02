#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为 Root 用户
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# 系统检测
check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|oracle"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|oracle"; then
        release="centos"
    else
        echo -e "${RED}未检测到支持的操作系统！${PLAIN}" && exit 1
    fi
}

# 清理其他加速 (卸载/禁用)
clean_accel() {
    echo -e "${YELLOW}正在检查并清理其他加速设置...${PLAIN}"
    
    # 备份 sysctl.conf
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%F-%H%M)
    
    # 清理 sysctl.conf 中的拥塞控制设置
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_no_metrics_save/d' /etc/sysctl.conf
    
    # 清理 sysctl.d 中的相关配置
    rm -f /etc/sysctl.d/10-lotspeed.conf
    
    # 尝试移除常见的加速模块
    if lsmod | grep -q "appex"; then
        rmmod appex 2>/dev/null
        echo -e "${GREEN}检测到 LotServer (appex)，已卸载模块。${PLAIN}"
    fi
    
    if lsmod | grep -q "lotspeed"; then
        rmmod lotspeed 2>/dev/null
        echo -e "${GREEN}检测到旧版 LotSpeed，已卸载模块。${PLAIN}"
    fi

    # 刷新 sysctl
    sysctl --system >/dev/null 2>&1
    echo -e "${GREEN}清理完成。${PLAIN}"
}

# 安装依赖
install_depend() {
    echo -e "${YELLOW}正在安装编译依赖...${PLAIN}"
    kernel_version=$(uname -r)
    
    if [[ "${release}" == "centos" ]]; then
        yum install -y epel-release
        yum install -y git make gcc kernel-devel-"${kernel_version}" kernel-headers-"${kernel_version}"
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        apt-get update
        apt-get install -y build-essential git linux-headers-"${kernel_version}"
    fi
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}依赖安装失败！请检查网络或源配置。${PLAIN}"
        echo -e "${YELLOW}注意：如果找不到内核头文件，请先尝试更新系统内核(apt upgrade / yum update)并重启。${PLAIN}"
        exit 1
    fi
}

# 安装 LotSpeed
install_lotspeed() {
    # 1. 清理环境
    clean_accel
    
    # 2. 安装依赖
    install_depend
    
    # 3. 下载源码
    echo -e "${YELLOW}正在克隆 LotSpeed (zeta-tcp) 源码...${PLAIN}"
    rm -rf lotspeed
    git clone -b zeta-tcp https://github.com/uk0/lotspeed.git
    
    if [[ ! -d "lotspeed" ]]; then
        echo -e "${RED}源码克隆失败，请检查网络是否能连接 GitHub。${PLAIN}"
        exit 1
    fi
    
    cd lotspeed || exit
    
    # 4. 编译
    echo -e "${YELLOW}开始编译内核模块...${PLAIN}"
    make
    
    if [[ ! -f "lotspeed.ko" ]]; then
        echo -e "${RED}编译失败！请检查上方错误信息。${PLAIN}"
        cd ..
        exit 1
    fi
    
    # 5. 安装模块
    echo -e "${YELLOW}安装模块到系统目录...${PLAIN}"
    cp lotspeed.ko /lib/modules/$(uname -r)/kernel/net/ipv4/
    depmod -a
    
    # 6. 加载模块
    modprobe lotspeed
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}模块加载失败！可能内核版本不兼容或不支持。${PLAIN}"
        cd ..
        exit 1
    fi
    
    # 7. 配置开机加载 (Optional but recommended)
    echo "lotspeed" > /etc/modules-load.d/lotspeed.conf
    
    # 8. 应用 Sysctl 配置
    echo -e "${YELLOW}应用系统配置...${PLAIN}"
    cat > /etc/sysctl.d/10-lotspeed.conf <<EOF
net.ipv4.tcp_congestion_control = lotspeed
net.ipv4.tcp_no_metrics_save = 1
EOF
    
    sysctl --system >/dev/null 2>&1
    
    # 9. 验证
    cd ..
    rm -rf lotspeed
    check_status
}

# 卸载 LotSpeed
uninstall_lotspeed() {
    echo -e "${YELLOW}正在卸载 LotSpeed...${PLAIN}"
    
    # 移除配置
    rm -f /etc/sysctl.d/10-lotspeed.conf
    rm -f /etc/modules-load.d/lotspeed.conf
    
    # 恢复 sysctl (通常默认是 cubic 或 bbr，这里我们删除 lotspeed 指定项让系统回退到默认)
    sed -i '/net.ipv4.tcp_congestion_control = lotspeed/d' /etc/sysctl.conf
    
    # 卸载模块
    if lsmod | grep -q "lotspeed"; then
        rmmod lotspeed
    fi
    
    # 删除模块文件
    rm -f /lib/modules/$(uname -r)/kernel/net/ipv4/lotspeed.ko
    depmod -a
    
    sysctl --system >/dev/null 2>&1
    
    echo -e "${GREEN}LotSpeed 已卸载。${PLAIN}"
}

# 检查状态
check_status() {
    if lsmod | grep -q "lotspeed"; then
        echo -e "当前状态: ${GREEN}LotSpeed 模块已加载${PLAIN}"
        current_algo=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
        if [[ "${current_algo}" == "lotspeed" ]]; then
             echo -e "TCP拥塞控制: ${GREEN}${current_algo} (生效中)${PLAIN}"
        else
             echo -e "TCP拥塞控制: ${YELLOW}${current_algo} (未生效，请检查 sysctl)${PLAIN}"
        fi
    else
        echo -e "当前状态: ${RED}LotSpeed 未安装或未加载${PLAIN}"
    fi
}

# 菜单
menu() {
    clear
    echo -e "#############################################################"
    echo -e "#               LotSpeed 单边加速一键安装脚本               #"
    echo -e "#           基于 lotspeed (zeta-tcp) 分支源码编译           #"
    echo -e "#############################################################"
    echo -e ""
    check_status
    echo -e ""
    echo -e " 1. 安装 LotSpeed (自动卸载其他加速)"
    echo -e " 2. 卸载 LotSpeed"
    echo -e " 3. 检查运行状态"
    echo -e " 0. 退出脚本"
    echo -e ""
    read -p " 请输入数字 [0-3]: " num
    
    case "$num" in
        1)
            check_sys
            install_lotspeed
            ;;
        2)
            uninstall_lotspeed
            ;;
        3)
            check_status
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}请输入正确的数字！${PLAIN}"
            sleep 1
            menu
            ;;
    esac
}

# 运行菜单
menu