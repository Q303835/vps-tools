#!/bin/bash

# ====================================================
# 脚本功能：自动识别云商（修复 Oracle 误报）、双首字母大写、递增编号、全能运维
# ====================================================

if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请使用 root 权限运行。"
  exit 1
fi

echo "✨ 正在启动全能运维脚本 V3.4 (Oracle Fix)..."

# --- 1. 精准识别云商与 Region ---
get_metadata() {
    # 优先检测 Oracle (使用其固定的元数据 IP)
    ORA_TEST=$(curl -s -m 2 http://192.0.0.192/1.0/meta-data/instance/region 2>/dev/null)
    
    # 1. Oracle 判断
    if [ -n "$ORA_TEST" ]; then
        PROVIDER="oracle"
        REGION="$ORA_TEST"
    # 2. Azure 判断 (通过 DMI)
    elif [ -f /sys/class/dmi/id/sys_vendor ] && grep -q "Microsoft" /sys/class/dmi/id/sys_vendor; then
        PROVIDER="azure"
        REGION=$(curl -s -m 2 -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
    # 3. AWS 判断
    elif [ -f /sys/class/dmi/id/sys_vendor ] && grep -q "Amazon" /sys/class/dmi/id/sys_vendor; then
        PROVIDER="aws"
        REGION=$(curl -s -m 2 http://169.254.169.254/latest/meta-data/placement/region)
    # 4. GCP 判断
    elif [ -f /sys/class/dmi/id/sys_vendor ] && grep -q "Google" /sys/class/dmi/id/sys_vendor; then
        PROVIDER="gcp"
        REGION=$(curl -s -m 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
    # 5. DigitalOcean 判断 (其 Metadata 接口特有路径)
    elif curl -s -m 2 http://169.254.169.254/metadata/v1/id > /dev/null 2>&1; then
        PROVIDER="digitalocean"
        REGION="global"
    else
        PROVIDER="vps"
        REGION="node"
    fi

    # 清理残留的 XML 或空格
    REGION=$(echo "$REGION" | tr -d '[:space:]' | tr -cd '[:alnum:]-')
    [ -z "$REGION" ] && REGION="node"
}

get_metadata

# --- 2. 城市名转换 ---
case $REGION in
    "ap-northeast-1"|"japaneast"|"asia-northeast1"|"ap-tokyo-1") CITY="tokyo" ;;
    "ap-southeast-1"|"southeastasia"|"asia-southeast1"|"ap-singapore-1") CITY="singapore" ;;
    "ap-east-1"|"hongkong"|"eastasia") CITY="hongkong" ;;
    "us-east-1"|"eastus") CITY="virginia" ;;
    *) CITY=${REGION} ;;
esac

# --- 3. 格式化名称 (双首字母大写 + 递增) ---
CAP_PROVIDER="${PROVIDER^}"
CAP_CITY="${CITY^}"
BASE_NAME="${CAP_PROVIDER}-${CAP_CITY}"

CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" =~ ${BASE_NAME}-([0-9]+) ]]; then
    OLD_NUM=$(echo $CURRENT_HOSTNAME | grep -oE '[0-9]+$' | tail -1)
    NEW_NUM=$(printf "%02d" $((10#$OLD_NUM + 1)))
else
    NEW_NUM="01"
fi

NEW_HOSTNAME="${BASE_NAME}-${NEW_NUM}"
hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/g" /etc/hosts

# --- 4. BBR & 防火墙 ---
echo "🚀 开启 BBR..."
sysctl -w net.core.default_qdisc=fq > /dev/null
sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null
echo "🛡️ 关闭防火墙..."
(command -v ufw >/dev/null && ufw disable) || (command -v firewalld >/dev/null && systemctl stop firewalld)
iptables -F

echo "-----------------------------------"
echo "🎉 修正完毕！当前主机名: $(hostname)"
