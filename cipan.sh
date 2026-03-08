#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本 (例如: sudo bash nfs_manager.sh)"
  exit 1
fi

# 检查系统包管理器并定义安装包
if [ -x "$(command -v apt-get)" ]; then
    PKG_MNGR="apt-get"
    SERVER_PKG="nfs-kernel-server"
    CLIENT_PKG="nfs-common"
    SVC_NAME="nfs-kernel-server"
elif [ -x "$(command -v yum)" ]; then
    PKG_MNGR="yum"
    SERVER_PKG="nfs-utils rpcbind"
    CLIENT_PKG="nfs-utils rpcbind"
    SVC_NAME="nfs-server"
else
    echo "未识别的包管理器，当前仅支持基于 Debian/Ubuntu (apt) 或 RHEL/CentOS (yum) 的系统。"
    exit 1
fi

echo "================================================="
echo "    Linux NFS 共享磁盘一键管理脚本 (高级完全版)  "
echo "================================================="
echo "请选择要执行的操作:"
echo "------------------- [新 建] ---------------------"
echo "1. [服务端] 创建共享空间 (分配容量并完全控制)"
echo "2. [客户端] 挂载共享空间 (加入开机自启)"
echo "------------------- [重 启] ---------------------"
echo "3. [服务端] 重启共享服务 (应用配置更改)"
echo "4. [客户端] 重新挂载磁盘 (修复断开的连接)"
echo "------------------- [卸 载] ---------------------"
echo "5. [服务端] 彻底卸载共享 (危险: 清空虚拟磁盘数据!)"
echo "6. [客户端] 断开卸载磁盘 (移除自启配置)"
echo "-------------------------------------------------"
echo "0. 退出脚本"
echo "================================================="
read -p "请输入选项 (0-6): " OPTION

case $OPTION in
    1)
        echo -e "\n--- 开始配置服务端 ---"
        echo "正在安装 NFS 服务端组件..."
        $PKG_MNGR install -y $SERVER_PKG > /dev/null 2>&1

        read -p "请输入你要分配的共享磁盘容量 (例如 10G, 500M): " DISK_SIZE
        read -p "请输入允许访问的客户端 IP (例如 192.168.1.100，输入 * 代表允许所有): " CLIENT_IP
        
        BASE_DIR="/var/nfs_share_data"
        IMG_FILE="$BASE_DIR/shared_disk.img"
        EXPORT_DIR="$BASE_DIR/exported_folder"

        echo "正在创建容量为 $DISK_SIZE 的虚拟磁盘..."
        mkdir -p $BASE_DIR
        mkdir -p $EXPORT_DIR
        
        fallocate -l $DISK_SIZE $IMG_FILE
        mkfs.ext4 -F $IMG_FILE > /dev/null 2>&1

        # 配置开机挂载虚拟磁盘
        if ! grep -q "$IMG_FILE" /etc/fstab; then
            echo "$IMG_FILE $EXPORT_DIR ext4 loop 0 0" >> /etc/fstab
        fi
        mount -a

        # 赋予完全控制权限
        echo "正在赋予共享目录完全控制权限..."
        chmod 777 $EXPORT_DIR

        # 配置 NFS
        if ! grep -q "$EXPORT_DIR" /etc/exports; then
            echo "$EXPORT_DIR $CLIENT_IP(rw,sync,no_root_squash,no_subtree_check)" >> /etc/exports
        fi
        
        exportfs -arv > /dev/null 2>&1
        systemctl enable rpcbind > /dev/null 2>&1
        systemctl start rpcbind > /dev/null 2>&1
        systemctl enable $SVC_NAME > /dev/null 2>&1
        systemctl restart $SVC_NAME

        echo -e "\n✅ 服务端创建完成！"
        echo "服务端共享路径: $EXPORT_DIR"
        ;;
        
    2)
        echo -e "\n--- 开始配置客户端 ---"
        echo "正在安装 NFS 客户端组件..."
        $PKG_MNGR install -y $CLIENT_PKG > /dev/null 2>&1

        read -p "请输入服务端的 IP 地址: " SERVER_IP
        read -p "请输入服务端的共享路径 (默认 /var/nfs_share_data/exported_folder): " SERVER_PATH
        SERVER_PATH=${SERVER_PATH:-/var/nfs_share_data/exported_folder}
        read -p "请输入本机的挂载路径 (例如 /mnt/myshare): " CLIENT_MOUNT_PATH

        mkdir -p $CLIENT_MOUNT_PATH

        # 配置开机自动挂载
        if ! grep -q "$SERVER_IP:$SERVER_PATH" /etc/fstab; then
            echo "$SERVER_IP:$SERVER_PATH $CLIENT_MOUNT_PATH nfs defaults,_netdev 0 0" >> /etc/fstab
        fi

        mount -a

        if mount | grep -q "$CLIENT_MOUNT_PATH"; then
            echo -e "\n✅ 挂载成功！已加入开机自启。"
            echo "测试写入权限..."
            touch $CLIENT_MOUNT_PATH/test_write.txt && rm -f $CLIENT_MOUNT_PATH/test_write.txt
            if [ $? -eq 0 ]; then
                 echo "✅ 写入测试通过！你拥有完全控制权。"
            else
                 echo "❌ 写入测试失败，请检查权限。"
            fi
            df -h | grep "$CLIENT_MOUNT_PATH"
        else
            echo -e "\n❌ 挂载失败，请检查 IP、路径及防火墙。"
        fi
        ;;

    3)
        echo -e "\n--- 重启服务端共享服务 ---"
        exportfs -arv > /dev/null 2>&1
        systemctl restart rpcbind
        systemctl restart $SVC_NAME
        echo "✅ 服务端共享服务已成功重启，最新配置已生效！"
        ;;

    4)
        echo -e "\n--- 重新挂载客户端磁盘 ---"
        mount -a
        echo "✅ 挂载指令已执行，请使用 df -h 检查是否恢复正常。"
        ;;

    5)
        echo -e "\n--- 彻底卸载服务端共享 ---"
        echo "⚠️  严重警告：此操作将删除服务端分配的虚拟磁盘文件及其中【所有的共享数据】！"
        read -p "是否确认继续？(输入 YES 继续): " CONFIRM
        if [ "$CONFIRM" == "YES" ]; then
            BASE_DIR="/var/nfs_share_data"
            EXPORT_DIR="$BASE_DIR/exported_folder"
            IMG_FILE="$BASE_DIR/shared_disk.img"
            
            # 1. 移除 exports 并刷新
            sed -i "\|${EXPORT_DIR}|d" /etc/exports
            exportfs -arv > /dev/null 2>&1
            
            # 2. 卸载磁盘
            umount $EXPORT_DIR > /dev/null 2>&1
            
            # 3. 移除 fstab 自启
            sed -i "\|${IMG_FILE}|d" /etc/fstab
            
            # 4. 删除数据文件
            rm -rf $BASE_DIR
            
            echo "✅ 服务端共享已彻底卸载，磁盘空间已释放！"
        else
            echo "已取消卸载操作。"
        fi
        ;;

    6)
        echo -e "\n--- 卸载客户端共享磁盘 ---"
        read -p "请输入你当前挂载的本地路径 (例如 /mnt/myshare): " CLIENT_MOUNT_PATH
        
        # 安全验证，防止误删根目录等
        if [ -z "$CLIENT_MOUNT_PATH" ] || [ "$CLIENT_MOUNT_PATH" == "/" ]; then
            echo "无效的路径，操作取消。"
            exit 1
        fi

        # 1. 强制卸载挂载点
        umount -f -l $CLIENT_MOUNT_PATH > /dev/null 2>&1
        
        # 2. 移除 fstab 自启
        # 使用安全的 grep 过滤方案防止 sed 路径转义问题
        grep -v "$CLIENT_MOUNT_PATH" /etc/fstab > /tmp/fstab_tmp && mv /tmp/fstab_tmp /etc/fstab
        
        echo "✅ 挂载点已被卸载，并且已取消开机自启！"
        
        read -p "是否顺便删除本地的空挂载文件夹 $CLIENT_MOUNT_PATH ？(y/n): " DEL_DIR
        if [[ "$DEL_DIR" == "y" || "$DEL_DIR" == "Y" ]]; then
            rmdir $CLIENT_MOUNT_PATH 2>/dev/null && echo "✅ 文件夹已删除" || echo "⚠️ 文件夹非空或不存在，跳过删除。"
        fi
        ;;

    0)
        echo "已退出脚本。"
        exit 0
        ;;
    *)
        echo "无效选项，请输入 0-6 之间的数字。"
        exit 1
        ;;
esac