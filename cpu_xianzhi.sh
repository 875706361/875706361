#!/bin/bash

LOG_FILE="/var/log/cpu_limit.log"
LIMIT_RATE=50   # 限制为50%CPU，可根据需要调整
CHECK_INTERVAL=3

log() {
    echo "$(date '+%F %T') - $1" >> "$LOG_FILE"
}

while true; do
    # 查找所有xray进程PID
    for pid in $(pgrep xray); do
        # 检查该PID是否已经被cpulimit限制
        if ! pgrep -f "cpulimit.*-p $pid" > /dev/null; then
            log "限制xray进程 PID=$pid CPU到${LIMIT_RATE}%"
            cpulimit -p $pid -l $LIMIT_RATE -b
        fi
    done
    sleep $CHECK_INTERVAL
done
