#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 权限运行此脚本 (sudo su)"
  exit 1
fi

echo "=========================================="
echo "    AWS Lightsail 流量动态监控一键脚本 v2.0"
echo "=========================================="

# 1. 自动安装/检查 vnstat 及计算工具
echo "🔄 正在安装/检查依赖工具..."
apt update -y && apt install vnstat bc -y
systemctl start vnstat
systemctl enable vnstat

# 2. 自动检测主网卡
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|docker|br-|veth' | head -n 1)
fi
echo "✅ 自动检测到当前主网卡为: ${INTERFACE}"

# 3. 交互式输入 Gotify 配置
echo "------------------------------------------"
read -p "请输入 Gotify 网站地址 (例如 https://gotify.xxx.com): " GOTIFY_URL
GOTIFY_URL=${GOTIFY_URL%/} # 去掉末尾的斜杠

read -p "请输入 Gotify App Token: " GOTIFY_TOKEN
read -p "请输入该服务器每月套餐总量 (单位 GB, 默认 2048): " TOTAL_LIMIT_GB
TOTAL_LIMIT_GB=${TOTAL_LIMIT_GB:-2048}

# 4. 流量计算模式选择（单向 vs 动态双向）
echo "------------------------------------------"
echo "请选择该服务器的流量计费模式:"
echo "  1) 单向流量计费 (只计算出网/Tx流量，适合常规按量VPS)"
echo "  2) 动态双向计费 (入网+出网=总流量，适合 AWS Lightsail 共享池)"
read -p "请输入数字选项 (1 或 2, 默认 2): " TRAFFIC_MODE
TRAFFIC_MODE=${TRAFFIC_MODE:-2}

if [ "$TRAFFIC_MODE" -eq 2 ]; then
    MODE_NAME="双向动态计费 (In+Out)"
else
    MODE_NAME="单向计费 (仅Out)"
fi
echo "------------------------------------------"

# 定义最终生成的监控脚本路径
TARGET_SCRIPT="/root/traffic_monitor_${INTERFACE}.sh"

# 5. 动态生成监控脚本
echo "📝 正在生成监控脚本: ${TARGET_SCRIPT}"

cat << 'EOF' > "${TARGET_SCRIPT}"
#!/bin/bash

# ================= 配置区域 =================
GOTIFY_URL="REPLACE_URL"
GOTIFY_TOKEN="REPLACE_TOKEN"
TOTAL_LIMIT_GB=REPLACE_LIMIT
INTERFACE="REPLACE_INTERFACE"
MODE=REPLACE_MODE # 1为单向，2为双向
# ============================================

CURRENT_MONTH=$(date +%Y-%m)

# 跨月自动重置状态（一键清空该网卡所有的临时状态文件）
if [ -f "/tmp/traffic_notified_${INTERFACE}_50.txt" ]; then
    [[ "$(cat /tmp/traffic_notified_${INTERFACE}_50.txt)" != "$CURRENT_MONTH" ]] && rm -f /tmp/traffic_notified_${INTERFACE}_*.txt
fi

# 获取 vnstat 本月流量 JSON 数据
JSON_DATA=$(vnstat -i $INTERFACE --json m)

# 提取入站(rx)和出站(tx) —— 【已修正为 tail -n 1 精准抓取本月】
RX_KIB=$(echo "$JSON_DATA" | grep -oP '"rx":\s*\K[0-9]+' | tail -n 1)
TX_KIB=$(echo "$JSON_DATA" | grep -oP '"tx":\s*\K[0-9]+' | tail -n 1)

if [ -z "$RX_KIB" ]; then RX_KIB=0; fi
if [ -z "$TX_KIB" ]; then TX_KIB=0; fi

# 根据用户选择的模式计算「已用流量」
if [ "$MODE" -eq 2 ]; then
    # 双向动态求和 (Rx + Tx)
    USED_KIB=$(echo "$RX_KIB + $TX_KIB" | bc)
    MODE_TEXT="双向总和(入站+出站)"
else
    # 单向仅出站 (Tx)
    USED_KIB=$TX_KIB
    MODE_TEXT="单向纯出站"
fi

# 单位转换与计算
USED_GB=$(echo "scale=2; $USED_KIB / 1024 / 1024" | bc)
RX_GB=$(echo "scale=2; $RX_KIB / 1024 / 1024" | bc)
TX_GB=$(echo "scale=2; $TX_KIB / 1024 / 1024" | bc)

REMAIN_GB=$(echo "scale=2; $TOTAL_LIMIT_GB - $USED_GB" | bc)
PERCENTAGE=$(echo "scale=0; ($USED_GB * 100) / $TOTAL_LIMIT_GB" | bc)

if [ -z "$PERCENTAGE" ]; then PERCENTAGE=0; fi

# 获取当前主机名
HOSTNAME=$(hostname)

NOTIFICATION_TITLE="⚠️ 流量预警: ${HOSTNAME} (${INTERFACE})"
NOTIFICATION_MSG="流量计算模式：${MODE_TEXT}
📊 套餐总量：${TOTAL_LIMIT_GB} GB
📥 本月入站(Rx)：${RX_GB} GB
📤 本月出站(Tx)：${TX_GB} GB
📈 已用总计：${USED_GB} GB (${PERCENTAGE}%)
📉 剩余可用：${REMAIN_GB} GB"

send_gotify() {
    curl -s -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
        -F "title=${NOTIFICATION_TITLE}" \
        -F "message=${NOTIFICATION_MSG}" \
        -F "priority=5"
}

# ================= 逻辑触发区域（包含新增多档位） =================

# 1. 达到 96% 触发
if [ "$PERCENTAGE" -ge 96 ]; then
    STATUS_FILE_96="/tmp/traffic_notified_${INTERFACE}_96.txt"
    if [ ! -f "$STATUS_FILE_96" ]; then
        send_gotify
        echo "$CURRENT_MONTH" > "$STATUS_FILE_96"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_90.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_85.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_80.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_70.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_50.txt"
    fi

# 2. 达到 90% 触发
elif [ "$PERCENTAGE" -ge 90 ]; then
    STATUS_FILE_90="/tmp/traffic_notified_${INTERFACE}_90.txt"
    if [ ! -f "$STATUS_FILE_90" ]; then
        send_gotify
        echo "$CURRENT_MONTH" > "$STATUS_FILE_90"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_85.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_80.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_70.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_50.txt"
    fi

# 3. 达到 85% 触发
elif [ "$PERCENTAGE" -ge 85 ]; then
    STATUS_FILE_85="/tmp/traffic_notified_${INTERFACE}_85.txt"
    if [ ! -f "$STATUS_FILE_85" ]; then
        send_gotify
        echo "$CURRENT_MONTH" > "$STATUS_FILE_85"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_80.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_70.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_50.txt"
    fi

# 4. 达到 80% 触发
elif [ "$PERCENTAGE" -ge 80 ]; then
    STATUS_FILE_80="/tmp/traffic_notified_${INTERFACE}_80.txt"
    if [ ! -f "$STATUS_FILE_80" ]; then
        send_gotify
        echo "$CURRENT_MONTH" > "$STATUS_FILE_80"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_70.txt"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_50.txt"
    fi

# 5. 达到 70% 触发
elif [ "$PERCENTAGE" -ge 70 ]; then
    STATUS_FILE_70="/tmp/traffic_notified_${INTERFACE}_70.txt"
    if [ ! -f "$STATUS_FILE_70" ]; then
        send_gotify
        echo "$CURRENT_MONTH" > "$STATUS_FILE_70"
        echo "$CURRENT_MONTH" > "/tmp/traffic_notified_${INTERFACE}_50.txt"
    fi

# 6. 达到 50% 触发
elif [ "$PERCENTAGE" -ge 50 ]; then
    STATUS_FILE_50="/tmp/traffic_notified_${INTERFACE}_50.txt"
    if [ ! -f "$STATUS_FILE_50" ]; then
        send_gotify
        echo "$CURRENT_MONTH" > "$STATUS_FILE_50"
    fi
fi
EOF

# 替换动态变量
sed -i "s|REPLACE_URL|${GOTIFY_URL}|g" "${TARGET_SCRIPT}"
sed -i "s|REPLACE_TOKEN|${GOTIFY_TOKEN}|g" "${TARGET_SCRIPT}"
sed -i "s|REPLACE_LIMIT|${TOTAL_LIMIT_GB}|g" "${TARGET_SCRIPT}"
sed -i "s|REPLACE_INTERFACE|${INTERFACE}|g" "${TARGET_SCRIPT}"
sed -i "s|REPLACE_MODE|${TRAFFIC_MODE}|g" "${TARGET_SCRIPT}"

# 赋予执行权限
chmod +x "${TARGET_SCRIPT}"

# 6. 自动写入 crontab 定时任务
echo "⏰ 正在配置 crontab 每小时自动检查..."
CRON_JOB="0 * * * * /bin/bash ${TARGET_SCRIPT}"
(crontab -l 2>/dev/null | grep -F "${TARGET_SCRIPT}") || (crontab -l 2>/dev/null; echo "${CRON_JOB}") | crontab -

echo "=========================================="
echo " 🎉 配置成功！"
echo " 监控模式: ${MODE_NAME}"
echo " 监控脚本: ${TARGET_SCRIPT}"
echo " 现在脚本会动态累加入站和出站流量，并支持 50/70/80/85/90/96% 阶梯式预警！"
echo "=========================================="
