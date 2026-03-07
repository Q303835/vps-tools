#!/bin/bash

# ====================================================
# 脚本功能：自动识别云商（DMI硬件识别）、双首字母大写、递增编号、全能运维
# ====================================================

if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请使用 root 权限运行。"
  exit 1
fi

echo "✨ 正在启动全能运维脚本 V3.5 (Ultimate Precision)..."

# --- 1. 硬件级识别云商与 Region ---
get_metadata() {
    # 读取系统厂商信息（这是最稳的识别方式）
    SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    BIOS_VENDOR=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null)
    
    # 1. Oracle 识别 (硬件标志: Oracle Cloud)
    if [[ "$SYS_VENDOR" == *"Oracle"* ]] || [[ "$BIOS_VENDOR" == *"Oracle"* ]]; then
        PROVIDER="oracle"
        REGION=$(curl -s -m 2 http://192.0.0.192/1.0/meta-data/instance/region)
    # 2. AWS 识别
    elif [[ "$SYS_VENDOR" == *"Amazon"* ]]; then
        PROVIDER="aws"
        REGION=$(curl -s -m 2 http://169.254.169.254/latest/meta-data/placement/region)
    # 3. Azure 识别
    elif [[ "$SYS_VENDOR" == *"Microsoft"* ]]; then
        PROVIDER="azure"
        REGION=$(curl -s -m 2 -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
    # 4. Google 识别
    elif [[ "$SYS_VENDOR" == *"Google"* ]]; then
        PROVIDER="gcp"
        REGION=$(curl -s -m 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
    # 5. DigitalOcean 识别
    elif [[ "$SYS_VENDOR" == *"DigitalOcean"* ]]; then
        PROVIDER="digitalocean"
        REGION="global"
    else
        PROVIDER="vps"
        REGION="node"
    fi

    # 清理非字符内容
    REGION=$(echo "$REGION" | tr -d '[:space:]' | tr -cd '[:alnum:]-')
    [ -z "$REGION" ] && REGION="node"
}

get_metadata

# --- 2. 城市名转换 ---
case $REGION in
    "ap-northeast-1"|"japaneast"|"asia-northeast1"|"ap-tokyo-1") CITY="tokyo" ;;
    "ap-southeast-1"|"southeastasia"|"asia-southeast1"|"ap-singapore-1") CITY="singapore" ;;
    "ap-east-1"|"hongkong"|"eastasia") CITY="hongkong" ;;
    *) CITY=${REGION} ;;
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
hostnamectl set-hostname "$NEW_HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/g" /etc/hosts

# --- 4. BBR & 防火墙 ---
echo "🚀 开启 BBR 加速..."
sysctl -w net.core.default_qdisc=fq > /dev/null
sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null
echo "🛡️ 关闭防火墙..."
(command -v ufw >/dev/null && ufw disable) || (command -v firewalld >/dev/null && systemctl stop firewalld)
iptables -F

echo "-----------------------------------"
echo "🎉 终极修复完成！当前主机名: $(hostname)"
