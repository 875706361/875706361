#!/bin/bash
#
function print_tips
{
	echo "*******************************"
	echo "(1)安装squid代理"
	echo "(2)卸载squid代理"
	echo "(3)退出"
	echo "********************************"
}
while true
do
	echo
	print_tips
	read -p "请输入选项(1|2|3):" choice
	#读取用户输入的信息放入choice变量中
	case $choice in
	#判断用户所输入的内容以及输入内容的作用
	1)
	yum install squid -y
	chkconfig --level 35 squid on
	rm -f /etc/squid/squid.conf
	cd /etc/squid
	wget https://raw.githubusercontent.com/875706361/875706361/master/squid.conf
	cd
	echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
	sysctl -p
	service iptables stop
	squid -z
	service squid start
	;;
	2)
	yum remove squid -y
	;;
	3)
	exit
	;;
	*)
	echo "输入错误，请重新输入!"
	;;
	esac
done
	