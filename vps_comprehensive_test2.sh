#!/bin/bash
# vps_comprehensive_test.sh
# 针对 LXC 架构及 IPv6 环境优化的综合检测脚本

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${PURPLE}==================================================${NC}"
echo -e "${PURPLE}       VPS 性能检测综合脚本 (LXC/IPv6 优化版)      ${NC}"
echo -e "${PURPLE}==================================================${NC}"

# 工具检查与安装
install_tools() {
    echo -e "${CYAN}--- 正在检查必要工具 ---${NC}"
    apt-get update -qq
    apt-get install -y -qq curl wget bc fio dnsutils jq python3-pip &>/dev/null
    if ! command -v speedtest-cli &> /dev/null; then
        pip3 install speedtest-cli --break-system-packages &>/dev/null
    fi
}

# 1. 系统信息
system_info() {
    echo -e "\n${BLUE}[1. 系统信息]${NC}"
    echo -e "主机名:     $(hostname)"
    echo -e "操作系统:   $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo -e "内核版本:   $(uname -r)"
    echo -e "虚拟化架构: $(systemd-detect-virt)"
    echo -e "CPU型号:    $(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')"
    echo -e "CPU核心:    $(nproc) 核"
    echo -e "内存情况:   $(free -h | awk '/Mem:/ {print $3 "/" $2}')"
    echo -e "硬盘空间:   $(df -h / | awk 'NR==2 {print $3 "/" $2}')"
}

# 2. CPU 性能测试 (圆周率计算)
cpu_test() {
    echo -e "\n${BLUE}[2. CPU 性能测试 (PI计算)]${NC}"
    echo -n "单核计算 5000位圆周率耗时: "
    local start=$(date +%s.%N)
    echo "scale=5000; 4*a(1)" | bc -l -q > /dev/null 2>&1
    local end=$(date +%s.%N)
    echo -e "${YELLOW}$(echo "$end - $start" | bc) 秒${NC}"
}

# 3. 磁盘 I/O 测试
disk_test() {
    echo -e "\n${BLUE}[3. 磁盘 I/O 测试 (Fio)]${NC}"
    # 随机写测试
    echo -n "4K 随机写入 IOPS: "
    local iops_w=$(fio --name=test --rw=randwrite --bs=4k --runtime=10 --iodepth=64 --filename=iotest.tmp --ioengine=libaio --direct=1 --group_reporting | grep "IOPS=" | awk -F"[=,]" '{print $2}')
    echo -e "${YELLOW}$iops_w${NC}"
    # 顺序读测试
    echo -n "顺序读取速度: "
    local bw_r=$(dd if=iotest.tmp of=/dev/null bs=1M count=512 2>&1 | tail -1 | awk '{print $NF, $(NF-1)}')
    echo -e "${YELLOW}$bw_r${NC}"
    rm -f iotest.tmp
}

# 4. 网络连通性 (IPv4/IPv6)
network_test() {
    echo -e "\n${BLUE}[4. 网络质量与 IP 信息]${NC}"
    local ipv4=$(curl -s4 --connect-timeout 5 ifconfig.me || echo "无IPv4/NAT")
    local ipv6=$(curl -s6 --connect-timeout 5 ifconfig.me || echo "无公网IPv6")
    echo -e "IPv4 地址: ${YELLOW}$ipv4${NC}"
    echo -e "IPv6 地址: ${YELLOW}$ipv6${NC}"
    
    echo -n "Google IPv6 延迟: "
    ping6 -c 3 google.com >/dev/null 2>&1 && ping6 -c 3 google.com | awk -F'/' 'END {print $5 " ms"}' || echo "不通"
    
    echo -n "Cloudflare 延迟: "
    ping -c 3 1.1.1.1 >/dev/null 2>&1 && ping -c 3 1.1.1.1 | awk -F'/' 'END {print $5 " ms"}' || echo "不通"
}

# 5. 下载速度测试 (更新了更可靠的节点)
download_test() {
    echo -e "\n${BLUE}[5. 全球大文件下载测试]${NC}"
    local nodes=(
        "https://speed.cloudflare.com/__down?bytes=104857600 Cloudflare-全球"
        "https://jp.host-test.net/100mb.bin 日本-本地"
        "http://cachefly.cachefly.net/100mb.test Cachefly-CDN"
        "https://sgp-ping.vultr.com/vultr.com.100MB.bin 新加坡-Vultr"
    )

    for node in "${nodes[@]}"; do
        local url=$(echo $node | awk '{print $1}')
        local name=$(echo $node | awk '{print $2}')
        echo -n "$name: "
        curl -L -o /dev/null -s -w "%{speed_download}" --connect-timeout 10 "$url" | awk '{printf "%.2f MB/s\n", $1/1048576}' || echo "下载失败"
    done
}

# 6. 流媒体解锁检测
media_unlock_test() {
    echo -e "\n${BLUE}[6. 流媒体解锁检测]${NC}"
    # Netflix JP
    local nf=$(curl -s4 "https://www.netflix.com/title/81215567" | grep -o "Not Available" &>/dev/null && echo -e "${RED}失败${NC}" || echo -e "${GREEN}解锁 (JP)${NC}")
    echo -e "Netflix 日本: $nf"
    
    # ChatGPT
    local chat=$(curl -sS https://chatgpt.com 2>&1 | grep -q "blocked" && echo -e "${RED}被墙${NC}" || echo -e "${GREEN}可用${NC}")
    echo -e "ChatGPT 访问: $chat"
}

# 执行流程
install_tools
system_info
cpu_test
disk_test
network_test
download_test
media_unlock_test

echo -e "\n${PURPLE}==================================================${NC}"
echo -e "              测试完成，祝你折腾愉快！             "
echo -e "${PURPLE}==================================================${NC}"