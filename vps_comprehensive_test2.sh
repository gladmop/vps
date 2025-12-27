#!/bin/bash
# vps_final_test.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${PURPLE}==================================================${NC}"
echo -e "${PURPLE}       VPS 终极检测脚本 (针对 LXC/IPv6 深度修正)        ${NC}"
echo -e "${PURPLE}==================================================${NC}"

# 1. 系统信息
echo -e "\n${BLUE}[1. 系统环境]${NC}"
echo -e "虚拟化:   $(systemd-detect-virt)"
echo -e "CPU型号:  $(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')"
echo -e "核心数:   $(nproc) 核"
echo -e "负载:     $(uptime | awk -F'load average:' '{print $2}')"

# 2. CPU 性能测试
echo -e "\n${BLUE}[2. CPU 算力测试]${NC}"
echo -n "PI 计算 5000位耗时: "
start=$(date +%s.%N)
echo "scale=5000; 4*a(1)" | bc -l -q > /dev/null 2>&1
end=$(date +%s.%N)
echo -e "${YELLOW}$(echo "$end - $start" | bc) 秒${NC}"

# 3. 磁盘 I/O 修正测试
echo -e "\n${BLUE}[3. 磁盘性能测试 (修正版)]${NC}"
# 强制指定 size=100M 以兼容 LXC
fio --name=test --rw=randwrite --bs=4k --size=100M --runtime=10 --iodepth=64 --filename=iotest.tmp --ioengine=libaio --direct=1 --group_reporting > fio.log 2>&1
iops=$(grep "IOPS=" fio.log | awk -F"[=,]" '{print $2}')
if [ -z "$iops" ]; then iops="测试受限"; fi
echo -e "4K 随机写入 IOPS: ${YELLOW}$iops${NC}"

dd if=/dev/urandom of=iotest.tmp bs=1M count=100 conv=fsync > /dev/null 2>&1
speed=$(dd if=iotest.tmp of=/dev/null bs=1M 2>&1 | tail -1 | awk '{print $NF, $(NF-1)}')
echo -e "顺序读取速度:    ${YELLOW}$speed${NC}"
rm -f iotest.tmp fio.log

# 4. 深度下载测试 (更换更稳的节点)
echo -e "\n${BLUE}[4. 全球大文件下载速度]${NC}"
nodes=(
    "https://speed.cloudflare.com/__down?bytes=100000000 Cloudflare-全球"
    "https://pivp.v6.rocks/100mb.bin IPv6-专线测试"
    "https://mirror.accum.se/debian-cd/current/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso Debian-瑞典"
)

for node in "${nodes[@]}"; do
    url=$(echo $node | awk '{print $1}')
    name=$(echo $node | awk '{print $2}')
    echo -n "$name: "
    curl -L -o /dev/null -s -w "%{speed_download}" --connect-timeout 5 "$url" | awk '{printf "%.2f MB/s\n", $1/1048576}' || echo "连接失败"
done

# 5. 解锁测试
echo -e "\n${BLUE}[5. 核心解锁检测]${NC}"
# Netflix
nf=$(curl -s4 "https://www.netflix.com/title/81215567" | grep -o "Not Available" &>/dev/null && echo -e "${RED}失败${NC}" || echo -e "${GREEN}解锁 (JP)${NC}")
echo -e "Netflix 日本: $nf"
# ChatGPT
chat=$(curl -sS https://chatgpt.com 2>&1 | grep -q "blocked" && echo -e "${RED}被墙${NC}" || echo -e "${GREEN}可用${NC}")
echo -e "ChatGPT 访问: $chat"

echo -e "\n${PURPLE}==================================================${NC}"
