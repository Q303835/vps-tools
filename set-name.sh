#!/bin/bash

# ====================================================
# 脚本功能：自动/手动识别云商、双首字母大写、递增编号、全能运维
# ====================================================

if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请使用 root 权限运行。"
  exit 1
fi

echo "✨ 正在启动全能运维脚本 V4.0..."

# --- 1. 识别云商逻辑 ---
get_metadata() {
    # 尝试自动识别
    if [[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" == *"Oracle"* ]]; then PROVIDER="oracle"
    elif [[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" == *"Amazon"* ]]; then PROVIDER="aws"
    elif [[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" == *"Microsoft"* ]]; then PROVIDER="azure"
    elif [[ "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" == *"Google"* ]]; then PROVIDER="gcp"
    fi

    # 如果自动识别失败，改为手动选择
    if [ -z "$PROVIDER" ] || [ "$PROVIDER" == "vps" ]; then
        echo "🤔 自动识别失败，请手动选择服务商:"
        PS3='请选择 (输入数字): '
        options=("Oracle" "AWS" "Azure" "GCP" "DigitalOcean" "Vultr" "其他")
        select opt in "${options[@]}"; do
            case $opt in
                "Oracle") PROVIDER="oracle"; break;;
                "AWS") PROVIDER="aws"; break;;
                "Azure") PROVIDER="azure"; break;;
                "GCP") PROVIDER="gcp"; break;;
                "DigitalOcean") PROVIDER="digitalocean"; break;;
                "Vultr") PROVIDER="vultr"; break;;
                *) PROVIDER="vps"; break;;
            esac
        done
    fi
}

get_metadata

# --- 2. 获取地区 (如果自动拿不到，就默认使用 Tokyo) ---
echo "🔍 正在获取 Region..."
if [ "$PROVIDER" == "oracle" ]; then
    REGION=$(curl -s -m 2 http://192.0.0.192/1.0/meta-data/instance/region)
elif [ "$PROVIDER" == "aws" ]; then
    REGION=$(curl -s -m 2 http://169.254.169.254/latest/meta-data/placement/region)
fi

# 兜底：如果没拿到 Region，默认设为 Tokyo (你最常用的)
[ -z "$REGION" ] && REGION="tokyo"

# 城市名转换
case $REGION in
    "ap-northeast-1"|"japaneast"|"ap-tokyo-1"|"tokyo") CITY="Tokyo" ;;
    "ap-southeast-1"|"singapore") CITY="Singapore" ;;
    "ap-east-1"|"hongkong") CITY="Hongkong" ;;
    *) CITY="${REGION^}" ;;
esac

# --- 3. 命名与递增 ---
CAP_PROVIDER="${PROVIDER^}"
BASE_NAME="${CAP_PROVIDER}-${CITY}"

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

# --- 4. 开启 BBR & 5. 关闭防火墙 ---
sysctl -w net.core.default_qdisc=fq > /dev/null 2>&1
sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
sysctl -p > /dev/null 2>&1
(command -v ufw >/dev/null && ufw disable) || (command -v firewalld >/dev/null && systemctl stop firewalld)
iptables -F

echo "-----------------------------------"
echo "✅ 搞定！主机名已更新为: $(hostname)"
