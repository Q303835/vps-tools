#!/bin/bash

# 更新并安装 curl 和 jq
apt update
apt install curl jq -y

# 1. 获取 JSON 数据
JSON_DATA=$(curl -s http://ip-api.com/json/)

# 2. 提取并格式化 ISP (增加多服务商识别)
ISP=$(echo "$JSON_DATA" | jq -r '.isp')
ISP_LOWER=$(echo "$ISP" | tr '[:upper:]' '[:lower:]')

if echo "$ISP_LOWER" | grep -q "oracle"; then
    PROVIDER="Oracle"
elif echo "$ISP_LOWER" | grep -q "amazon"; then
    PROVIDER="AWS"
elif echo "$ISP_LOWER" | grep -q "microsoft\|azure"; then
    PROVIDER="Azure"
elif echo "$ISP_LOWER" | grep -q "google"; then
    PROVIDER="GCP"
elif echo "$ISP_LOWER" | grep -q "digitalocean"; then
    PROVIDER="DO"
else
    # 其他不常见的服务商，取第一个词，并删除末尾可能出现的逗号或句号
    PROVIDER=$(echo "$ISP" | awk '{print $1}' | tr -d ',.:;"')
fi

# 3. 提取并格式化城市
CITY=$(echo "$JSON_DATA" | jq -r '.city' | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

# 4. 自动识别 CPU 架构
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    SYS_ARCH="ARM"
elif [ "$ARCH" = "x86_64" ]; then
    SYS_ARCH="AMD"
else
    SYS_ARCH="$ARCH"
fi

# 5. 拼接基础主机名
BASE_HOSTNAME="${PROVIDER}-${CITY}-${SYS_ARCH}"

# 6. 交互式确认编号
echo "------------------------------------------"
read -p "当前基础主机名为 [ ${BASE_HOSTNAME} ]。请输入机器编号 (例如输入 2 会变成 ${BASE_HOSTNAME}-2，不加编号请直接回车): " SUFFIX

if [ -n "$SUFFIX" ]; then
    NEW_HOSTNAME="${BASE_HOSTNAME}-${SUFFIX}"
else
    NEW_HOSTNAME="${BASE_HOSTNAME}"
fi

# 7. 设置新主机名
hostnamectl set-hostname "$NEW_HOSTNAME"

# 8. 更新 /etc/hosts 文件，防止 sudo 报错
sed -i "s/127.0.1.1.*/127.0.1.1\t$NEW_HOSTNAME/g" /etc/hosts

echo "=========================================="
echo "重命名成功！新的主机名为: $NEW_HOSTNAME"
echo "请断开 SSH 并重新连接，或者输入 'bash' 即可看到变化。"
echo "=========================================="