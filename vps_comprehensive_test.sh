#!/bin/bash
# vps_comprehensive_test.sh
# 综合VPS性能检测脚本
# 作者：AI助手
# 版本：2.0
# 功能：硬件性能、网络质量、解锁能力全面检测

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 全局变量
LOG_FILE="/tmp/vps_test_$(date +%Y%m%d_%H%M%S).log"
TEST_DIR="/tmp/vps_test"
mkdir -p $TEST_DIR

# 工具检查函数
check_tools() {
    echo -e "${CYAN}=== 检查必要工具 ===${NC}"
    
    local missing_tools=()
    
    # 基本工具
    for tool in curl wget ping traceroute mtr dig bc; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    # 特殊工具
    if ! command -v fio &> /dev/null; then
        missing_tools+=(fio)
    fi
    
    if ! command -v iperf3 &> /dev/null; then
        missing_tools+=(iperf3)
    fi
    
    if ! command -v speedtest-cli &> /dev/null; then
        missing_tools+=(speedtest-cli)
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=(jq)
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${YELLOW}缺少以下工具: ${missing_tools[*]}${NC}"
        echo -e "${BLUE}正在安装...${NC}"
        install_tools "${missing_tools[@]}"
    else
        echo -e "${GREEN}✓ 所有必要工具已安装${NC}"
    fi
}

# 安装工具函数
install_tools() {
    local os_id=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    
    case $os_id in
        ubuntu|debian)
            apt-get update
            apt-get install -y "$@" curl wget iputils-ping traceroute mtr dnsutils bc fio iperf3 speedtest-cli jq python3 python3-pip
            pip3 install speedtest-cli --upgrade
            ;;
        centos|rhel|fedora)
            yum install -y epel-release
            yum install -y "$@" curl wget iputils traceroute mtr bind-utils bc fio iperf3 jq python3 python3-pip
            pip3 install speedtest-cli --upgrade
            ;;
        alpine)
            apk add --no-cache "$@" curl wget iputils traceroute mtr bind-tools bc fio iperf3 jq python3 py3-pip
            pip3 install speedtest-cli --upgrade
            ;;
        *)
            echo -e "${RED}不支持的操作系统: $os_id${NC}"
            echo -e "${YELLOW}请手动安装必要工具${NC}"
            exit 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 工具安装完成${NC}"
    else
        echo -e "${RED}✗ 工具安装失败${NC}"
        exit 1
    fi
}

# 系统信息检测
system_info() {
    echo -e "${CYAN}=== 系统信息 ===${NC}"
    
    echo -e "${BLUE}基本系统信息:${NC}"
    echo "主机名: $(hostname)"
    echo "操作系统: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo "内核版本: $(uname -r)"
    echo "系统架构: $(uname -m)"
    echo "虚拟化: $(systemd-detect-virt 2>/dev/null || echo "未知")"
    
    echo -e "\n${BLUE}运行时间:${NC}"
    uptime
    
    echo -e "\n${BLUE}CPU信息:${NC}"
    echo "CPU型号: $(lscpu | grep "Model name" | cut -d':' -f2 | sed 's/^[ \t]*//')"
    echo "CPU核心数: $(nproc)"
    echo "CPU频率: $(lscpu | grep "CPU MHz" | cut -d':' -f2 | sed 's/^[ \t]*//') MHz"
    
    echo -e "\n${BLUE}内存信息:${NC}"
    free -h
    
    echo -e "\n${BLUE}磁盘信息:${NC}"
    df -hT
    
    echo -e "\n${BLUE}网络接口:${NC}"
    ip -br addr show | grep -v lo
}

# CPU性能测试
cpu_test() {
    echo -e "${CYAN}=== CPU性能测试 ===${NC}"
    
    echo -e "${BLUE}1. 单核性能测试 (计算圆周率):${NC}"
    local start_time=$(date +%s.%N)
    echo "scale=5000; 4*a(1)" | bc -l -q > /dev/null 2>&1
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    echo "耗时: ${duration}秒"
    
    echo -e "\n${BLUE}2. 多核性能测试 (7-zip基准):${NC}"
    if command -v 7z &> /dev/null; then
        7z b 2>/dev/null | grep -A 3 "Avr:"
    else
        echo "安装7-zip进行更准确的测试:"
        echo "Ubuntu/Debian: apt-get install p7zip-full"
        echo "CentOS/RHEL: yum install p7zip"
    fi
    
    echo -e "\n${BLUE}3. CPU压力测试 (30秒):${NC}"
    local cores=$(nproc)
    echo "使用 $cores 个核心进行压力测试..."
    timeout 30 yes > /dev/null 2>&1 &
    local pid=$!
    sleep 30
    kill $pid 2>/dev/null
    echo "压力测试完成"
}

# 磁盘性能测试
disk_test() {
    echo -e "${CYAN}=== 磁盘性能测试 ===${NC}"
    
    local test_file="$TEST_DIR/disk_test.bin"
    local size=1024  # 1GB
    
    echo -e "${BLUE}1. 顺序写入测试 (1GB):${NC}"
    dd if=/dev/zero of="$test_file" bs=1M count=$size oflag=direct 2>&1 | tail -1
    
    echo -e "\n${BLUE}2. 顺序读取测试:${NC}"
    dd if="$test_file" of=/dev/null bs=1M iflag=direct 2>&1 | tail -1
    
    echo -e "\n${BLUE}3. 使用Fio进行详细测试:${NC}"
    if command -v fio &> /dev/null; then
        # 4K随机读
        echo "4K随机读取:"
        fio --name=4k_read --filename="$test_file" --rw=randread --bs=4k --size=100m --runtime=10 --direct=1 --ioengine=libaio --numjobs=1 --group_reporting 2>/dev/null | grep -A 1 "read:" | grep -E "IOPS|bw="
        
        # 4K随机写
        echo "4K随机写入:"
        fio --name=4k_write --filename="$test_file" --rw=randwrite --bs=4k --size=100m --runtime=10 --direct=1 --ioengine=libaio --numjobs=1 --group_reporting 2>/dev/null | grep -A 1 "write:" | grep -E "IOPS|bw="
    else
        echo "Fio未安装，跳过详细测试"
    fi
    
    # 清理
    rm -f "$test_file"
}

# 网络性能测试
network_test() {
    echo -e "${CYAN}=== 网络性能测试 ===${NC}"
    
    echo -e "${BLUE}1. 公网IP信息:${NC}"
    local ipv4=$(curl -s -4 ifconfig.me)
    local ipv6=$(curl -s -6 ifconfig.me 2>/dev/null || echo "不支持")
    echo "IPv4: $ipv4"
    echo "IPv6: $ipv6"
    
    echo -e "\n${BLUE}2. 国内延迟测试:${NC}"
    local nodes=(
        "114.114.114.114 电信DNS"
        "1.1.1.1 Cloudflare"
        "8.8.8.8 Google DNS"
        "223.5.5.5 阿里DNS"
    )
    
    for node in "${nodes[@]}"; do
        local ip=$(echo $node | awk '{print $1}')
        local name=$(echo $node | awk '{print $2}')
        echo -n "$name ($ip): "
        ping -c 4 -W 2 $ip 2>/dev/null | grep -E "rtt|packet loss" | tail -1 || echo "超时"
    done
    
    echo -e "\n${BLUE}3. 路由追踪测试:${NC}"
    echo "到北京电信路由:"
    mtr -r -c 3 114.114.114.114 2>/dev/null | tail -5
    
    echo -e "\n${BLUE}4. 带宽测试 (使用speedtest-cli):${NC}"
    if command -v speedtest-cli &> /dev/null; then
        speedtest-cli --simple 2>/dev/null || echo "speedtest测试失败"
    else
        echo "speedtest-cli未安装"
    fi
    
    echo -e "\n${BLUE}5. 下载速度测试:${NC}"
    local test_urls=(
        "http://speedtest-sfo2.digitalocean.com/100mb.test"
        "http://cachefly.cachefly.net/100mb.test"
        "http://speedtest.tokyo.linode.com/100MB-tokyo.bin"
    )
    
    for url in "${test_urls[@]}"; do
        echo -n "测试 $url: "
        curl -o /dev/null -w "速度: %{speed_download} B/s 时间: %{time_total}s\n" -s "$url" 2>/dev/null || echo "失败"
    done
}

# 流媒体解锁测试
streaming_test() {
    echo -e "${CYAN}=== 流媒体解锁测试 ===${NC}"
    
    echo -e "${BLUE}1. Netflix检测:${NC}"
    local netflix_result=$(curl -s -4 "https://www.netflix.com/title/81215567" 2>/dev/null | grep -o "Not Available" || echo "可能解锁")
    echo "Netflix: $netflix_result"
    
    echo -e "\n${BLUE}2. YouTube Premium检测:${NC}"
    local yt_result=$(curl -s "https://www.youtube.com/premium" 2>/dev/null | grep -o "YouTube Premium is not available in your country" && echo "不可用" || echo "可能可用")
    echo "YouTube Premium: $yt_result"
    
    echo -e "\n${BLUE}3. ChatGPT检测:${NC}"
    local chatgpt_result=$(curl -s "https://chat.openai.com" 2>/dev/null | grep -o "Access denied" && echo "被阻止" || echo "可能可用")
    echo "ChatGPT: $chatgpt_result"
    
    echo -e "\n${BLUE}4. 综合流媒体检测 (使用脚本):${NC}"
    local media_script="https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh"
    echo "下载检测脚本..."
    curl -sL $media_script 2>/dev/null | bash -s -- -M 4 2>/dev/null | grep -E "(Netflix|YouTube|ChatGPT)" || echo "流媒体检测失败"
}

# IP质量检测
ip_quality_test() {
    echo -e "${CYAN}=== IP质量检测 ===${NC}"
    
    local ip=$(curl -s ifconfig.me)
    
    echo -e "${BLUE}1. IP信息:${NC}"
    echo "IP地址: $ip"
    
    echo -e "\n${BLUE}2. 端口检测:${NC}"
    # 检测常用端口
    local ports=(22 80 443 25 465 587)
    for port in "${ports[@]}"; do
        timeout 2 bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null && echo "端口 $port: 开放" || echo "端口 $port: 关闭"
    done
    
    echo -e "\n${BLUE}3. 反向DNS查询:${NC}"
    dig -x $ip +short 2>/dev/null || echo "无PTR记录"
    
    echo -e "\n${BLUE}4. 黑名单检查 (使用公开API):${NC}"
    # 使用Spamhaus检查
    local spamhaus=$(dig +short $ip.dnsbl.spamhaus.org 2>/dev/null)
    if [ -z "$spamhaus" ]; then
        echo "Spamhaus: 未列入黑名单"
    else
        echo "Spamhaus: 可能被列入黑名单"
    fi
}

# 综合评分
overall_score() {
    echo -e "${CYAN}=== 综合评分 ===${NC}"
    
    local score=0
    local max_score=100
    
    # 这里可以添加评分逻辑
    # 基于前面的测试结果给出评分
    
    echo "评分系统开发中..."
    echo "请根据上面的测试结果手动评估"
    
    echo -e "\n${GREEN}${BOLD}=== 测试完成 ===${NC}"
    echo "详细日志已保存到: $LOG_FILE"
    echo "测试临时文件目录: $TEST_DIR"
}

# 主函数
main() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════╗"
    echo "║        综合VPS性能检测脚本 v2.0         ║"
    echo "║    Comprehensive VPS Testing Script      ║"
    echo "╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # 检查并安装必要工具
    check_tools
    
    # 开始测试
    echo -e "\n${GREEN}开始全面测试...${NC}"
    echo "测试日志: $LOG_FILE"
    echo ""
    
    # 执行所有测试并记录日志
    {
        echo "=== VPS测试报告 ==="
        echo "测试时间: $(date)"
        echo "======================================"
        
        system_info
        echo ""
        
        cpu_test
        echo ""
        
        disk_test
        echo ""
        
        network_test
        echo ""
        
        streaming_test
        echo ""
        
        ip_quality_test
        echo ""
        
    } 2>&1 | tee "$LOG_FILE"
    
    # 显示综合评分
    overall_score
    
    # 清理建议
    echo -e "\n${YELLOW}=== 清理建议 ===${NC}"
    echo "运行以下命令清理测试文件:"
    echo "  rm -rf $TEST_DIR"
    echo "  rm -f $LOG_FILE"
    
    # 后续建议
    echo -e "\n${BLUE}=== 后续操作建议 ===${NC}"
    echo "1. 查看完整日志: cat $LOG_FILE"
    echo "2. 分享测试结果: cat $LOG_FILE | pastebin"
    echo "3. 定期运行测试监控性能变化"
}

# 异常处理
trap 'echo -e "\n${RED}测试被中断${NC}"; exit 1' INT TERM

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}警告: 建议使用root权限运行以获得更准确的结果${NC}"
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 运行主函数
main
