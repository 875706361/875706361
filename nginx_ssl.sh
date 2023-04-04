#!/bin/bash

string="小丑在笑你!"

function print_tips
{
	clear
	echo "*******************************"
	echo "(1)安装nginx全站证书"
	echo "(2)恢复默认nginx 81端口配置"
	echo "********************************"
}

function anzhuang
{
	clear
	cd /usr/local/nginx/conf/
	cp nginx.conf nginx.conf.1
	echo "备份nginx.conf 为nginx.conf.1"
	rm -rf nginx.conf
	wget https://raw.githubusercontent.com/875706361/875706361/master/nginx.conf
	service nginx restart
	echo "已配置好ssl,已重启nginx,请使用Https访问网站测试"
	echo "网站:https://域名:81"
}

function xiezai
{
	clear
	cd /usr/local/nginx/conf/
	rm -rf nginx.conf
	cp nginx.conf.1 nginx.conf
	service nginx restart
	echo "已经恢复默认nginx配置"
	echo "请使用80端口访问域名"
}

while true
do
	clear
	echo "【string=$string】"
	echo
	print_tips
	read -p "请输入选项(1|2|q|Q):" choice
	#读取用户输入的信息放入choice变量中
	case $choice in
	#判断用户所输入的内容以及输入内容的作用
	1)
		anzhuang
		;;
	2)
		xiezai
		;;
	q|Q)
		exit
		;;
	*)
		echo "输入错误，请重新输入!"
		;;
	esac
done
