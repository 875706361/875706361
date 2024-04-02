#!/bin/bash
export LANG=en_US.UTF-8
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts
if [[ -f /etc/redhat-release ]]; then
release="Centos"
elif cat /etc/issue | grep -q -E -i "debian"; then
release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
else 
red "不支持你当前系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(lsb_release -sd || cat /etc/redhat-release || cat /etc/os-release | grep -i pretty_name | cut -d \" -f2)
version=$(uname -r | cut -d "-" -f1)
main=$(uname -r | cut -d "." -f1)
minor=$(uname -r | cut -d "." -f2)
vi=$(systemd-detect-virt)
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "目前脚本不支持$(uname -m)架构" && exit;;
esac
if [ ! -f xuiyg_update ]; then
green "首次安装x-ui脚本必要的依赖……"
update(){
if [ -x "$(command -v apt-get)" ]; then
apt update
elif [ -x "$(command -v yum)" ]; then
yum update && yum install epel-release -y
elif [ -x "$(command -v dnf)" ]; then
dnf update
fi
}
update
packages=("curl" "openssl" "tar" "wget" "cron")
for package in "${packages[@]}"
do
if ! command -v "$package" &> /dev/null; then
if [ -x "$(command -v apt-get)" ]; then
apt-get install -y "$package" 
elif [ -x "$(command -v yum)" ]; then
yum install -y "$package"
elif [ -x "$(command -v dnf)" ]; then
dnf install -y "$package"
fi
fi
done
if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
if ! command -v "cronie" &> /dev/null; then
if [ -x "$(command -v yum)" ]; then
yum install -y cronie
elif [ -x "$(command -v dnf)" ]; then
dnf install -y cronie
fi
fi
fi
update
touch xuiyg_update
fi
if [[ $vi = openvz ]]; then
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4
cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit
else
echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
green "TUN守护功能已启动"
fi
fi
fi
warpcheck(){
wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}
v6(){
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
v4=$(curl -s4m5 ip.sb -k)
if [ -z $v4 ]; then
yellow "检测到 纯IPV6 VPS，添加DNS64"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
fi
fi
}
baseinstall() {
if [[ $release = Centos ]]; then
if [[ ${vsid} =~ 8 ]]; then
yum clean all && yum makecache
fi
yum install epel-release -y
fi
}
serinstall(){
cd /usr/local/
curl -sSL -o /usr/local/x-ui-linux-${cpu}.tar.gz --insecure https://github.com/875706361/875706361/raw/master/x-ui-yg_beifen/x-ui-linux-${cpu}.tar.gz
tar zxvf x-ui-linux-${cpu}.tar.gz
rm x-ui-linux-${cpu}.tar.gz -f
cd x-ui
chmod +x x-ui bin/xray-linux-${cpu}
cp -f x-ui.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable x-ui
systemctl start x-ui
cd
rm -rf /usr/bin/x-ui
curl -sSL -o /usr/bin/x-ui --insecure https://raw.githubusercontent.com/875706361/875706361/master/x-ui-yg_beifen/install.sh >/dev/null 2>&1
chmod +x /usr/bin/x-ui
}
userinstall(){
echo
readp "设置x-ui登录用户名，必须为6位字符以上（回车跳过为随机6位字符）：" username
sleep 1
if [[ -z ${username} ]]; then
username=`date +%s%N |md5sum | cut -c 1-6`
else
if [[ 6 -ge ${#username} ]]; then
until [[ 6 -le ${#username} ]]
do
[[ 6 -ge ${#username} ]] && yellow "\n用户名必须为6位字符以上！请重新输入" && readp "\n设置x-ui登录用户名：" username
done
fi
fi
sleep 1
green "x-ui登录用户名：${username}"
echo -e ""
readp "设置x-ui登录密码，必须为6位字符以上（回车跳过为随机6位字符）：" password
sleep 1
if [[ -z ${password} ]]; then
password=`date +%s%N |md5sum | cut -c 1-6`
else
if [[ 6 -ge ${#password} ]]; then
until [[ 6 -le ${#password} ]]
do
[[ 6 -ge ${#password} ]] && yellow "\n用户名必须为6位字符以上！请重新输入" && readp "\n设置x-ui登录密码：" password
done
fi
fi
sleep 1
/usr/local/x-ui/x-ui setting -username ${username} -password ${password} >/dev/null 2>&1
green "x-ui登录密码：${password}"
}
portinstall(){
echo
readp "设置x-ui登录端口[1-65535]（回车跳过为2000-65535之间的随机端口）：" port
sleep 1
if [[ -z $port ]]; then
port=$(shuf -i 2000-65535 -n 1)
until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义x-ui端口:" port
done
else
until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义x-ui端口:" port
done
fi
sleep 1
/usr/local/x-ui/x-ui setting -port $port >/dev/null 2>&1
green "x-ui登录端口：${port}"
}
resinstall(){
echo "----------------------------------------------------------------------"
restart
curl -sL https://raw.githubusercontent.com/yonggekkk/x-ui-yg/main/version  | awk -F "更新内容" '{print $1}' | head -n 1 > /usr/local/x-ui/v
echo
xuilogin(){
v4=$(curl -s4m5 ip.sb -k)
v6=$(curl -s6m5 ip.sb -k)
if [[ -z $v4 ]]; then
int="请在浏览器地址栏输入 [$v6]:$port 进入x-ui登录界面\n
x-ui用户名：${username}\n
x-ui密码：${password}\n"
elif [[ -n $v4 && -n $v6 ]]; then
int="请在浏览器地址栏输入 $v4:$port 或者 [$v6]:$port 进入x-ui登录界面\n
x-ui用户名：${username}\n
x-ui密码：${password}\n"
else
int="请在浏览器地址栏输入 $v4:$port 进入x-ui登录界面\n
x-ui用户名：${username}\n
x-ui密码：${password}\n"
fi
}
sleep 2
green "启用定时任务（在其他设置选项中可自定义更改）：" && sleep 1
green "1、每天自动更新geoip/geosite文件" && sleep 1
green "2、每分钟执行x-ui监测守护" && sleep 1
green "3、每天重启一次x-ui" && sleep 1
xuigo
cronxui
echo "----------------------------------------------------------------------"
yellow "x-ui $(cat /usr/local/x-ui/v 2>/dev/null) 安装成功，请稍等3秒，输出x-ui登录信息……"
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
xuilogin
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
xuilogin
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
echo
blue "$int"
echo
echo
show_usage
}
xuiinstall(){
v6 && openyn
baseinstall
serinstall
blue "以下设置内容建议自定义，防止账号密码及端口被恶意扫描而泄露"
userinstall
portinstall
resinstall
[[ -e /etc/gai.conf ]] && grep -qE '^ *precedence ::ffff:0:0/96  100' /etc/gai.conf || echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf 2>/dev/null
}
update() {
yellow "升级也有可能出意外哦，建议如下："
yellow "1、点击x-ui面版中的备份与恢复，下载备份文件x-ui.db"
yellow "2、在 /etc/x-ui 路径导出备份文件x-ui.db"
readp "确定升级，请按回车(退出请按ctrl+c):" ins
if [[ -z $ins ]]; then
systemctl stop x-ui
rm /usr/local/x-ui/ -rf
serinstall && sleep 2
restart
curl -sL https://raw.githubusercontent.com/yonggekkk/x-ui-yg/main/version  | awk -F "更新内容" '{print $1}' | head -n 1 > /usr/local/x-ui/v
green "x-ui更新完成" && sleep 2 && x-ui
else
red "输入有误" && update
fi
}
uninstall() {
yellow "本次卸载将清除所有数据，建议如下："
yellow "1、点击x-ui面版中的备份与恢复，下载备份文件x-ui.db"
yellow "2、在 /etc/x-ui 路径导出备份文件x-ui.db"
readp "确定卸载，请按回车(退出请按ctrl+c):" ins
if [[ -z $ins ]]; then
systemctl stop x-ui
systemctl disable x-ui
rm /etc/systemd/system/x-ui.service -f
systemctl daemon-reload
systemctl reset-failed
rm /etc/x-ui/ -rf
rm /usr/local/x-ui/ -rf
rm /usr/bin/x-ui -f
uncronxui
rm -rf xuiyg_update
sed -i '/^precedence ::ffff:0:0\/96  100/d' /etc/gai.conf 2>/dev/null
green "x-ui已卸载完成"
else
red "输入有误" && uninstall
fi
}
reset_config() {
/usr/local/x-ui/x-ui setting -reset
sleep 1 
portinstall
}
stop() {
systemctl stop x-ui
check_status
if [[ $? == 1 ]]; then
crontab -l > /tmp/crontab.tmp
sed -i '/goxui.sh/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
green "x-ui停止成功"
else
red "x-ui停止失败，请运行 x-ui log 查看日志并反馈" && exit
fi
}
restart() {
systemctl restart x-ui
sleep 2
check_status
if [[ $? == 0 ]]; then
crontab -l > /tmp/crontab.tmp
sed -i '/goxui.sh/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
crontab -l > /tmp/crontab.tmp
echo "* * * * * /usr/local/x-ui/goxui.sh" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
green "x-ui重启成功"
else
red "x-ui重启失败，请运行 x-ui log 查看日志并反馈" && exit
fi
}
show_log() {
journalctl -u x-ui.service -e --no-pager -f
}
get_char(){
SAVEDSTTY=`stty -g`
stty -echo
stty cbreak
dd if=/dev/tty bs=1 count=1 2> /dev/null
stty -raw
stty echo
stty $SAVEDSTTY
}
back(){
white "------------------------------------------------------------------------------------"
white " 回x-ui主菜单，请按任意键"
white " 退出脚本，请按Ctrl+C"
get_char && show_menu
}
acme() {
bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
back
}
bbr() {
bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
back
}
cfwarp() {
bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
back
}
status() {
systemctl status x-ui -l
}
xuirestop(){
echo
readp "1. 停止 x-ui \n2. 重启 x-ui \n3. 返回主菜单\n请选择：" action
if [[ $action == "1" ]]; then
stop
elif [[ $action == "2" ]]; then
restart
elif [[ $action == "3" ]]; then
show_menu
else
red "输入错误,请重新选择" && xuirestop
fi
}
xuichange(){
echo
readp "1. 更改 x-ui 用户名与密码 \n2. 更改 x-ui 面板登录端口 \n3. 重置 x-ui 面板设置（面板设置选项中所有设置都装恢复出厂设置，登录端口将重新自定义，账号密码不变）\n4. 返回主菜单\n请选择：" action
if [[ $action == "1" ]]; then
userinstall && restart
elif [[ $action == "2" ]]; then
portinstall && restart
elif [[ $action == "3" ]]; then
reset_config && restart
elif [[ $action == "4" ]]; then
show_menu
else
red "输入错误,请重新选择" && xuichange
fi
}
# 0: running, 1: not running, 2: not installed
check_status() {
if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
return 2
fi
temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
if [[ x"${temp}" == x"running" ]]; then
return 0
else
return 1
fi
}
check_enabled() {
temp=$(systemctl is-enabled x-ui)
if [[ x"${temp}" == x"enabled" ]]; then
return 0
else
return 1
fi
}
check_uninstall() {
check_status
if [[ $? != 2 ]]; then
yellow "x-ui已安装，可先选择2卸载，再安装" && sleep 3
if [[ $# == 0 ]]; then
show_menu
fi
return 1
else
return 0
fi
}
check_install() {
check_status
if [[ $? == 2 ]]; then
yellow "未安装x-ui，请先安装x-ui" && sleep 3
if [[ $# == 0 ]]; then
show_menu
fi
return 1
else
return 0
fi
}
show_status() {
check_status
case $? in
0)
white "x-ui状态: \c";blue "已运行"
show_enable_status
;;
1)
white "x-ui状态: \c";yellow "未运行"
show_enable_status
;;
2)
white "x-ui状态: \c";red "未安装"
esac
show_xray_status
}
show_enable_status() {
check_enabled
if [[ $? == 0 ]]; then
white "x-ui自启: \c";blue "是"
else
white "x-ui自启: \c";red "否"
fi
}
check_xray_status() {
count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
if [[ count -ne 0 ]]; then
return 0
else
return 1
fi
}
show_xray_status() {
check_xray_status
if [[ $? == 0 ]]; then
white "xray状态: \c";blue "已启动"
else
white "xray状态: \c";red "未启动"
fi
}
show_usage() {
white "x-ui 快捷命令如下 "
white "------------------------------------------"
white "x-ui              - 显示 x-ui 管理菜单"
white "x-ui status       - 查看 x-ui 状态"
white "x-ui log          - 查看 x-ui 日志"
white "------------------------------------------"
}
xuigo(){
cat>/usr/local/x-ui/goxui.sh<<-\EOF
#!/bin/bash
xui=`ps -aux |grep "x-ui" |grep -v "grep" |wc -l`
xray=`ps -aux |grep "xray" |grep -v "grep" |wc -l`
if [ $xui = 0 ];then
x-ui restart
fi
if [ $xray = 0 ];then
x-ui restart
fi
EOF
chmod +x /usr/local/x-ui/goxui.sh
}
cronxui(){
uncronxui
crontab -l > /tmp/crontab.tmp
echo "0 3 * * * curl -sSL -o /usr/local/x-ui/bin/geoip.dat -z /usr/local/x-ui/bin/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" >> /tmp/crontab.tmp
echo "0 3 * * * curl -sSL -o /usr/local/x-ui/bin/geosite.dat -z /usr/local/x-ui/bin/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" >> /tmp/crontab.tmp
echo "* * * * * /usr/local/x-ui/goxui.sh" >> /tmp/crontab.tmp
echo "0 2 * * * x-ui restart" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}
uncronxui(){
crontab -l > /tmp/crontab.tmp
sed -i '/geoip.dat/d' /tmp/crontab.tmp
sed -i '/geosite.dat/d' /tmp/crontab.tmp
sed -i '/goxui.sh/d' /tmp/crontab.tmp
sed -i '/x-ui restart/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}
close(){
systemctl stop firewalld.service >/dev/null 2>&1
systemctl disable firewalld.service >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1
ufw disable >/dev/null 2>&1
iptables -P INPUT ACCEPT >/dev/null 2>&1
iptables -P FORWARD ACCEPT >/dev/null 2>&1
iptables -P OUTPUT ACCEPT >/dev/null 2>&1
iptables -t mangle -F >/dev/null 2>&1
iptables -F >/dev/null 2>&1
iptables -X >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
if [[ -n $(apachectl -v 2>/dev/null) ]]; then
systemctl stop httpd.service >/dev/null 2>&1
systemctl disable httpd.service >/dev/null 2>&1
service apache2 stop >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
fi
sleep 1
green "执行开放端口，关闭防火墙完毕"
}
openyn(){
echo
readp "是否开放端口，关闭防火墙？\n1、是，执行(回车默认)\n2、否，我自已手动\n请选择：" action
if [[ -z $action ]] || [[ $action == "1" ]]; then
close
elif [[ $action == "2" ]]; then
echo
else
red "输入错误,请重新选择" && openyn
fi
}
others(){
echo
readp "1. 开放端口，关闭防火墙 \n2. 查看、更改定时任务 \n3. 返回主菜单\n请选择：" action
if [[ $action == "1" ]]; then
close
elif [[ $action == "2" ]]; then
crontab -e
elif [[ $action == "3" ]]; then
show_menu
else
red "输入错误,请重新选择" && others
fi
}
show_menu(){
clear
green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"           
echo -e "${bblue} ░██     ░██      ░██ ██ ██         ░█${plain}█   ░██     ░██   ░██     ░█${red}█   ░██${plain}  "
echo -e "${bblue}  ░██   ░██      ░██    ░░██${plain}        ░██  ░██      ░██  ░██${red}      ░██  ░██${plain}   "
echo -e "${bblue}   ░██ ░██      ░██ ${plain}                ░██ ██        ░██ █${red}█        ░██ ██  ${plain}   "
echo -e "${bblue}     ░██        ░${plain}██    ░██ ██       ░██ ██        ░█${red}█ ██        ░██ ██  ${plain}  "
echo -e "${bblue}     ░██ ${plain}        ░██    ░░██        ░██ ░██       ░${red}██ ░██       ░██ ░██ ${plain}  "
echo -e "${bblue}     ░█${plain}█          ░██ ██ ██         ░██  ░░${red}██     ░██  ░░██     ░██  ░░██ ${plain}  "
green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "甬哥Github项目  ：github.com/yonggekkk"
white "甬哥blogger博客 ：ygkkk.blogspot.com"
white "甬哥YouTube频道 ：www.youtube.com/@ygkkk"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. 安装 x-ui"
green " 2. 卸载 x-ui"
echo "----------------------------------------------------------------------------------"
green " 3. 更新 x-ui"
green " 4. 停止、重启 x-ui"
green " 5. 变更 x-ui 设置（1.用户名密码 2.登录端口 3.还原面板设置）"
green " 6. 查看 x-ui 运行日志"
echo "----------------------------------------------------------------------------------"
green " 7. 其他设置（1.开放端口 2.定时任务）"
green " 8. 安装 BBR+FQ 加速"
green " 9. 管理 ACME 证书申请"
green "10. 管理 WARP"
green " 0. 退出脚本"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
insV=$(cat /usr/local/x-ui/v 2>/dev/null)
latestV=$(curl -sL https://raw.githubusercontent.com/yonggekkk/x-ui-yg/main/version  | awk -F "更新内容" '{print $1}' | head -n 1)
if [[ -f /usr/local/x-ui/v ]]; then
if [ "$insV" = "$latestV" ]; then
echo -e "当前 x-ui 脚本版本号：${bblue}${insV}${plain} 已是最新版本\n"
else
echo -e "当前 x-ui 脚本版本号：${bblue}${insV}${plain}"
echo -e "检测到最新 x-ui 脚本版本号：${yellow}${latestV}${plain}"
echo -e "${yellow}$(curl -sL https://raw.githubusercontent.com/yonggekkk/x-ui-yg/main/version)${plain}"
echo -e "可选择3进行更新\n"
fi
else
echo -e "当前 x-ui 脚本版本号：${bblue}${latestV}${plain} 已是最新版本\n"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
white "VPS系统信息如下："
white "操作系统:   $(blue "$op")" && white "内核版本:   $(blue "$version")" && white "CPU架构 :   $(blue "$cpu")" && white "虚拟化类型: $(blue "$vi")"
echo "------------------------------------------"
show_status
echo "------------------------------------------"
acp=$(/usr/local/x-ui/x-ui setting -show 2>/dev/null)
if [[ -n $acp ]]; then
white "x-ui登录信息如下：" && blue "$acp" 
else
white "x-ui登录信息如下：" && red "未安装x-ui，无显示"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
readp " 请输入数字:" Input
case "$Input" in     
 1 ) check_uninstall && xuiinstall;;
 2 ) check_install && uninstall;;
 3 ) check_install && update;;
 4 ) check_install && xuirestop;;
 5 ) check_install && xuichange;;
 6 ) check_install && show_log;;
 7 ) others;;
 8 ) bbr;;
 9 ) acme;;
 10 ) cfwarp;;
 * ) exit 
esac
}
if [[ $# > 0 ]]; then
case $1 in
"status") check_install 0 && status 0
;;
"log") check_install 0 && show_log 0
;;
*) show_usage
esac
else
show_menu
fi
