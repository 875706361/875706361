#!/bin/bash

string="小丑在笑你!"

function print_tips
{
	echo "*******************************"
	echo "(1)安装iptables防火墙"
	echo "(2)卸载iptables防火墙"
	echo "(3)导入默认连接数限制防火墙规则"
	echo "(4)输入自定义防火墙规则"
	echo "查看防火墙规则文件配置内容"
	echo "(q|Q)退出脚本"
	echo "********************************"
}

function anzhuang
{
	clear
	yum install -y iptables	#安装iptables
	yum update iptables	#升级iptables
	yum install iptables-services	#安装iptables-services
	echo "禁用/停止centos7自带的firewalld服务"
	#停止firewalld服务
	systemctl stop firewalld
	#禁用firewalld服务
	systemctl mask firewalld
	echo "安装成功,默认为允许所有端口通过"
	iptables -P INPUT ACCEPT
	iptables -A INPUT -p icmp --icmp-type 8 -j ACCEPT
	service iptables save	#保存以上规则
	systemctl restart iptables.service	#重启iptables防火墙
	echo "iptables防火墙已重启"
}

function xiezai
{
	clear
	read -p "永久停用请输入1
yum命令卸载请输入2
停用后开启请输入3
退出请输入q
请输入(1|2|3|q)：" xz
	case $xz in
	1)
	chkconfig iptables off
	;;
	2)
	yum remove iptables -y
	;;
	3)
	chkconfig iptables on
	;;
	4)
	exit
	;;
	*)
	echo "输入错误,请重新输入"
	esac	
}

function guize
{
	echo "开始导入默认限制连接数规则"
	echo "**************************"
	iptables -A INPUT -p tcp -m tcp --dport 0:2000 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 2001:26000 -m connlimit --connlimit-above 50 --connlimit-mask 32 --connlimit-saddr -j DROP
iptables -A INPUT -p tcp -m tcp --dport 27000:65535 -m connlimit --connlimit-above 50 --connlimit-mask 32 --connlimit-saddr -j DROP
	yum list | grep initscripts
	yum install initscripts
	service iptables save	#保存以上规则
	systemctl start iptables.service	#重启iptables防火墙
	echo "**************************"
	echo "默认限制连接数规则导入完毕"
	echo "**************************"
	echo "允许0:2000端口通过
2001:26000端口限制50连接数
27000:65535端口限制50连接数"
}

function zidingyi_guize
{
	clear
	echo "**************************"
	echo "请输入自定义允许通过端口【起始端口:结束端口】"
	read -p "请输入自定义允许通过端口: " duan
	case $duan in
	#eiptables -A INPUT -p tcp -m tcp --dport $duankou -j ACCEPT
	esac
}

function chakan
{
	echo "iptables防火墙配置文件路劲：/etc/sysconfig/iptables"
	echo "请输入查看或者编辑:1查看
	2编辑"
	read -p "请输入[1|2]：" kan
	case $kan in
	1)
	cat /etc/sysconfig/iptables
	;;
	2)
	vi /etc/sysconfig/iptables
	esac
}

while true
do
	clear
	echo "【string=$string】"
	echo
	print_tips
	read -p "请输入选项(1|2|3|4|q|Q):" choice
	#读取用户输入的信息放入choice变量中
	case $choice in
	#判断用户所输入的内容以及输入内容的作用
	1)
		anzhuang
		;;
	2)
		xiezai
		;;
	3)
		guize
		;;
	4)
		zidingyi_guize
		;;
	5)
		chakan
		;;
	q|Q)
		exit
		;;
	*)
		echo "输入错误，请重新输入!"
		;;
	esac
done
