#!/bin/bash

# 提示用户输入主DNS和备用DNS
read -p "请输入主DNS地址: " primary_dns
read -p "请输入备用DNS地址: " secondary_dns

# 检查输入是否为空
if [[ -z "$primary_dns" || -z "$secondary_dns" ]]; then
    echo "DNS地址不能为空!"
    exit 1
fi

# 检查发行版类型
distro=$(cat /etc/os-release | grep ^ID= | cut -d= -f2 | tr -d '"')

case "$distro" in
    ubuntu|debian)
        # 适用于 Ubuntu 或 Debian 系列系统
        echo "您正在使用 Ubuntu 或 Debian 系列系统。"
        # 更新 /etc/resolv.conf 文件
        echo "nameserver $primary_dns" > /etc/resolv.conf
        echo "nameserver $secondary_dns" >> /etc/resolv.conf
        # 禁用 resolvconf 或类似服务以避免重启后还原
        if systemctl is-active --quiet resolvconf; then
            systemctl stop resolvconf
            systemctl disable resolvconf
        fi
        ;;
    almalinux|centos|rhel)
        # 适用于 Almalinux、CentOS 或 RHEL 系统
        echo "您正在使用 Almalinux、CentOS 或 RHEL 系统。"
        if systemctl is-active --quiet systemd-resolved; then
            # 如果系统使用 systemd-resolved，则更新 resolved.conf
            echo -e "[Resolve]\nDNS=$primary_dns\nFallbackDNS=$secondary_dns" > /etc/systemd/resolved.conf
            # 重新启动 systemd-resolved 服务以应用更改
            systemctl restart systemd-resolved
            echo "已通过 systemd-resolved 更新 DNS 设置"
        else
            # 如果没有 systemd-resolved，直接更新 /etc/resolv.conf 文件
            echo "systemd-resolved 未启用，正在更新 /etc/resolv.conf。"
            echo "nameserver $primary_dns" > /etc/resolv.conf
            echo "nameserver $secondary_dns" >> /etc/resolv.conf
        fi
        # 禁用 NetworkManager 自动覆盖 resolv.conf
        if systemctl is-active --quiet NetworkManager; then
            nmcli networking off
            nmcli networking on
        fi
        ;;
    alinux)
        # 适用于 阿里云 Linux (Aliyun Linux)
        echo "您正在使用阿里云 Linux 系统。"
        if systemctl is-active --quiet systemd-resolved; then
            # 如果系统使用 systemd-resolved，则更新 resolved.conf
            echo -e "[Resolve]\nDNS=$primary_dns\nFallbackDNS=$secondary_dns" > /etc/systemd/resolved.conf
            systemctl restart systemd-resolved
            echo "已通过 systemd-resolved 更新 DNS 设置"
        else
            echo "systemd-resolved 未启用，正在更新 /etc/resolv.conf。"
            echo "nameserver $primary_dns" > /etc/resolv.conf
            echo "nameserver $secondary_dns" >> /etc/resolv.conf
        fi
        # 禁用 NetworkManager 自动覆盖 resolv.conf
        if systemctl is-active --quiet NetworkManager; then
            nmcli networking off
            nmcli networking on
        fi
        ;;
    *)
        # 适用于其他主流 Linux 系统
        echo "您正在使用其他主流 Linux 系统。"
        if systemctl is-active --quiet systemd-resolved; then
            # 如果系统使用 systemd-resolved，则更新 resolved.conf
            echo -e "[Resolve]\nDNS=$primary_dns\nFallbackDNS=$secondary_dns" > /etc/systemd/resolved.conf
            systemctl restart systemd-resolved
            echo "已通过 systemd-resolved 更新 DNS 设置"
        else
            echo "systemd-resolved 未启用，正在更新 /etc/resolv.conf。"
            echo "nameserver $primary_dns" > /etc/resolv.conf
            echo "nameserver $secondary_dns" >> /etc/resolv.conf
        fi
        # 禁用 NetworkManager 自动覆盖 resolv.conf
        if systemctl is-active --quiet NetworkManager; then
            nmcli networking off
            nmcli networking on
        fi
        ;;
esac

# 输出当前 DNS 配置
echo "当前 DNS 配置:"
cat /etc/resolv.conf
