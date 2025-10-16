#!/bin/sh

# =====================================================================================
#  OpenWrt 路由器终极性能优化脚本 v3.3 (智能驱动版)
#
#  更新日志 (v3.3):
#  - [优化] 澄清了 CPU 监控插件 (collectd) 与内核驱动 (kmod) 的区别。
#  - [核心] 保留并强化了自动检测和安装缺失的 CPU 频率内核驱动 (`kmod-mt7621-cpufreq`) 的功能。
#  - [优化] 改进了脚本输出的文本和颜色，使其更具指导性和可读性。
# =====================================================================================

# --- 颜色定义 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 函数：检查 Root 权限 ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：此脚本必须以 root 权限运行。${NC}" >&2
        exit 1
    fi
}

# --- 函数：应用 Sysctl 内核参数 ---
apply_sysctl_settings() {
    echo -e "${GREEN}>>> 步骤 1/5: 正在通过 UCI 应用和持久化内核参数...${NC}"

    uci -q batch << EOI
set system.@system[0].log_size='64'
set system.@system[0].urandom_seed='0'
set system.ntp='timeserver'
set system.ntp.enabled='1'
set system.ntp.server_host='ntp.aliyun.com' 'cn.pool.ntp.org' 'time.windows.com'

# --- 核心网络调优 (高吞吐 & 低延迟) ---
set system.@system[0].default_qdisc='fq_codel'
set system.@system[0].tcp_congestion_control='bbr'

# --- 连接跟踪 (路由器核心) ---
set system.@system[0].nf_conntrack_max='65536'

# --- TCP/IP 栈优化 ---
set system.@system[0].netdev_max_backlog='16384'
set system.@system[0].somaxconn='16384'
set system.@system[0].tcp_fastopen='3'
set system.@system[0].tcp_fin_timeout='25'
set system.@system[0].tcp_keepalive_time='1200'
set system.@system[0].tcp_max_syn_backlog='8192'
set system.@system[0].tcp_syn_retries='3'
set system.@system[0].tcp_synack_retries='3'
set system.@system[0].tcp_tw_reuse='1'
set system.@system[0].udp_rmem_min='8192'
set system.@system[0].udp_wmem_min='8192'
EOI

    uci commit system
    echo "内核参数已通过 UCI 提交。"
}

# --- 函数：启用流卸载 ---
enable_flow_offloading() {
    echo -e "${GREEN}>>> 步骤 2/5: 正在启用软件和硬件流卸载...${NC}"

    uci -q batch << EOI
set firewall.@defaults[0].flow_offloading='1'
set firewall.@defaults[0].flow_offloading_hw='1'
EOI

    uci commit firewall
    echo "流卸载 (Flow Offloading) 已启用。"
}

# --- 函数：设置并持久化 CPU 性能模式 ---
set_persistent_cpu_governor() {
    echo -e "${GREEN}>>> 步骤 3/5: 正在检查并设置 CPU 性能模式...${NC}"

    local governor_path=$(find /sys/devices/system/cpu/ -name scaling_governor | head -n 1)

    # 如果找不到控制文件，说明缺少核心驱动
    if [ -z "${governor_path}" ]; then
        echo -e "${YELLOW}警告: 未找到 CPU 频率控制接口。这通常意味着缺少内核驱动。${NC}"
        echo -e "${YELLOW}注意: 'collectd-mod-cpufreq' 是监控工具, 'kmod-mt7621-cpufreq' 才是控制驱动。${NC}"
        echo "正在尝试自动安装 'kmod-mt7621-cpufreq' 驱动..."
        
        # 自动安装
        opkg update
        if opkg install kmod-mt7621-cpufreq; then
            echo -e "${GREEN}驱动安装成功！正在尝试加载模块...${NC}"
            modprobe mt7621_cpufreq
            sleep 2 # 等待 sysfs 文件系统更新
            # 再次查找路径
            governor_path=$(find /sys/devices/system/cpu/ -name scaling_governor | head -n 1)
        else
            echo -e "${RED}错误: 内核驱动安装失败。请检查网络或固件软件源。${NC}"
            governor_path="" # 确保路径为空，跳过后续设置
        fi
    fi

    # 检查路径是否有效且可写
    if [ -n "${governor_path}" ] && [ -w "${governor_path}" ]; then
        echo "正在设置 CPU 为 'performance' 模式并配置开机自启..."
        echo 'performance' > "${governor_path}"

        local rc_local_file="/etc/rc.local"
        local set_gov_cmd="echo 'performance' > ${governor_path}"
        local marker="# Set CPU governor for performance (by optimization script)"

        # 检查是否已存在标记，防止重复写入
        if ! grep -q "${marker}" "${rc_local_file}"; then
            sed -i "/^exit 0/i\\${marker}\n${set_gov_cmd}\n" "${rc_local_file}"
            echo -e "${GREEN}成功: CPU 'performance' 模式已配置为开机自启。${NC}"
        else
            echo "CPU 'performance' 模式开机自启项已存在，无需重复添加。"
        fi
    else
        echo -e "${YELLOW}警告: CPU 性能模式设置失败。跳过此项优化。${NC}"
        echo -e "${YELLOW}如果已自动安装驱动，请重启路由器后再试。${NC}"
    fi
}

# --- 主函数 ---
main() {
    check_root

    echo "--- 开始执行 OpenWrt 性能优化 (v3.3 - 智能驱动版) ---"

    apply_sysctl_settings
    enable_flow_offloading
    set_persistent_cpu_governor

    echo -e "${GREEN}>>> 步骤 4/5: 正在应用所有配置...${NC}"

    # 在后台重启服务，避免阻塞
    /etc/init.d/firewall restart >/dev/null 2>&1 &
    /etc/init.d/system reload >/dev/null 2>&1 &

    echo ""
    echo -e "${GREEN}==========================================================================${NC}"
    echo -e "${GREEN}      >>> 步骤 5/5: 优化完成！所有设置已应用并持久化。${NC}"
    echo -e "${YELLOW}      为确保所有更改（尤其是新安装的内核驱动）完美生效，${NC}"
    echo -e "${YELLOW}      强烈建议您现在重启路由器： reboot${NC}"
    echo -e "${GREEN}==========================================================================${NC}"
}

# --- 脚本入口 ---
main
