#!/bin/bash

# 检查是否以root权限运行
if [[ $EUID -ne 0 ]]; then
   echo "请使用root权限运行此脚本！"
   exit 1
fi

# 检测系统类型
os_type=""
if [ -f /etc/os-release ]; then
    os_type=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
elif [ -f /etc/redhat-release ]; then
    os_type="centos"
elif [ -f /etc/debian_version ]; then
    os_type="debian"
else
    echo "无法检测系统类型，此脚本仅支持常见Linux系统！"
    exit 1
fi

# 输出检测到的系统类型
echo "检测到的系统类型: $os_type"

# 用户输入新的SSH端口
read -p "请输入新的SSH端口（例如 2222）: " new_port

# 检查端口是否有效
if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
    echo "无效端口号，请输入1到65535之间的数字！"
    exit 1
fi

# 修改SSH配置文件
ssh_config="/etc/ssh/sshd_config"
if grep -q "^#Port 22" $ssh_config; then
    sed -i "s/^#Port 22/Port $new_port/" $ssh_config
elif grep -q "^Port " $ssh_config; then
    sed -i "s/^Port .*/Port $new_port/" $ssh_config
else
    echo "Port $new_port" >> $ssh_config
fi

echo "SSH端口已修改为 $new_port"

# 防火墙处理逻辑
if [[ "$os_type" == "ubuntu" || "$os_type" == "debian" ]]; then
    # 针对 Ubuntu 和 Debian 的防火墙处理
    if command -v ufw > /dev/null; then
        read -p "是否卸载防火墙（ufw）？(y/n): " uninstall_firewall
        if [[ "$uninstall_firewall" =~ ^[Yy]$ ]]; then
            echo "正在卸载防火墙..."
            apt-get remove --purge -y ufw
            echo "防火墙已卸载"
        else
            echo "更新防火墙规则..."
            ufw allow $new_port/tcp
            ufw delete allow 22/tcp
            echo "防火墙规则已更新"
        fi
    else
        echo "未检测到UFW防火墙，跳过防火墙规则更新"
    fi
elif [[ "$os_type" == "centos" || "$os_type" == "fedora" ]]; then
    # 针对 CentOS 和 Fedora 的防火墙处理
    if command -v firewall-cmd > /dev/null; then
        read -p "是否卸载防火墙（firewalld）？(y/n): " uninstall_firewall
        if [[ "$uninstall_firewall" =~ ^[Yy]$ ]]; then
            echo "正在卸载防火墙..."
            systemctl stop firewalld
            systemctl disable firewalld
            yum remove -y firewalld
            echo "防火墙已卸载"
        else
            echo "更新防火墙规则..."
            firewall-cmd --permanent --add-port=${new_port}/tcp
            firewall-cmd --permanent --remove-port=22/tcp
            firewall-cmd --reload
            echo "防火墙规则已更新"
        fi
    else
        echo "未检测到 firewalld 防火墙，跳过防火墙规则更新"
    fi
elif [[ "$os_type" == "opensuse" ]]; then
    # 针对 openSUSE 的防火墙处理
    if command -v firewall-cmd > /dev/null; then
        read -p "是否卸载防火墙（firewalld）？(y/n): " uninstall_firewall
        if [[ "$uninstall_firewall" =~ ^[Yy]$ ]]; then
            echo "正在卸载防火墙..."
            systemctl stop firewalld
            systemctl disable firewalld
            zypper remove -y firewalld
            echo "防火墙已卸载"
        else
            echo "更新防火墙规则..."
            firewall-cmd --permanent --add-port=${new_port}/tcp
            firewall-cmd --permanent --remove-port=22/tcp
            firewall-cmd --reload
            echo "防火墙规则已更新"
        fi
    else
        echo "未检测到 firewalld 防火墙，跳过防火墙规则更新"
    fi
else
    echo "当前系统未检测到可支持的防火墙管理工具，跳过防火墙规则更新"
fi

# 重启SSH服务
echo "重启SSH服务..."
if [[ "$os_type" == "ubuntu" || "$os_type" == "debian" ]]; then
    systemctl restart sshd || systemctl restart ssh
elif [[ "$os_type" == "centos" || "$os_type" == "fedora" || "$os_type" == "opensuse" ]]; then
    systemctl restart sshd
fi

# 检查SSH服务状态
if systemctl status sshd > /dev/null 2>&1 || systemctl status ssh > /dev/null 2>&1; then
    echo "SSH服务已成功重启！请确保使用新端口 $new_port 连接服务器。"
else
    echo "SSH服务重启失败，请检查配置文件！"
    exit 1
fi
