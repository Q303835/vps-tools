#!/bin/bash

# ====================================================
# 脚本功能：云商识别、双首字母大写、递增编号、交互式确认编辑
# 适配：Ubuntu, Debian, CentOS, Rocky, AlmaLinux
# ====================================================

if [ "$EUID" -ne 0 ]; then 
  echo "❌ 请使用 root 权限运行。"
  exit 1
fi

echo "✨ 正在启动全能运维脚本 V5.0 (Interactive Edition)..."

# --- 1. 云商识别逻辑 ---
get_metadata() {
    # 尝试自动识别硬件
    SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    if [[ "$SYS_VENDOR" == *"Oracle"* ]]; then PROVIDER="oracle"
    elif [[ "$SYS_VENDOR" == *"Amazon"* ]]; then PROVIDER="aws"
    elif [[ "$SYS_VENDOR" == *"Microsoft"* ]]; then PROVIDER="azure"
    elif [[ "$SYS_VENDOR" == *"Google"* ]]; then PROVIDER="gcp"
    fi

    # 如果自动识别失败，改为手动选择
    if [ -z "$PROVIDER" ]; then
        echo "🤔 自动识别云商失败，请手动选择:"
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

# --- 2. 获取地区与城市 ---
if [ "$PROVIDER" == "oracle" ]; then
    REGION=$(curl -s -m 2 http://192.0.0.192/1.0/meta-data/instance/region)
elif [ "$PROVIDER" == "aws" ]; then
    REGION=$(curl -s -m 2 http://169.254.169.254/latest/meta-data/placement/region)
elif [ "$PROVIDER" == "azure" ]; then
    REGION=$(curl -s -m 2 -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")
fi

# 转换城市名 (加了常见的 Oracle 日本代码映射)
case $REGION in
    "ap-northeast-1"|"japaneast"|"ap-tokyo-1") CITY="Tokyo" ;;
    "ap-southeast-1"|"southeastasia"|"ap-singapore-1") CITY="Singapore" ;;
    "ap-east-1"|"hongkong"|"eastasia") CITY="Hongkong" ;;
    *) [ -n "$REGION" ] && CITY="${REGION^}" || CITY="Node" ;;
esac

# --- 3. 生成拟定名称并进入交互模式 ---
CAP_PROVIDER="${PROVIDER^}"
BASE_NAME="${CAP_PROVIDER}-${CITY}"

# 检测递增编号
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" =~ ${BASE_NAME}-([0-9]+) ]]; then
    OLD_NUM=$(echo $CURRENT_HOSTNAME | grep -oE '[0-9]+$' | tail -1)
    NEW_NUM=$(printf "%02d" $((10#$OLD_NUM + 1)))
else
    NEW_NUM="01"
fi

SUGGESTED_NAME="${BASE_NAME}-${NEW_NUM}"

# 核心：人工确认环节
echo "-----------------------------------"
echo "📢 脚本建议的主机名为: $SUGGESTED_NAME"
read -p "满意请按 [回车] 直接设置，如需修改请输入新名称: " USER_INPUT

if [ -n "$USER_INPUT" ]; then
    FINAL_NAME="$USER_INPUT"
else
    FINAL_NAME="$SUGGESTED_NAME"
fi

# 执行设置
hostnamectl set-hostname "$FINAL_NAME"
sed -i "s/127.0.1.1.*/127.0.1.1 $FINAL_NAME/g" /etc/hosts

# --- 4. 开启 BBR & 5. 关闭防火墙 ---
echo "🚀 正在优化网络并关闭防火墙..."
sysctl -w net.core.default_qdisc=fq > /dev/null 2>&1
sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
(command -v ufw >/dev/null && ufw disable) || (command -v firewalld >/dev/null && systemctl stop firewalld)
iptables -F

echo "-----------------------------------"
echo "🎉 任务完成！当前主机名已设为: $(hostname)"
