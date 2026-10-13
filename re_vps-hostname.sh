#!/bin/bash

# 更新并安装 curl 和 jq
apt update
apt install curl jq -y

# 1. 获取 JSON 数据
JSON_DATA=$(curl -s http://ip-api.com/json/)

# 2. 提取并格式化 ISP
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
elif echo "$ISP_LOWER" | grep -q "linode\|akamai"; then
    PROVIDER="Linode"
elif echo "$ISP_LOWER" | grep -q "vultr\|choopa"; then
    PROVIDER="Vultr"
else
    PROVIDER=$(echo "$ISP" | awk '{print $1}' | tr -d ',.:;"')
fi

# 3. 提取并格式化城市 (去除所有空格，转为小写)
CITY=$(echo "$JSON_DATA" | jq -r '.city' | tr -d ' ' | tr '[:upper:]' '[:lower:]')

# --- 新增：常用 VPS 主机城市/数据中心映射规则 ---
case "$CITY" in
    # 欧洲地区
    "frankfurtammain") CITY="frankfurt" ;;
    "eemshaven") CITY="netherlands" ;; # GCP 荷兰
    "stghislain") CITY="belgium" ;;    # GCP 比利时
    "hamina") CITY="finland" ;;        # GCP 芬兰
    "amsterdam") CITY="ams" ;;
    "london") CITY="lon" ;;
    
    # 亚太地区
    "hongkong") CITY="HK" ;;
    "singapore") CITY="SG" ;;
    "chuncheon") CITY="Chuncheon" ;;   # 甲骨文 韩国春川
    "sydney") CITY="syd" ;;

    # 美洲地区 (包含各大厂偏僻数据中心小镇)
    "thedalles"|"boardman"|"umatilla") CITY="oregon" ;;      # 俄勒冈 (GCP/AWS)
    "ashburn"|"boydton") CITY="virginia" ;;                  # 弗吉尼亚 (AWS/Azure)
    "councilbluffs"|"desmoines") CITY="iowa" ;;              # 爱荷华 (GCP/Azure)
    "monckscorner") CITY="southcarolina" ;;                  # 南卡罗来纳 (GCP)
    "quincy") CITY="washington" ;;                           # 华盛顿州 (Azure)
    "sanantonio") CITY="texas" ;;                            # 德州 (Azure)
    "losangeles") CITY="la" ;;
    "sanjose"|"santaclara") CITY="sanjose" ;;
    "newyork"|"newyorkcity") CITY="ny" ;;
esac
# ---------------------------------

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
