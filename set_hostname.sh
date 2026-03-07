#!/bin/bash

# ====================================================
# 脚本功能：自动识别云商（修复XML报错）、双首字母大写、递增编号、开BBR、关防火墙
# ====================================================

if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请使用 root 权限运行。"
  exit 1
fi

echo "✨ 正在启动全能运维脚本 V3.3 (Bug Fix)..."

# --- 1. 强力识别云商与 Region ---
get_metadata() {
    # 尝试判断是否为 Azure (通过 DMI 信息最准)
    if [ -f /sys/class/dmi/id/sys_vendor ] && grep -q "Microsoft" /sys/class/dmi/id/sys_vendor; then
        PROVIDER="azure"
        REGION=$(curl -s -m 2 -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
    # 尝试判断是否为 AWS
    elif [ -f /sys/class/dmi/id/sys_vendor ] && grep -q "Amazon" /sys/class/dmi/id/sys_vendor; then
        PROVIDER="aws"
        REGION=$(curl -s -m 2 http://169.254.169.254/latest/meta-data/placement/region)
    # 尝试判断是否为 GCP
    elif [ -f /sys/class/dmi/id/sys_vendor ] && grep -q "Google" /sys/class/dmi/id/sys_vendor; then
        PROVIDER="gcp"
        REGION=$(curl -s -m 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
    # 兜底探测 (Oracle/DigitalOcean/Vultr)
    else
        # 简单探测路径
        ORA_TEST=$(curl -s -m 2 -I http://192.0.0.192/1.0/meta-data/instance/region 2>/dev/null)
        if [ -n "$ORA_TEST" ]; then
            PROVIDER="oracle"
            REGION=$(curl -s -m 2 http://192.0.0.192/1.0/meta-data/instance/region)
        elif [ -f "/var/lib/cloud/data/instance-id" ]; then
            PROVIDER="digitalocean"; REGION="global"
        else
            PROVIDER="vps"; REGION="node"
        fi
    fi

    # 关键修复：如果 REGION 包含 XML 标签或报错，强制清理
    if [[ "$REGION" == *"<"* ]]; then
        REGION="unknown"
    fi
}

get_metadata

# --- 2. 城市名转换 ---
case $REGION in
    "ap-northeast-1"|"japaneast"|"asia-northeast1") CITY="tokyo" ;;
    "ap-southeast-1"|"southeastasia"|"asia-southeast1") CITY="singapore" ;;
    "ap-east-1"|"hongkong"|"eastasia") CITY="hongkong" ;;
    "us-east-1"|"eastus") CITY="virginia" ;;
    *) CITY=${REGION:-"node"} ;;
esac

# --- 3. 格式化名称 ---
CAP_PROVIDER="${PROVIDER^}"
CAP_CITY="${CITY^}"
BASE_NAME="${CAP_PROVIDER}-${CAP_CITY}"

# 自动递增逻辑
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" =~ ${BASE_NAME}-([0-9]+) ]]; then
    OLD_NUM=$(echo $CURRENT_HOSTNAME | grep -oE '[0-9]+$' | tail -1)
    NEW_NUM=$(printf "%02d" $((10#$OLD_NUM + 1)))
else
    NEW_NUM="01"
fi

NEW_HOSTNAME="${BASE_NAME}-${NEW_NUM}"

# 执行改名 (增加异常字符过滤)
NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | tr -d '[:space:]' | tr -cd '[:alnum:]-')
hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/g" /etc/hosts

# --- 4. BBR & 防火墙 (略) ---
echo "🚀 开启 BBR 加速..."
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf 2>/dev/null
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf 2>/dev/null
sysctl -p > /dev/null 2>&1
if command -v ufw >/dev/null 2>&1; then ufw disable >/dev/null; fi

echo "-----------------------------------"
echo "🎉 修复成功！新的主机名是: $(hostname)"
