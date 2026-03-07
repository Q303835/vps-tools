#!/bin/bash

# ====================================================
# 脚本功能：自动识别云商、改名（双首字母大写+递增）、开BBR、关防火墙
# ====================================================

if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请使用 root 权限运行。"
  exit 1
fi

echo "✨ 正在启动全能运维脚本 V3.2..."

# --- 1. 自动识别云商与 Region ---
get_metadata() {
    AWS_REG=$(curl -s -m 2 http://169.254.169.254/latest/meta-data/placement/region)
    AZ_REG=$(curl -s -m 2 -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
    GCP_REG=$(curl -s -m 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
    ORA_REG=$(curl -s -m 2 http://192.0.0.192/1.0/meta-data/instance/region)

    if [ -n "$AWS_REG" ]; then PROVIDER="aws"; REGION=$AWS_REG
    elif [ -n "$AZ_REG" ]; then PROVIDER="azure"; REGION=$AZ_REG
    elif [ -n "$GCP_REG" ]; then PROVIDER="gcp"; REGION=$GCP_REG
    elif [ -n "$ORA_REG" ]; then PROVIDER="oracle"; REGION=$ORA_REG
    elif grep -q "vultr" /etc/hostname 2>/dev/null; then PROVIDER="vultr"; REGION="global"
    elif [ -f "/var/lib/cloud/data/instance-id" ]; then PROVIDER="digitalocean"; REGION="global"
    else PROVIDER="vps"; REGION="unknown"
    fi
}

get_metadata

# --- 2. 城市名转换 ---
case $REGION in
    "ap-northeast-1"|"japaneast"|"asia-northeast1") CITY="tokyo" ;;
    "ap-southeast-1"|"southeastasia"|"asia-southeast1") CITY="singapore" ;;
    "ap-east-1"|"hongkong") CITY="hongkong" ;;
    "us-east-1"|"eastus") CITY="virginia" ;;
    *) CITY=${REGION:-"node"} ;;
esac

# --- 3. 双首字母大写与自动递增逻辑 ---
# 将服务商和城市名首字母均大写 (例如 aws -> Aws, tokyo -> Tokyo)
CAP_PROVIDER="${PROVIDER^}"
CAP_CITY="${CITY^}"
BASE_NAME="${CAP_PROVIDER}-${CAP_CITY}"

CURRENT_HOSTNAME=$(hostname)

# 正则匹配逻辑：支持旧版小写名识别并递增
if [[ "$CURRENT_HOSTNAME" =~ ^[Aa-z]+-[Aa-z]+-([0-9]+)$ ]]; then
    OLD_NUM=$(echo $CURRENT_HOSTNAME | grep -oE '[0-9]+$')
    NEW_NUM=$(printf "%02d" $((10#$OLD_NUM + 1)))
    echo "🔄 检测到同名节点，编号递增至 $NEW_NUM"
else
    NEW_NUM="01"
    echo "🆕 从 01 开始编号"
fi

NEW_HOSTNAME="${BASE_NAME}-${NEW_NUM}"

# 执行改名
hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/g" /etc/hosts
echo "✅ 主机名已更新为: $NEW_HOSTNAME"

# --- 4. 开启 BBR ---
echo "🚀 开启 BBR 加速..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; fi
if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; fi
sysctl -p > /dev/null

# --- 5. 关闭防火墙 ---
echo "🛡️ 关闭内部防火墙..."
if command -v ufw >/dev/null 2>&1; then ufw disable >/dev/null; elif command -v firewalld >/dev/null 2>&1; then systemctl stop firewalld && systemctl disable firewalld; fi
iptables -P INPUT ACCEPT && iptables -F

echo "-----------------------------------"
echo "🎉 所有运维任务执行完毕！新的主机名是: $NEW_HOSTNAME"
