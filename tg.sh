#!bin/bash
#MTProxy代理搭建脚本
function clay
{
	echo -e "\033[32m------------------------------------\033[1m"
	echo "1.安装MTProxy代理"
	echo "2.添加每天更新配置代理文件"
	echo "q:退出脚本"
}


while true
do
	echo
	clay
	read -p "请输入选项(1|2|q):" a
	case $a in
	1)
	echo "MTProxy代理正在安装..."
	yum install openssl-devel zlib-devel -y
	yum groupinstall "Development Tools" -y
	git clone https://github.com/TelegramMessenger/MTProxy
	cd MTProxy	#这里需要判断是否执行成功
	make && cd objs/bin
	if [ $? -eq 0 ];then
                echo "MTProxy编译成功!"
        else
                echo "MTProxy编译失败!请检查错误"
        fi
	echo "获取Telegram通信密匙"
	curl -s https://core.telegram.org/getProxySecret -o proxy-secret
	echo "获取当前Telegram代理配置(官方建议每天更新此文件)"
	curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
	echo "生成代理密匙"
	a=`head -c 16 /dev/urandom | xxd -ps`
	duankou="6677"
	echo "启动MTP服务端"
	./mtproto-proxy -u nobody -p 8888 -H ${duankou} -S ${a} --aes-pwd proxy-secret proxy-multi.conf -M 1
	if [ $? -eq 0 ];then
                echo "MTProxy启动成功!"
        else
                echo "MTProxy启动失败!请检查错误"
        fi
	echo "客户连接配置:"
	echo "端口:${duankou},连接秘钥:${a}"
	exit
	;;
	2)
	yum install crontabs
	systemctl enable crond
	systemctl start crond
cat >>/etc/crontab<<EOF
0 0 * * * root /home/tg1.sh
EOF
	
	crontab /etc/crontab
	crontab -l
	cd /home
	wget https://raw.githubusercontent.com/875706361/875706361/master/tg1.sh	#tg1脚本的链接
	cd
	echo "添加成功!"
	exit
	;;
	q)
	echo "退出脚本"
	exit
	;;
	*)
	echo "输入错误,请重新输入!"
	;;
	esac
done
