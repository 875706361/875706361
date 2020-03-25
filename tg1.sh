#!bin/bash
#MTProxy代理官方建议每天更新的文件脚本
cd MTProxy
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
