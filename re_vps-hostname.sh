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

# 3. 提取国家代码 (例如 DE, US, HK 等)
COUNTRY=$(echo "$JSON_DATA" | jq -r '.countryCode')

# 4. 提取并格式化城市 (去除所有空格，转为小写)
CITY=$(echo "$JSON_DATA" | jq -r '.city' | tr -d ' ' | tr '[:upper:]' '[:lower:]')

# --- 常用 VPS 主机城市/数据中心映射规则 ---
case "$CITY" in
    # 欧洲地区
    "frankfurtammain") CITY="frankfurt" ;;
    "eemshaven") CITY="netherlands" ;; 
    "stghislain") CITY="belgium" ;;    
    "hamina") CITY="finland" ;;        
    "amsterdam") CITY="ams" ;;
    "london") CITY="lon" ;;
    
    # 亚太地区
    "hongkong") CITY="hk" ;;
    "singapore") CITY="sg" ;;
    "chuncheon") CITY="chuncheon" ;;
    "sydney") CITY="syd" ;;

    # 美洲地区 
    "thedalles"|"boardman"|"umatilla") CITY="oregon" ;;      
    "ashburn"|"boydton") CITY="virginia" ;;                  
    "councilbluffs"|"desmoines") CITY="iowa" ;;              
    "monckscorner") CITY="southcarolina" ;;                  
    "quincy") CITY="washington" ;;                           
    "sanantonio") CITY="texas" ;;                            
    "losangeles") CITY="la" ;;
    "sanjose"|"santaclara") CITY="sanjose" ;;
    "newyork"|"newyorkcity") CITY="ny" ;;
esac
# ---------------------------------

# 5. 自动识别 CPU 架构
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    SYS_ARCH="ARM"
elif [ "$ARCH" = "x86_64" ]; then
    SYS_ARCH="AMD"
else
    SYS_ARCH="$ARCH"
fi

# 6. 拼接带国家代码的基础主机名 (例如: Oracle-DE-frankfurt-ARM)
BASE_HOSTNAME="${PROVIDER}-${COUNTRY}-${CITY}-${SYS_ARCH}"

# 7. 交互式确认编号
echo "------------------------------------------"
read -p "当前基础主机名为 [ ${BASE_HOSTNAME} ]。请输入机器编号 (例如输入 2 会变成 ${BASE_HOSTNAME}-2，不加编号请直接回车): " SUFFIX

if [ -n "$SUFFIX" ]; then
    NEW_HOSTNAME="${BASE_HOSTNAME}-${SUFFIX}"
else
    NEW_HOSTNAME="${BASE_HOSTNAME}"
fi

# 8. 设置新主机名
hostnamectl set-hostname "$NEW_HOSTNAME"

# 9. 更新 /etc/hosts 文件，防止 sudo 报错
sed -i "s/127.0.1.1.*/127.0.1.1\t$NEW_HOSTNAME/g" /etc/hosts

echo "=========================================="
echo "重命名成功！新的主机名为: $NEW_HOSTNAME"
echo "请断开 SSH 并重新连接，或者输入 'bash' 即可看到变化。"
echo "=========================================="
