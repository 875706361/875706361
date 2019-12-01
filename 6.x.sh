#! /bin/sh

# update yum
yum -y update
yum upgrade -y

# 1、安装yum优先级插件
yum install yum-priorities

# 2、epel
rpm -Uvh https://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
rpm -Uvh http://rpms.remirepo.net/enterprise/remi-release-6.rpm
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-6

# 3、修改/etc/yum.repos.d/epel.repo文件
sed -i '$a priority=11' /etc/yum.repos.d/epel.repo

# 4、重建缓存
yum makecache

# 5、安装Yum加速组件
yum -y install yum-fastestmirror
yum repolist
yum clean all
yum makecache

# 6、安装常用工具
yum -y install vim-enhanced wget lrzsz
yum -y install gcc gcc-c++ kernel-devel ntp vim-enhanced flex bison autoconf make automake bzip2-devel ncurses-devel zlib-devel libjpeg-devel libpng-devel libtiff-devel freetype-devel libXpm-devel gettext-devel pam-devel libtool libtool-ltdl openssl openssl-devel fontconfig-devel libxml2-devel curl-devel libicu libicu-devel libmcrypt libmcrypt-devel libmhash libmhash-devel pcre-devel libtool-libs gd file patch mlocate diffutils readline-devel glibc-devel glib2-devel libcap-devel

# 7、安装编译软件等所需开发工具包组
yum -y groupinstall "Desktop Platform Development" "Development tools" "Server Platform Development"

# 8、selinux
setenforce 0
sed -i s/SELINUX=enforcing/SELINUX=disabled/g /etc/selinux/config

# 9、时间同步
cronfileroot="/var/spool/cron/root"
cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
if [ ! -f $cronfileroot ]; then
touch ${cronfileroot}
chmod 600 ${cronfileroot}
fi
sed -i '$a */30 * * * * /usr/sbin/ntpdate us.pool.ntp.org >> /var/log/crontab.log 2>&1' ${cronfileroot}
service crond restart

# 10、ulimit
sed -i '$a * - nproc 102400' /etc/security/limits.conf
sed -i '$a * - nofile 102400' /etc/security/limits.conf

# 11、nload
yum install -y nload

# 12、iftop
yum install -y iftop
