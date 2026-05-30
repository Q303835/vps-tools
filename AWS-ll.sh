#!/bin/bash

# ==================== 配置区 ====================
SPEED="50kbps"
BASELINE_FILE="/var/lib/traffic_baseline"
GOTIFY_CONFIG_FILE="/etc/gotify_config.conf"

# ==================== 自动获取活动网卡 ====================
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ls /sys/class/net/ | grep -v "lo" | head -n1)
fi

if [ -z "$INTERFACE" ]; then
    echo "❌ 错误：未找到有效的网络接口！"
    exit 1
fi

# ==================== 交互式输入与历史记忆 ====================
echo "=================================================="
echo "-> 🔍 成功自动识别网卡: ${INTERFACE}"

# 1. 输入总流量
read -p "请输入您当前 Lightsail 的套餐总流量 (如: 1, 2, 3 表示 TB; 或 1024, 2048 表示 GB): " USER_INPUT
if [ $USER_INPUT -le 10 ]; then
    TOTAL_QUOTA_GB=$((USER_INPUT * 1024))
else
    TOTAL_QUOTA_GB=$USER_INPUT
fi
LIMIT_GB=$((TOTAL_QUOTA_GB * 90 / 100))

# 2. 读取历史 Gotify 配置
if [ -f "$GOTIFY_CONFIG_FILE" ]; then
    source "$GOTIFY_CONFIG_FILE"
fi

echo "--------------------------------------------------"
echo "🔔 开始配置 Gotify 通知 (如果不需要推送，直接连续回车跳过)"

# 输入 Gotify URL
if [ -n "$OLD_GOTIFY_URL" ]; then
    read -p "请输入 Gotify 域名/IP (当前默认: $OLD_GOTIFY_URL): " INPUT_URL
    GOTIFY_URL=${INPUT_URL:-$OLD_GOTIFY_URL}
else
    read -p "请输入 Gotify 域名/IP (例如 https://gotify.abc.com): " GOTIFY_URL
fi

# 输入 Gotify Token
if [ -n "$OLD_GOTIFY_TOKEN" ]; then
    read -p "请输入 Gotify App Token (当前默认: [已隐藏长Token]): " INPUT_TOKEN
    GOTIFY_TOKEN=${INPUT_TOKEN:-$OLD_GOTIFY_TOKEN}
else
    read -p "请输入 Gotify App Token: " GOTIFY_TOKEN
fi

# 如果用户输入了配置，则保存供下次使用
if [[ -n "$GOTIFY_URL" && -n "$GOTIFY_TOKEN" ]]; then
    # 去除 URL 末尾可能误输入的 /
    GOTIFY_URL=${GOTIFY_URL%/}
    mkdir -p "$(dirname "$GOTIFY_CONFIG_FILE")"
    cat > "$GOTIFY_CONFIG_FILE" << EOF
OLD_GOTIFY_URL="${GOTIFY_URL}"
OLD_GOTIFY_TOKEN="${GOTIFY_TOKEN}"
EOF
    echo "-> ✨ Gotify 推送配置已成功保存！下次运行可直接回车跳过。"
else
    echo "-> ⚠️ 未检测到完整的 Gotify 配置，本次运行将不发送推送通知。"
fi

echo "--------------------------------------------------"
echo "-> 已设置总配额: ${TOTAL_QUOTA_GB} GB"
echo "-> 已自动设置限速阈值 (90%): ${LIMIT_GB} GB"
echo "=================================================="

# ==================== Gotify 发送函数 ====================
send_gotify_notification() {
    local title="$1"
    local message="$2"
    local priority="$3"

    # 没配置或者留空则跳过
    if [[ -z "$GOTIFY_URL" || -z "$GOTIFY_TOKEN" ]]; then
        return 0
    fi

    curl -s -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
        -F "title=${title}" \
        -F "message=${message}" \
        -F "priority=${priority}" > /dev/null
}

# ==================== 核心逻辑 ====================
get_current_usage() {
    local line=$(grep "$INTERFACE" /proc/net/dev)
    local rx=$(echo $line | awk '{print $2}')
    local tx=$(echo $line | awk '{print $10}')
    RX_BYTES=$rx
    TX_BYTES=$tx
    RX_GB=$((rx / 1024 / 1024 / 1024))
    TX_GB=$((tx / 1024 / 1024 / 1024))
}

get_current_month() {
    date +%Y-%m
}

read_baseline() {
    if [ -f "$BASELINE_FILE" ]; then
        BASELINE_MONTH=$(head -1 $BASELINE_FILE)
        BASELINE_RX=$(sed -n '2p' $BASELINE_FILE)
        BASELINE_TX=$(sed -n '3p' $BASELINE_FILE)
    else
        BASELINE_MONTH=""
        BASELINE_RX=0
        BASELINE_TX=0
    fi
}

save_baseline() {
    mkdir -p /var/lib
    cat > $BASELINE_FILE << EOF
$(get_current_month)
$RX_GB
$TX_GB
$RX_BYTES
$TX_BYTES
EOF
}

get_current_usage
read_baseline
CURRENT_MONTH=$(get_current_month)

if [ "$CURRENT_MONTH" != "$BASELINE_MONTH" ]; then
    save_baseline
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║  📅 检测到新月份 ($CURRENT_MONTH)，已自动重置基准值                    ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    send_gotify_notification "📅 流量统计重置" "检测到新月份 ($CURRENT_MONTH)，流量基准已自动重置。" 5
    read_baseline
fi

MONTH_RX=$((RX_GB - BASELINE_RX))
MONTH_TX=$((TX_GB - BASELINE_TX))
MONTH_TOTAL=$((MONTH_RX + MONTH_TX))

MONTH_REMAINING=$((TOTAL_QUOTA_GB - MONTH_TOTAL))
if [ $MONTH_REMAINING -lt 0 ]; then MONTH_REMAINING=0; fi

PERCENT=$((MONTH_TOTAL * 100 / TOTAL_QUOTA_GB))
if [ $PERCENT -gt 100 ]; then PERCENT=100; fi

BAR_LEN=45
FILLED=$((PERCENT * BAR_LEN / 100))
EMPTY=$((BAR_LEN - FILLED))
BAR=$(printf "%${FILLED}s" | tr ' ' '█')$(printf "%${EMPTY}s" | tr ' ' '░')

LIMIT_STATUS="正常"
if tc qdisc show dev $INTERFACE 2>/dev/null | grep -q "tbf"; then
    LIMIT_STATUS="已限速 ${SPEED}"
fi

if [ $PERCENT -ge 90 ]; then
    ALERT="🔴 红色预警 (已用 >90%)"
    send_gotify_notification "⚠️ 流量极其危险" "服务器流量已使用 ${PERCENT}% (${MONTH_TOTAL} GB / ${TOTAL_QUOTA_GB} GB)，即将耗尽！" 8
elif [ $PERCENT -ge 80 ]; then
    ALERT="🟠 橙色预警 (已用 >80%)"
    send_gotify_notification "⚠️ 流量紧张预警" "服务器流量已使用 ${PERCENT}% (${MONTH_TOTAL} GB)。" 6
elif [ $PERCENT -ge 60 ]; then
    ALERT="🟡 黄色预警 (已用 >60%)"
else
    ALERT="🟢 正常"
fi

# ========== 输出报告 ==========
echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                     📊 AWS Lightsail 流量监控报告                 ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"
echo "║  📅 时间: $(date '+%Y-%m-%d %H:%M:%S')                             ║"
echo "║  🖥️  服务器: $(hostname)                                           ║"
echo "║  🌐 网卡: $(printf '%-16s' "$INTERFACE")                                  ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"
echo "║                         📦 本月流量用量                           ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"
echo "║                                                                   ║"
echo "║    📥 入站 (下载):  $(printf '%-8s' "${MONTH_RX} GB")                 计费(双向)  ║"
echo "║    📤 出站 (上传):  $(printf '%-8s' "${MONTH_TX} GB")                 计费(双向)  ║"
echo "║    ─────────────────────────────────────────────────────          ║"
echo "║    📊 本月总计:     $(printf '%-8s' "${MONTH_TOTAL} GB")                 双向计费    ║"
echo "║                                                                   ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"
echo "║                         📈 配额使用情况                           ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"
echo "║                                                                   ║"
echo "║    总配额:  $(printf '%-8s' "${TOTAL_QUOTA_GB} GB")                                      ║"
echo "║    已使用:  $(printf '%-8s' "${MONTH_TOTAL} GB")                                      ║"
echo "║    剩  余:  $(printf '%-8s' "${MONTH_REMAINING} GB")                                      ║"
echo "║                                                                   ║"
echo "║    [${BAR}] ${PERCENT}%"
echo "║                                                                   ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"
echo "║                         ⚠️  预警与状态                             ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"
echo "║                                                                   ║"
echo "║    当前状态:  $ALERT                                            ║"
echo "║    限速状态:  $LIMIT_STATUS                                       ║"
echo "║    限速阈值:  ${LIMIT_GB} GB (触发后限速至 ${SPEED})                   ║"
echo "║                                                                   ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"
echo "║                         💡 累计数据 (自开机)                      ║"
echo "╠═══════════════════════════════════════════════════════════════════╣"
echo "║                                                                   ║"
echo "║    📥 总入站:  $(printf '%-10s' "${RX_GB} GB")                                      ║"
echo "║    📤 总出站:  $(printf '%-10s' "${TX_GB} GB")                                      ║"
echo "║                                                                   ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"

# ==================== 限速控制 ====================
if [ $MONTH_TOTAL -ge $LIMIT_GB ]; then
    if ! tc qdisc show dev $INTERFACE 2>/dev/null | grep -q "tbf"; then
        tc qdisc add dev $INTERFACE root tbf rate $SPEED burst 32kbit latency 400ms
        echo ""
        echo "╔═══════════════════════════════════════════════════════════════════╗"
        echo "║  🔴 已触发限速！双向总流量 ${MONTH_TOTAL}GB 超过阈值 ${LIMIT_GB}GB             ║"
        echo "║  🚫 当前限速: ${SPEED}                                            ║"
        echo "╚═══════════════════════════════════════════════════════════════════╝"
        
        send_gotify_notification "🚨 服务器已被限速！" "双向总流量已达 ${MONTH_TOTAL} GB，超过阈值 ${LIMIT_GB} GB。网络速度已被限制为 ${SPEED}。" 9
    fi
else
    if tc qdisc show dev $INTERFACE 2>/dev/null | grep -q "tbf"; then
        tc qdisc del dev $INTERFACE root
        echo ""
        echo "╔═══════════════════════════════════════════════════════════════════╗"
        echo "║  ✅ 已解除限速！双向总流量 ${MONTH_TOTAL}GB 未超过阈值                         ║"
        echo "╚═══════════════════════════════════════════════════════════════════╝"
        
        send_gotify_notification "✅ 限速已解除" "当前双向总流量为 ${MONTH_TOTAL} GB，已恢复正常网速。" 5
    fi
fi
echo ""