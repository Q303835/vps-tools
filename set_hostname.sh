#!/bin/bash

# ====================================================
# 脚本功能：自动识别云商、改名、开BBR、关防火墙
# 适配：Ubuntu, Debian, CentOS, Rocky, AlmaLinux
# ====================================================

if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请使用 root 权限运行。"
  exit 1
fi

echo "✨ 正在启动全能运维脚本..."

# --- 1. 自动识别云商与 Region ---
echo "🔍 正在读取云厂商元数据..."

# 定义探测函数
get_metadata() {
    # AWS & OpenStack (Vultr/DO等)
    AWS_REG=$(curl -s -m 2 http://169.254.169.254/latest/meta-data/placement/region)
    # Azure
    AZ_REG=$(curl -s -m 2 -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
    # GCP
    GCP_REG=$(curl -s -m 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
    # Oracle
    ORA_REG=$(curl -s -m 2 http://192.0.0.192/1.0/meta-data/instance/region)

    if [ -n "$AWS_REG" ]; then PROVIDER="aws"; REGION=$AWS_REG
    elif [ -n "$AZ_REG" ]; then PROVIDER="azure"; REGION=$AZ_REG
    elif [ -n "$GCP_REG" ]; then PROVIDER="gcp"; REGION=$GCP_REG
    elif [ -n "$ORA_REG" ]; then PROVIDER="oracle"; REGION=$ORA_REG
    # 针对 Vultr 和 DigitalOcean 的启发式判断 (通过主机名或厂商特定文件)
    elif grep -q "vultr" /etc/hostname 2>/dev/null || [ -d "/usr/local/vultr" ]; then PROVIDER="vultr"; REGION="global"
    elif [ -f "/var/lib/cloud/data/instance-id" ] && curl -s -m 2 http://169.254.169.254/metadata/v1/id > /dev/null; then PROVIDER="digitalocean"; REGION="global"
    else PROVIDER="vps"; REGION="unknown"
    fi
}

get_metadata

# --- 2. 城市名转换 ---
case $REGION in
    "ap-northeast-1"|"japaneast"|"asia-northeast1"|"uk-tokyo-1") CITY="tokyo" ;;
    "ap-southeast-1"|"southeastasia"|"asia-southeast1"|"ap-singapore-1") CITY="singapore" ;;
    "ap-east-1"|"hongkong") CITY="hongkong" ;;
    "us-east-1"|"eastus") CITY="virginia" ;;
    "us-west-1"|"westus") CITY="california" ;;
    *) CITY=${REGION:-"node"} ;;
esac

# --- 3. 修改主机名 ---
# 自动生成编号 (基于当前目录下文件数或随机，这里默认 01)
INDEX="01"
NEW_HOSTNAME="${PROVIDER}-${CITY}-${INDEX}"
hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/g" /etc/hosts
echo "✅ 主机名已设为: $NEW_HOSTNAME"

# --- 4. 开启 BBR ---
echo "🚀 开启 BBR 加速..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; fi
if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; fi
sysctl -p > /dev/null

# --- 5. 关闭防火墙 ---
echo "🛡️ 关闭内部防火墙..."
if command -v ufw >/dev/null 2>&1; then ufw disable >/dev/null
elif command -v firewalld >/dev/null 2>&1; then systemctl stop firewalld && systemctl disable firewalld; fi
iptables -P INPUT ACCEPT && iptables -F
echo "✅ 运维任务全部完成！"