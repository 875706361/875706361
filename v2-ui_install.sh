#!/bin/bash
cd
wget https://github.com/875706361/875706361/raw/master/v2-ui-linux.tar.gz
mv v2-ui-linux.tar.gz /usr/local/
cd /usr/local/
tar zxvf v2-ui-linux.tar.gz
rm v2-ui-linux.tar.gz -f
cd v2-ui
chmod +x v2-ui bin/v2ray-v2-ui bin/v2ctl
cp -f v2-ui.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable v2-ui
systemctl restart v2-ui
cd /tmp
wget https://raw.githubusercontent.com/sprov065/v2-ui/master/v2-ui.sh
mv v2-ui.sh /usr/bin/v2-ui
chmod 777 /usr/bin/v2-ui
cd
bash <(curl -s -L https://233blog.com/v2ray.sh)
v2-ui
