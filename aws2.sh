#!/bin/bash

# ============================================
# AWS Lightsail 实例管理脚本 (多 Region 支持)
# ============================================

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
# 告警通知配置
WECOM_WEBHOOK=""      # 企业微信
FEISHU_WEBHOOK=""     # 飞书
TELEGRAM_BOT_TOKEN="" # Telegram Bot Token
TELEGRAM_CHAT_ID=""   # Telegram Chat ID
DINGTALK_WEBHOOK=""   # 钉钉
DINGTALK_SECRET=""    # 钉钉加签密钥 (可选)

# 启用的通知渠道 (1=启用 0=禁用)
WECOM_ENABLED=0
FEISHU_ENABLED=0
TELEGRAM_ENABLED=0
DINGTALK_ENABLED=0

# 通知配置持久化文件
NOTIFY_CONFIG_FILE="/tmp/lightsail_notify.conf"

# 企业微信 Webhook
WECOM_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=b500e563-f054-4f9d-bd9c-49f0c0378b66"

# 流量告警阈值 (%)
ALERT_THRESHOLDS=(50 70 80 90)

# 告警记录文件
ALERT_STATE_FILE="/tmp/lightsail_alert_state.txt"

# 所有 Lightsail 支持的 Region
LIGHTSAIL_REGIONS=(
    "us-east-1"
    "us-east-2"
    "us-west-2"
    "eu-west-1"
    "eu-west-2"
    "eu-west-3"
    "eu-central-1"
    "eu-north-1"
    "ap-southeast-1"
    "ap-southeast-2"
    "ap-northeast-1"
    "ap-northeast-2"
    "ap-south-1"
    "ca-central-1"
    "sa-east-1"
)

# Region 中文名映射
declare -A REGION_NAMES=(
    ["us-east-1"]="北美 美国东部 弗吉尼亚"
    ["us-east-2"]="北美 美国东部 俄亥俄"
    ["us-west-2"]="北美 美国西部 俄勒冈"
    ["eu-west-1"]="欧洲 爱尔兰"
    ["eu-west-2"]="欧洲 英国 伦敦"
    ["eu-west-3"]="欧洲 法国 巴黎"
    ["eu-central-1"]="欧洲 德国 法兰克福"
    ["eu-north-1"]="欧洲 瑞典 斯德哥尔摩"
    ["ap-southeast-1"]="亚太 新加坡"
    ["ap-southeast-2"]="亚太 澳大利亚 悉尼"
    ["ap-northeast-1"]="亚太 日本 东京"
    ["ap-northeast-2"]="亚太 韩国 首尔"
    ["ap-south-1"]="亚太 印度 孟买"
    ["ca-central-1"]="北美 加拿大 中部"
    ["sa-east-1"]="南美 巴西 圣保罗"
)

# 全局实例列表
INSTANCE_NAMES=()
INSTANCE_REGIONS=()
SELECTED_NAME=""
SELECTED_REGION=""

# ============================================
# 安装依赖
# ============================================

install_awscli() {
    echo -e "${YELLOW}正在安装 AWS CLI ...${NC}"
    OS=$(uname -s)
    ARCH=$(uname -m)

    if [ "$OS" == "Darwin" ]; then
        if command -v brew &> /dev/null; then
            brew install awscli
        else
            echo -e "${RED}未找到 Homebrew，请先安装 Homebrew: https://brew.sh${NC}"
            exit 1
        fi
    elif [ "$OS" == "Linux" ]; then
        if [ "$ARCH" == "x86_64" ]; then
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
        elif [ "$ARCH" == "aarch64" ]; then
            curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o /tmp/awscliv2.zip
        else
            echo -e "${RED}不支持的架构: $ARCH${NC}"
            exit 1
        fi
        unzip -q /tmp/awscliv2.zip -d /tmp/
        sudo /tmp/aws/install
        rm -rf /tmp/awscliv2.zip /tmp/aws
    else
        echo -e "${RED}不支持的操作系统: $OS${NC}"
        exit 1
    fi

    if command -v aws &> /dev/null; then
        echo -e "${GREEN}AWS CLI 安装成功: $(aws --version)${NC}"
    else
        echo -e "${RED}AWS CLI 安装失败，请手动安装。${NC}"
        exit 1
    fi
}

install_jq() {
    echo -e "${YELLOW}正在安装 jq ...${NC}"
    OS=$(uname -s)

    if [ "$OS" == "Darwin" ]; then
        if command -v brew &> /dev/null; then
            brew install jq
        else
            echo -e "${RED}未找到 Homebrew，请先安装 Homebrew: https://brew.sh${NC}"
            exit 1
        fi
    elif [ "$OS" == "Linux" ]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -y && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y jq
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y jq
        else
            echo -e "${RED}无法识别包管理器，请手动安装 jq。${NC}"
            exit 1
        fi
    else
        echo -e "${RED}不支持的操作系统: $OS${NC}"
        exit 1
    fi

    if command -v jq &> /dev/null; then
        echo -e "${GREEN}jq 安装成功: $(jq --version)${NC}"
    else
        echo -e "${RED}jq 安装失败，请手动安装。${NC}"
        exit 1
    fi
}

configure_aws() {
    echo -e "${YELLOW}正在配置 AWS 凭证 ...${NC}"
    echo -e "${YELLOW}请依次输入以下信息（可在 AWS 控制台 IAM 页面获取）:${NC}"
    aws configure
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}AWS 凭证配置成功。${NC}"
    else
        echo -e "${RED}AWS 凭证配置失败。${NC}"
        exit 1
    fi
}

check_and_setup() {
    echo -e "${GREEN}=============================${NC}"
    echo -e "${GREEN}  检查运行环境...            ${NC}"
    echo -e "${GREEN}=============================${NC}"

    if ! command -v aws &> /dev/null; then
        echo -e "${YELLOW}未找到 AWS CLI，即将自动安装...${NC}"
        install_awscli
    else
        echo -e "${GREEN}AWS CLI 已安装: $(aws --version)${NC}"
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}未找到 jq，即将自动安装...${NC}"
        install_jq
    else
        echo -e "${GREEN}jq 已安装: $(jq --version)${NC}"
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${YELLOW}未检测到有效的 AWS 凭证，即将进行配置...${NC}"
        configure_aws
        if ! aws sts get-caller-identity &> /dev/null; then
            echo -e "${RED}AWS 凭证验证失败，请检查 Access Key 是否正确。${NC}"
            exit 1
        fi
    else
        ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
        echo -e "${GREEN}AWS 凭证有效，账号 ID: $ACCOUNT${NC}"
    fi

    echo -e "${GREEN}环境检查完成，所有依赖已就绪。${NC}"
}

# ============================================
# 中文字符宽度补齐工具函数
# ============================================

display_width() {
    local STR="$1"
    local BYTE_LEN=$(echo -n "$STR" | wc -c)
    local CHAR_LEN=${#STR}
    local CN_COUNT=$(( (BYTE_LEN - CHAR_LEN) / 2 ))
    echo $(( CHAR_LEN + CN_COUNT ))
}

pad_right() {
    local STR="$1"
    local WIDTH="$2"
    local DW=$(display_width "$STR")
    local PAD=$(( WIDTH - DW ))
    if [ $PAD -gt 0 ]; then
        printf "%s%*s" "$STR" "$PAD" ""
    else
        printf "%s" "$STR"
    fi
}

# ============================================
# 企业微信告警
# ============================================

send_wecom_alert() {
    local INSTANCE="$1"
    local REGION_CN="$2"
    local USED_GB="$3"
    local TOTAL_GB="$4"
    local PERCENT="$5"

    local LEVEL
    if [ "$PERCENT" -ge 90 ]; then
        LEVEL="严重 (>=90%)"
    elif [ "$PERCENT" -ge 80 ]; then
        LEVEL="警告 (>=80%)"
    elif [ "$PERCENT" -ge 70 ]; then
        LEVEL="注意 (>=70%)"
    else
        LEVEL="提醒 (>=50%)"
    fi

    local CONTENT="【AWS Lightsail 流量告警】\n实例名称：${INSTANCE}\n所在地区：${REGION_CN}\n套餐流量：${TOTAL_GB} GB\n本月已用：${USED_GB} GB\n使用比例：${PERCENT}%\n告警级别：${LEVEL}"

    curl -s -X POST "$WECOM_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$(echo -e "$CONTENT")\"}}" > /dev/null
}

check_alert() {
    local INSTANCE="$1"
    local REGION="$2"
    local REGION_CN="$3"
    local USED_GB="$4"
    local TOTAL_GB="$5"

    if [ "$TOTAL_GB" -eq 0 ]; then return; fi

    local PERCENT=$(( USED_GB * 100 / TOTAL_GB ))

    for THRESHOLD in "${ALERT_THRESHOLDS[@]}"; do
        local STATE_KEY="${INSTANCE}_${THRESHOLD}"
        if [ "$PERCENT" -ge "$THRESHOLD" ]; then
            if ! grep -qF "$STATE_KEY" "$ALERT_STATE_FILE" 2>/dev/null; then
                echo -e "${RED}  [告警] $INSTANCE 流量已达 ${PERCENT}%，触发 ${THRESHOLD}% 阈值，发送企业微信通知...${NC}"
                send_wecom_alert "$INSTANCE" "$REGION_CN" "$USED_GB" "$TOTAL_GB" "$PERCENT"
                echo "$STATE_KEY" >> "$ALERT_STATE_FILE"
            fi
        else
            if [ -f "$ALERT_STATE_FILE" ]; then
                sed -i "/$STATE_KEY/d" "$ALERT_STATE_FILE" 2>/dev/null || \
                sed -i '' "/$STATE_KEY/d" "$ALERT_STATE_FILE" 2>/dev/null
            fi
        fi
    done
}

# ============================================
# 流量查询
# ============================================

get_instance_traffic() {
    local INSTANCE="$1"
    local REGION="$2"

    local MONTH_START=$(date -u +"%Y-%m-01T00:00:00Z")
    local NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local RAW=$(aws lightsail get-instance-metric-data \
        --instance-name "$INSTANCE" \
        --metric-name "NetworkOut" \
        --period 2592000 \
        --start-time "$MONTH_START" \
        --end-time "$NOW" \
        --unit "Bytes" \
        --statistics "Sum" \
        --region "$REGION" \
        --query 'metricData[0].sum' \
        --output text 2>/dev/null)

    if [ -z "$RAW" ] || [ "$RAW" == "None" ] || [ "$RAW" == "null" ]; then
        echo "0"
        return
    fi

    echo "$RAW" | awk '{printf "%.1f", $1/1024/1024/1024}'
}

# ============================================
# 列出所有实例 + 流量统计
# ============================================

list_instances_with_traffic() {
    echo ""
    echo -e "${GREEN}=== 正在查询所有 Region 的 Lightsail 实例及流量统计 ===${NC}"
    echo -e "${YELLOW}(流量查询较慢，请稍候...)${NC}"

    INSTANCE_NAMES=()
    INSTANCE_REGIONS=()
    ALL_ROWS=()
    INDEX=1

    for REGION in "${LIGHTSAIL_REGIONS[@]}"; do
        RESULT=$(aws lightsail get-instances --region "$REGION" \
            --query 'instances[*].{name:name,state:state.name,ipv4:publicIpAddress,ipv6:ipv6Addresses,blueprint:blueprintId,bundle:bundleId}' \
            --output json 2>/dev/null)

        COUNT=$(echo "$RESULT" | jq 'length' 2>/dev/null)
        if [ -z "$RESULT" ] || [ "$COUNT" -eq 0 ]; then
            continue
        fi

        BUNDLE_TRANSFER_JSON=$(aws lightsail get-bundles --region "$REGION" \
            --query 'bundles[*].{id:bundleId,transfer:transferPerMonthInGb}' \
            --output json 2>/dev/null)

        for ROW in $(seq 0 $((COUNT - 1))); do
            NAME=$(echo "$RESULT"      | jq -r ".[$ROW].name")
            STATE=$(echo "$RESULT"     | jq -r ".[$ROW].state")
            IPV4=$(echo "$RESULT"      | jq -r ".[$ROW].ipv4 // \"无\"")
            IPV6=$(echo "$RESULT"      | jq -r ".[$ROW].ipv6[0] // \"无\"")
            BLUEPRINT=$(echo "$RESULT" | jq -r ".[$ROW].blueprint")
            BUNDLE=$(echo "$RESULT"    | jq -r ".[$ROW].bundle")
            REGION_CN="${REGION_NAMES[$REGION]}"

            TOTAL_GB=$(echo "$BUNDLE_TRANSFER_JSON" | \
                jq -r ".[] | select(.id==\"$BUNDLE\") | .transfer" 2>/dev/null)
            TOTAL_GB=${TOTAL_GB:-0}

            echo -e "${YELLOW}  正在查询 $NAME 流量...${NC}"
            USED_GB=$(get_instance_traffic "$NAME" "$REGION")
            USED_INT=$(echo "$USED_GB" | awk '{printf "%d", $1}')
            TOTAL_INT=$(echo "$TOTAL_GB" | awk '{printf "%d", $1}')

            if [ "$TOTAL_INT" -gt 0 ]; then
                PERCENT=$(echo "$USED_GB $TOTAL_GB" | awk '{printf "%d", $1*100/$2}')
            else
                PERCENT=0
            fi

            # 进度条（10格）
            FILLED=$(( PERCENT / 10 ))
            EMPTY=$(( 10 - FILLED ))
            BAR=""
            for ((f=0; f<FILLED; f++)); do BAR="${BAR}█"; done
            for ((e=0; e<EMPTY; e++)); do BAR="${BAR}░"; done

            ALL_ROWS+=("$INDEX|$NAME|$REGION|$REGION_CN|$IPV4|$IPV6|$STATE|$BLUEPRINT|$BUNDLE|$USED_GB|$TOTAL_GB|$PERCENT|$BAR")
            INSTANCE_NAMES+=("$NAME")
            INSTANCE_REGIONS+=("$REGION")

            check_alert "$NAME" "$REGION" "$REGION_CN" "$USED_INT" "$TOTAL_INT"

            ((INDEX++))
        done
    done

    if [ ${#INSTANCE_NAMES[@]} -eq 0 ]; then
        echo -e "${YELLOW}未在任何 Region 找到实例。${NC}"
        return 1
    fi

    # 打印表头
    printf "\n"
    printf "%-6s  %-22s  %-16s  %-22s  %-42s  %-9s  %-14s  %s\n" \
        "编号" "名称" "IPv4" "地区" "IPv6" "状态" "Blueprint" "流量 (已用/总量)"
    printf '%0.s-' {1..175}; printf '\n'

    for ROW_DATA in "${ALL_ROWS[@]}"; do
        IFS='|' read -r IDX NAME REGION REGION_CN IPV4 IPV6 STATE \
            BLUEPRINT BUNDLE USED_GB TOTAL_GB PERCENT BAR <<< "$ROW_DATA"

        # 状态着色，固定9字符宽
        if [ "$STATE" == "running" ]; then
            STATE_STR="${GREEN}running${NC}  "
        elif [ "$STATE" == "stopped" ]; then
            STATE_STR="${RED}stopped${NC}  "
        else
            STATE_STR="${YELLOW}${STATE}${NC}  "
        fi

        # 流量颜色
        if [ "$PERCENT" -ge 90 ]; then
            TC="$RED"
        elif [ "$PERCENT" -ge 70 ]; then
            TC="$YELLOW"
        else
            TC="$GREEN"
        fi

        # 用 pad_right 对中文地区名和 IPv6 补齐
        printf "%-6s  %-22s  %-16s  %s  %-42s  %b  %-14s  %b\n" \
            "[$IDX]" \
            "$(pad_right "$NAME" 22)" \
            "$(pad_right "$IPV4" 16)" \
            "$(pad_right "$REGION_CN" 22)" \
            "$(pad_right "$IPV6" 42)" \
            "$STATE_STR" \
            "$BLUEPRINT" \
            "${TC}${BAR} ${USED_GB}G/${TOTAL_GB}G (${PERCENT}%)${NC}"
    done

    printf '%0.s-' {1..175}; printf '\n'
    echo -e "${GREEN}共找到 $((INDEX - 1)) 个实例。${NC}"
    return 0
}

# ============================================
# 选择实例
# ============================================

select_instance() {
    local TOTAL=${#INSTANCE_NAMES[@]}
    while true; do
        read -p "请输入实例编号 [1-${TOTAL}]: " IDX
        if [[ "$IDX" =~ ^[0-9]+$ ]] && [ "$IDX" -ge 1 ] && [ "$IDX" -le "$TOTAL" ]; then
            SELECTED_NAME="${INSTANCE_NAMES[$((IDX-1))]}"
            SELECTED_REGION="${INSTANCE_REGIONS[$((IDX-1))]}"
            SELECTED_REGION_CN="${REGION_NAMES[$SELECTED_REGION]}"
            echo -e "${GREEN}已选择: $SELECTED_NAME ($SELECTED_REGION_CN)${NC}"
            break
        else
            echo -e "${RED}无效编号，请重新输入。${NC}"
        fi
    done
}

# ============================================
# 实例操作菜单
# ============================================

instance_action_menu() {
    list_instances_with_traffic || return

    echo ""
    select_instance

    while true; do
        echo ""
        echo -e "${BLUE}=== 实例: $SELECTED_NAME | ${REGION_NAMES[$SELECTED_REGION]} ===${NC}"
        echo "1. 查看详情"
        echo "2. 启动"
        echo "3. 停止"
        echo "4. 重启"
        echo "5. 创建快照"
        echo "6. 删除实例"
        echo "7. 等待实例状态"
        echo "8. 重新选择实例"
        echo "0. 返回主菜单"
        read -p "请选择操作 [0-8]: " ACTION

        case $ACTION in
            1) do_get_info ;;
            2) do_start ;;
            3) do_stop ;;
            4) do_reboot ;;
            5) do_create_snapshot ;;
            6) do_delete; return ;;
            7) do_wait_state ;;
            8) echo ""; select_instance ;;
            0) return ;;
            *) echo -e "${RED}无效选项。${NC}" ;;
        esac
    done
}

# ============================================
# 具体操作函数
# ============================================

do_get_info() {
    echo -e "${GREEN}=== 实例详情: $SELECTED_NAME ===${NC}"
    aws lightsail get-instance \
        --instance-name "$SELECTED_NAME" \
        --region "$SELECTED_REGION" \
        --output json | jq '.instance | {
            "Name": .name,
            "State": .state.name,
            "IPv4": .publicIpAddress,
            "IPv6": .ipv6Addresses,
            "PrivateIP": .privateIpAddress,
            "Blueprint": .blueprintId,
            "Bundle": .bundleId,
            "CreatedAt": .createdAt
        }'
}

do_start() {
    echo -e "${YELLOW}正在启动实例: $SELECTED_NAME ...${NC}"
    aws lightsail start-instance \
        --instance-name "$SELECTED_NAME" \
        --region "$SELECTED_REGION"
    [ $? -eq 0 ] && echo -e "${GREEN}启动命令已发送。${NC}" || echo -e "${RED}启动失败。${NC}"
}

do_stop() {
    read -p "是否强制停止? (y/n): " FORCE
    echo -e "${YELLOW}正在停止实例: $SELECTED_NAME ...${NC}"
    if [ "$FORCE" == "y" ]; then
        aws lightsail stop-instance \
            --instance-name "$SELECTED_NAME" \
            --region "$SELECTED_REGION" \
            --force
    else
        aws lightsail stop-instance \
            --instance-name "$SELECTED_NAME" \
            --region "$SELECTED_REGION"
    fi
    [ $? -eq 0 ] && echo -e "${GREEN}停止命令已发送。${NC}" || echo -e "${RED}停止失败。${NC}"
}

do_reboot() {
    echo -e "${YELLOW}正在重启实例: $SELECTED_NAME ...${NC}"
    aws lightsail reboot-instance \
        --instance-name "$SELECTED_NAME" \
        --region "$SELECTED_REGION"
    [ $? -eq 0 ] && echo -e "${GREEN}重启命令已发送。${NC}" || echo -e "${RED}重启失败。${NC}"
}

do_create_snapshot() {
    SNAPSHOT_NAME="${SELECTED_NAME}-snapshot-$(date +%Y%m%d-%H%M%S)"
    echo -e "${YELLOW}正在创建快照: $SNAPSHOT_NAME ...${NC}"
    aws lightsail create-instance-snapshot \
        --instance-name "$SELECTED_NAME" \
        --instance-snapshot-name "$SNAPSHOT_NAME" \
        --region "$SELECTED_REGION"
    [ $? -eq 0 ] && echo -e "${GREEN}快照 $SNAPSHOT_NAME 创建命令已发送。${NC}" || echo -e "${RED}创建快照失败。${NC}"
}

do_delete() {
    echo -e "${RED}警告: 此操作将永久删除实例 $SELECTED_NAME！${NC}"
    read -p "请再次输入实例名称确认删除: " CONFIRM
    if [ "$CONFIRM" == "$SELECTED_NAME" ]; then
        aws lightsail delete-instance \
            --instance-name "$SELECTED_NAME" \
            --region "$SELECTED_REGION"
        [ $? -eq 0 ] && echo -e "${GREEN}实例已删除。${NC}" || echo -e "${RED}删除失败。${NC}"
    else
        echo -e "${YELLOW}名称不匹配，操作已取消。${NC}"
    fi
}

do_wait_state() {
    read -p "等待状态 (running/stopped): " TARGET_STATE
    echo -e "${YELLOW}等待实例 $SELECTED_NAME 变为 $TARGET_STATE ...${NC}"
    while true; do
        CURRENT=$(aws lightsail get-instance \
            --instance-name "$SELECTED_NAME" \
            --region "$SELECTED_REGION" \
            --query 'instance.state.name' \
            --output text 2>/dev/null)
        echo "当前状态: $CURRENT"
        [ "$CURRENT" == "$TARGET_STATE" ] && echo -e "${GREEN}已达到 $TARGET_STATE 状态！${NC}" && break
        sleep 5
    done
}

# ============================================
# 快照管理
# ============================================

list_snapshots() {
    echo -e "${GREEN}=== 所有 Region 的实例快照 ===${NC}"
    FOUND=0
    for REGION in "${LIGHTSAIL_REGIONS[@]}"; do
        RESULT=$(aws lightsail get-instance-snapshots \
            --region "$REGION" \
            --query 'instanceSnapshots[*].{Name:name,State:state,FromInstance:fromInstanceName,CreatedAt:createdAt,SizeGB:sizeInGb}' \
            --output table 2>/dev/null)
        if echo "$RESULT" | grep -q "Name"; then
            echo -e "${YELLOW}--- ${REGION_NAMES[$REGION]} ($REGION) ---${NC}"
            echo "$RESULT"
            FOUND=1
        fi
    done
    [ $FOUND -eq 0 ] && echo -e "${YELLOW}未在任何 Region 找到快照。${NC}"
}

# ============================================
# 创建新实例
# ============================================

create_instance() {
    echo -e "${GREEN}=== 创建新 Lightsail 实例 ===${NC}"
    echo ""

    # ---- 选择 Region ----
    for i in "${!LIGHTSAIL_REGIONS[@]}"; do
        REGION="${LIGHTSAIL_REGIONS[$i]}"
        printf "%3d. %-20s %s\n" "$((i+1))" "$REGION" "${REGION_NAMES[$REGION]}"
    done
    while true; do
        read -p "请选择 Region 编号 [1-${#LIGHTSAIL_REGIONS[@]}]: " RIDX
        if [[ "$RIDX" =~ ^[0-9]+$ ]] && [ "$RIDX" -ge 1 ] && [ "$RIDX" -le "${#LIGHTSAIL_REGIONS[@]}" ]; then
            NEW_REGION="${LIGHTSAIL_REGIONS[$((RIDX-1))]}"
            echo -e "${GREEN}已选择: ${REGION_NAMES[$NEW_REGION]} ($NEW_REGION)${NC}"
            break
        fi
        echo -e "${RED}无效编号。${NC}"
    done

    # ---- 选择可用区 ----
    echo ""
    echo -e "${BLUE}=== 可用区 ===${NC}"
    AZ_LIST=$(aws lightsail get-regions --include-availability-zones \
        --query "regions[?name=='$NEW_REGION'].availabilityZones[*].zoneName" \
        --output json --region "$NEW_REGION" 2>/dev/null | jq -r '.[][]')
    AZ_ARRAY=()
    AZ_IDX=1
    while IFS= read -r AZ_ITEM; do
        printf "%3d. %s\n" "$AZ_IDX" "$AZ_ITEM"
        AZ_ARRAY+=("$AZ_ITEM")
        ((AZ_IDX++))
    done <<< "$AZ_LIST"

    while true; do
        read -p "请选择可用区编号 [1-${#AZ_ARRAY[@]}]: " AZIDX
        if [[ "$AZIDX" =~ ^[0-9]+$ ]] && [ "$AZIDX" -ge 1 ] && [ "$AZIDX" -le "${#AZ_ARRAY[@]}" ]; then
            NEW_AZ="${AZ_ARRAY[$((AZIDX-1))]}"
            echo -e "${GREEN}已选择可用区: $NEW_AZ${NC}"
            break
        fi
        echo -e "${RED}无效编号。${NC}"
    done

    # ---- 实例名称 ----
    echo ""
    read -p "请输入实例名称: " NEW_NAME

    # ---- 选择 Linux 系统 ----
    echo ""
    echo -e "${BLUE}=== 选择 Linux 系统 ===${NC}"
    BLUEPRINT_JSON=$(aws lightsail get-blueprints --region "$NEW_REGION" \
        --query 'blueprints[?platform==`LINUX_UNIX` && type==`os`].{id:blueprintId,name:name}' \
        --output json 2>/dev/null)
    BLUEPRINT_IDS=()
    BLUEPRINT_LABELS=()
    BP_IDX=1
    BP_COUNT=$(echo "$BLUEPRINT_JSON" | jq 'length')
    for i in $(seq 0 $((BP_COUNT - 1))); do
        BP_ID=$(echo "$BLUEPRINT_JSON"   | jq -r ".[$i].id")
        BP_NAME=$(echo "$BLUEPRINT_JSON" | jq -r ".[$i].name")
        printf "%3d. %-30s (%s)\n" "$BP_IDX" "$BP_NAME" "$BP_ID"
        BLUEPRINT_IDS+=("$BP_ID")
        BLUEPRINT_LABELS+=("$BP_NAME")
        ((BP_IDX++))
    done

    while true; do
        read -p "请选择系统编号 [1-${#BLUEPRINT_IDS[@]}]: " BPIDX
        if [[ "$BPIDX" =~ ^[0-9]+$ ]] && [ "$BPIDX" -ge 1 ] && [ "$BPIDX" -le "${#BLUEPRINT_IDS[@]}" ]; then
            NEW_BLUEPRINT="${BLUEPRINT_IDS[$((BPIDX-1))]}"
            NEW_BLUEPRINT_NAME="${BLUEPRINT_LABELS[$((BPIDX-1))]}"
            echo -e "${GREEN}已选择系统: $NEW_BLUEPRINT_NAME${NC}"
            break
        fi
        echo -e "${RED}无效编号。${NC}"
    done

    # 判断默认登录用户
    BP_LOWER=$(echo "$NEW_BLUEPRINT" | tr '[:upper:]' '[:lower:]')
    if echo "$BP_LOWER" | grep -q "ubuntu"; then
        DEFAULT_USER="ubuntu"
    elif echo "$BP_LOWER" | grep -q "debian"; then
        DEFAULT_USER="admin"
    elif echo "$BP_LOWER" | grep -q "amazon\|amzn\|al2"; then
        DEFAULT_USER="ec2-user"
    elif echo "$BP_LOWER" | grep -q "centos"; then
        DEFAULT_USER="centos"
    elif echo "$BP_LOWER" | grep -q "freebsd"; then
        DEFAULT_USER="ec2-user"
    else
        DEFAULT_USER="ec2-user"
    fi

    # ---- 选择套餐 ----
    echo ""
    echo -e "${BLUE}=== 选择套餐规格 ===${NC}"
    BUNDLE_JSON=$(aws lightsail get-bundles --region "$NEW_REGION" \
        --query 'bundles[?supportedPlatforms[?contains(@, `LINUX_UNIX`)] && isActive==`true`].{id:bundleId,cpu:cpuCount,ram:ramSizeInGb,disk:diskSizeInGb,transfer:transferPerMonthInGb,price:price}' \
        --output json 2>/dev/null)

    BUNDLE_IDS=()
    BUNDLE_INFOS=()
    BN_IDX=1
    BN_COUNT=$(echo "$BUNDLE_JSON" | jq 'length')

    printf "\n%-4s  %-16s  %-6s  %-8s  %-10s  %-12s  %s\n" \
        "编号" "套餐ID" "CPU" "内存" "硬盘" "流量/月" "价格(美元/月)"
    printf '%0.s-' {1..75}; printf '\n'

    for i in $(seq 0 $((BN_COUNT - 1))); do
        BN_ID=$(echo "$BUNDLE_JSON"       | jq -r ".[$i].id")
        BN_CPU=$(echo "$BUNDLE_JSON"      | jq -r ".[$i].cpu")
        BN_RAM=$(echo "$BUNDLE_JSON"      | jq -r ".[$i].ram")
        BN_DISK=$(echo "$BUNDLE_JSON"     | jq -r ".[$i].disk")
        BN_TRANSFER=$(echo "$BUNDLE_JSON" | jq -r ".[$i].transfer")
        BN_PRICE=$(echo "$BUNDLE_JSON"    | jq -r ".[$i].price")

        printf "%-4s  %-16s  %-6s  %-8s  %-10s  %-12s  \$%s\n" \
            "[$BN_IDX]" "$BN_ID" "${BN_CPU}核" "${BN_RAM}GB" "${BN_DISK}GB" "${BN_TRANSFER}GB" "$BN_PRICE"

        BUNDLE_IDS+=("$BN_ID")
        BUNDLE_INFOS+=("${BN_CPU}核 ${BN_RAM}GB内存 ${BN_DISK}GB硬盘 ${BN_TRANSFER}GB流量 \$${BN_PRICE}/月")
        ((BN_IDX++))

        if [ "$BN_ID" == "16xlarge_3_0" ]; then
            break
        fi
    done

    printf '%0.s-' {1..75}; printf '\n'

    while true; do
        read -p "请选择套餐编号 [1-${#BUNDLE_IDS[@]}]: " BNIDX
        if [[ "$BNIDX" =~ ^[0-9]+$ ]] && [ "$BNIDX" -ge 1 ] && [ "$BNIDX" -le "${#BUNDLE_IDS[@]}" ]; then
            NEW_BUNDLE="${BUNDLE_IDS[$((BNIDX-1))]}"
            BUNDLE_INFO="${BUNDLE_INFOS[$((BNIDX-1))]}"
            echo -e "${GREEN}已选择套餐: $NEW_BUNDLE ($BUNDLE_INFO)${NC}"
            break
        fi
        echo -e "${RED}无效编号。${NC}"
    done

    # ---- 选择 SSH 密钥 ----
    echo ""
    echo -e "${BLUE}=== 选择 SSH 密钥 ===${NC}"
    KEY_JSON=$(aws lightsail get-key-pairs --region "$NEW_REGION" \
        --query 'keyPairs[*].{name:name,fingerprint:fingerprint}' \
        --output json 2>/dev/null)
    KEY_COUNT=$(echo "$KEY_JSON" | jq 'length')
    KEY_NAMES=()

    if [ "$KEY_COUNT" -gt 0 ]; then
        printf "%-4s  %-30s  %s\n" "编号" "密钥名称" "指纹"
        printf '%0.s-' {1..80}; printf '\n'
        for i in $(seq 0 $((KEY_COUNT - 1))); do
            KN=$(echo "$KEY_JSON" | jq -r ".[$i].name")
            KF=$(echo "$KEY_JSON" | jq -r ".[$i].fingerprint")
            printf "%-4s  %-30s  %s\n" "[$((i+1))]" "$KN" "$KF"
            KEY_NAMES+=("$KN")
        done
        printf '%0.s-' {1..80}; printf '\n'
    else
        echo -e "${YELLOW}该 Region 下没有 SSH 密钥。${NC}"
    fi

    echo "[$((KEY_COUNT+1))]. 上传新 SSH 公钥"
    echo ""

    while true; do
        read -p "请选择密钥编号 [1-$((KEY_COUNT+1))]: " KIDX
        if [[ "$KIDX" =~ ^[0-9]+$ ]] && [ "$KIDX" -ge 1 ] && [ "$KIDX" -le "$KEY_COUNT" ]; then
            NEW_KEY="${KEY_NAMES[$((KIDX-1))]}"
            echo -e "${GREEN}已选择密钥: $NEW_KEY${NC}"
            break
        elif [[ "$KIDX" =~ ^[0-9]+$ ]] && [ "$KIDX" -eq $((KEY_COUNT+1)) ]; then
            read -p "请输入新密钥名称: " NEW_KEY
            read -p "请粘贴 SSH 公钥内容 (ssh-rsa AAAA...): " PUBKEY
            aws lightsail import-key-pair \
                --key-pair-name "$NEW_KEY" \
                --public-key-base64 "$PUBKEY" \
                --region "$NEW_REGION"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}SSH 公钥 $NEW_KEY 上传成功。${NC}"
                break
            else
                echo -e "${RED}SSH 公钥上传失败，请检查公钥格式。${NC}"
                return
            fi
        else
            echo -e "${RED}无效编号。${NC}"
        fi
    done

    # ---- 打印配置单 ----
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}           实例创建配置单                   ${NC}"
    echo -e "${BLUE}============================================${NC}"
    printf "  %-16s %s\n" "实例名称:"   "$NEW_NAME"
    printf "  %-16s %s\n" "地区:"       "${REGION_NAMES[$NEW_REGION]} ($NEW_REGION)"
    printf "  %-16s %s\n" "可用区:"     "$NEW_AZ"
    printf "  %-16s %s\n" "操作系统:"   "$NEW_BLUEPRINT_NAME ($NEW_BLUEPRINT)"
    printf "  %-16s %s\n" "套餐规格:"   "$BUNDLE_INFO"
    printf "  %-16s %s\n" "SSH 密钥:"   "$NEW_KEY"
    printf "  %-16s %s\n" "默认登录名:" "$DEFAULT_USER"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    read -p "确认创建? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo -e "${YELLOW}已取消创建。${NC}"
        return
    fi

    # ---- 执行创建 ----
    echo -e "${YELLOW}正在创建实例: $NEW_NAME ...${NC}"
    aws lightsail create-instances \
        --instance-names "$NEW_NAME" \
        --availability-zone "$NEW_AZ" \
        --blueprint-id "$NEW_BLUEPRINT" \
        --bundle-id "$NEW_BUNDLE" \
        --key-pair-name "$NEW_KEY" \
        --region "$NEW_REGION"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}实例 $NEW_NAME 创建成功！${NC}"
        echo -e "${GREEN}SSH 连接方式: ssh -i <私钥文件> ${DEFAULT_USER}@<公网IP>${NC}"
    else
        echo -e "${RED}创建实例失败。${NC}"
    fi
}

# ============================================
# 主菜单
# ============================================

main_menu() {
    while true; do
        echo ""
        echo -e "${GREEN}=============================${NC}"
        echo -e "${GREEN}  AWS Lightsail 管理脚本     ${NC}"
        echo -e "${GREEN}=============================${NC}"
        echo "1. 列出实例并操作"
        echo "2. 流量统计监控"
        echo "3. 列出所有快照"
        echo "4. 创建新实例"
        echo "0. 退出"
        echo -e "${GREEN}=============================${NC}"
        read -p "请选择操作 [0-4]: " CHOICE

        case $CHOICE in
            1) instance_action_menu ;;
            2) list_instances_with_traffic ;;
            3) list_snapshots ;;
            4) create_instance ;;
            0) echo "退出脚本。"; exit 0 ;;
            *) echo -e "${RED}无效选项，请重新选择。${NC}" ;;
        esac
    done
}

# ============================================
# 入口
# ============================================

check_and_setup
main_menu
