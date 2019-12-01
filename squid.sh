#!/bin/bash
#
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