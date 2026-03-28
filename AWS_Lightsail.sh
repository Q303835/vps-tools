#!/bin/bash

# ==========================================
# 全局变量与配置文件路径
# ==========================================
CONFIG_FILE="$HOME/.lightsail_bot.conf"
TEMP_INSTANCE_FILE="/tmp/aws_lightsail_instances_map.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==========================================
# 0. 配置读取与保存模块
# ==========================================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        NOTIFY_CHANNEL="none"
        ALERT_PERCENTAGE=80
        TG_TOKEN=""
        TG_CHAT_ID=""
        WECOM_WEBHOOK=""
        DINGTALK_WEBHOOK=""
        FEISHU_WEBHOOK=""
    fi
}

save_config() {
    cat <<EOF > "$CONFIG_FILE"
NOTIFY_CHANNEL="$NOTIFY_CHANNEL"
ALERT_PERCENTAGE="$ALERT_PERCENTAGE"
TG_TOKEN="$TG_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"
WECOM_WEBHOOK="$WECOM_WEBHOOK"
DINGTALK_WEBHOOK="$DINGTALK_WEBHOOK"
FEISHU_WEBHOOK="$FEISHU_WEBHOOK"
EOF
}

load_config

# ==========================================
# 1. 账号管理 (多 Profile)
# ==========================================
manage_account() {
    echo -e "\n--- ${CYAN}账号管理${NC} ---"
    current_profile=$(grep "\[" ~/.aws/credentials 2>/dev/null | tr -d '[]')
    echo -e "当前已保存的配置文件:\n${current_profile:-无}"
    
    read -p "请输入要使用的 Profile 名称 (默认 default, 输入 0 返回): " profile_name
    if [[ "$profile_name" == "0" ]]; then return; fi
    profile_name=${profile_name:-default}

    if ! aws configure list --profile "$profile_name" &> /dev/null; then
        echo -e "${YELLOW}正在为 $profile_name 配置新凭据...${NC}"
        aws configure --profile "$profile_name"
    else
        echo -e "${GREEN}已切换至: $profile_name${NC}"
    fi
    export AWS_PROFILE=$profile_name
}

# ==========================================
# 2. 光帆地域及套餐映射表
# ==========================================
get_region_name() {
    case $1 in
        "ap-northeast-1") echo "亚太地区_日本东部东京" ;;
        "ap-northeast-2") echo "亚太地区_韩国中部首尔" ;;
        "ap-southeast-1") echo "亚太地区_新加坡" ;;
        "ap-southeast-2") echo "亚太地区_悉尼" ;;
        "ap-south-1")     echo "亚太地区_印度孟买" ;;
        "us-east-1")      echo "美国东部_弗吉尼亚州" ;;
        "us-east-2")      echo "美国东部_俄亥俄州" ;;
        "us-west-2")      echo "美国西部_俄勒冈州" ;;
        "eu-west-1")      echo "欧洲_爱尔兰" ;;
        "eu-west-2")      echo "欧洲_伦敦" ;;
        "eu-west-3")      echo "欧洲_巴黎" ;;
        "eu-central-1")   echo "欧洲_法兰克福" ;;
        "eu-north-1")     echo "欧洲_斯德哥尔摩" ;;
        "ca-central-1")   echo "加拿大中部_蒙特利尔" ;;
        *) echo "$1" ;;
    esac
}

get_bundle_allowance() {
    case $1 in
        *nano*) echo 1024 ;;
        *micro*) echo 2048 ;;
        *small*) echo 3072 ;;
        *medium*) echo 4096 ;;
        *large*) echo 5120 ;;
        *xlarge*) echo 6144 ;;
        *) echo 1024 ;;
    esac
}

# ==========================================
# 3. 机器人告警配置与发送模块
# ==========================================
send_alert() {
    local msg="$1"
    local channel="${2:-$NOTIFY_CHANNEL}"
    
    if [[ "$channel" == "none" || -z "$channel" ]]; then return; fi

    case $channel in
        "tg") curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d "chat_id=${TG_CHAT_ID}&text=${msg}" > /dev/null ;;
        "wecom") curl -s -H "Content-Type: application/json" -X POST -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"${msg}\"}}" "${WECOM_WEBHOOK}" > /dev/null ;;
        "dingtalk") curl -s -H "Content-Type: application/json" -X POST -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"${msg}\"}}" "${DINGTALK_WEBHOOK}" > /dev/null ;;
        "feishu") curl -s -H "Content-Type: application/json" -X POST -d "{\"msg_type\": \"text\", \"content\": {\"text\": \"${msg}\"}}" "${FEISHU_WEBHOOK}" > /dev/null ;;
    esac
}

setup_notifications() {
    while true; do
        clear
        echo -e "=== ${CYAN}机器人通知与告警设置${NC} ==="
        echo -e "当前启用渠道: ${GREEN}${NOTIFY_CHANNEL}${NC}"
        echo -e "当前流量报警阈值: ${GREEN}${ALERT_PERCENTAGE}%${NC}"
        echo "-----------------------------------"
        echo "1. 配置 Telegram"
        echo "2. 配置 企业微信 (WeCom)"
        echo "3. 配置 钉钉 (DingTalk)"
        echo "4. 配置 飞书 (Feishu)"
        echo "5. 设置 流量报警百分比 (如 50, 80, 90)"
        echo "6. 停用所有通知"
        echo "7. 发送一条测试消息"
        echo "0. 返回主菜单"
        echo "==================================="
        read -p "请输入对应的数字: " bot_choice

        case $bot_choice in
            1)
                read -p "请输入 TG Bot Token: " input_token
                read -p "请输入 TG Chat ID: " input_chat_id
                if [[ -n "$input_token" && -n "$input_chat_id" ]]; then
                    TG_TOKEN="$input_token"
                    TG_CHAT_ID="$input_chat_id"
                    NOTIFY_CHANNEL="tg"
                    save_config
                    echo -e "${GREEN}Telegram 配置已保存并启用！${NC}"
                fi
                sleep 1 ;;
            2)
                read -p "请输入企业微信 Webhook 的 Key (例: b500e563-f054-4f9d-bd9c-49f0c0378b66): " input_key
                if [[ "$input_key" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                    WECOM_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$input_key"
                    NOTIFY_CHANNEL="wecom"
                    save_config
                    echo -e "${GREEN}企业微信配置已保存并启用！${NC}"
                else
                    echo -e "${RED}输入格式不正确！请输入标准的 36 位 UUID Key。${NC}"
                fi
                sleep 2 ;;
            3)
                read -p "请输入钉钉 Webhook 完整地址: " input_hook
                if [[ -n "$input_hook" ]]; then
                    DINGTALK_WEBHOOK="$input_hook"
                    NOTIFY_CHANNEL="dingtalk"
                    save_config
                    echo -e "${GREEN}钉钉配置已保存并启用！${NC}"
                fi
                sleep 1 ;;
            4)
                read -p "请输入飞书 Webhook 完整地址: " input_hook
                if [[ -n "$input_hook" ]]; then
                    FEISHU_WEBHOOK="$input_hook"
                    NOTIFY_CHANNEL="feishu"
                    save_config
                    echo -e "${GREEN}飞书配置已保存并启用！${NC}"
                fi
                sleep 1 ;;
            5)
                read -p "请输入流量报警百分比 (直接输入数字，如 80 代表 80%): " input_pct
                if [[ "$input_pct" =~ ^[0-9]+$ && "$input_pct" -le 100 ]]; then
                    ALERT_PERCENTAGE="$input_pct"
                    save_config
                    echo -e "${GREEN}报警阈值已更新为 ${ALERT_PERCENTAGE}%！${NC}"
                else
                    echo -e "${RED}输入无效，请输入 1-100 的纯数字。${NC}"
                fi
                sleep 1 ;;
            6)
                NOTIFY_CHANNEL="none"
                save_config
                echo -e "${YELLOW}已停用所有机器人的自动通知。${NC}"
                sleep 1 ;;
            7)
                if [[ "$NOTIFY_CHANNEL" == "none" ]]; then
                    echo -e "${RED}请先配置并启用一个通知渠道！${NC}"
                else
                    echo -e "${YELLOW}正在发送测试消息到 $NOTIFY_CHANNEL...${NC}"
                    send_alert "🤖 AWS Lightsail 告警助手: 这是一条测试消息，说明您的 Webhook 配置成功！"
                    echo -e "${GREEN}发送完成！请检查您的客户端。${NC}"
                fi
                read -n 1 -s -p "按任意键继续..." ;;
            0) break ;;
            *) echo -e "${RED}输入无效。${NC}"; sleep 1 ;;
        esac
    done
}

# ==========================================
# 4. 创建新实例模块 (包含 SSH 密钥直传逻辑)
# ==========================================
create_instance() {
    echo -e "\n--- ${CYAN}创建新实例${NC} ---"
    read -p "请输入新实例名称 (例: MyNewVPS, 输入 0 返回): " new_name
    if [[ "$new_name" == "0" ]]; then return; fi
    
    echo -e "\n${YELLOW}请选择实例所在地域:${NC}"
    echo "1. 亚太地区_日本东部东京 (ap-northeast-1)"
    echo "2. 亚太地区_韩国中部首尔 (ap-northeast-2)"
    echo "3. 亚太地区_新加坡 (ap-southeast-1)"
    echo "4. 亚太地区_悉尼 (ap-southeast-2)"
    echo "5. 亚太地区_印度孟买 (ap-south-1)"
    echo "6. 美国东部_弗吉尼亚州 (us-east-1)"
    echo "7. 美国东部_俄亥俄州 (us-east-2)"
    echo "8. 美国西部_俄勒冈州 (us-west-2)"
    echo "9. 欧洲_法兰克福 (eu-central-1)"
    echo "10. 欧洲_爱尔兰 (eu-west-1)"
    echo "11. 欧洲_伦敦 (eu-west-2)"
    echo "12. 欧洲_巴黎 (eu-west-3)"
    echo "13. 欧洲_斯德哥尔摩 (eu-north-1)"
    echo "14. 加拿大中部_蒙特利尔 (ca-central-1)"
    echo "0. 返回"
    read -p "请输入数字选择地域 [0-14]: " reg_choice
    case $reg_choice in
        1) new_reg="ap-northeast-1";; 2) new_reg="ap-northeast-2";;
        3) new_reg="ap-southeast-1";; 4) new_reg="ap-southeast-2";;
        5) new_reg="ap-south-1";;     6) new_reg="us-east-1";;
        7) new_reg="us-east-2";;      8) new_reg="us-west-2";;
        9) new_reg="eu-central-1";;   10) new_reg="eu-west-1";;
        11) new_reg="eu-west-2";;     12) new_reg="eu-west-3";;
        13) new_reg="eu-north-1";;    14) new_reg="ca-central-1";;
        0) return;; *) echo -e "${RED}选择无效，返回菜单。${NC}"; return;;
    esac
    new_az="${new_reg}a"

    echo -e "\n${YELLOW}请选择 Linux 操作系统:${NC}"
    echo "1. Debian 12"
    echo "2. Debian 11"
    echo "3. Ubuntu 24.04 LTS"
    echo "4. Ubuntu 22.04 LTS"
    echo "5. Ubuntu 20.04 LTS"
    echo "6. CentOS 9 Stream"
    echo "7. AlmaLinux 9"
    echo "8. Amazon Linux 2023"
    echo "0. 返回"
    read -p "请输入数字选择系统 [0-8]: " os_choice
    case $os_choice in
        1) new_blueprint="debian_12";;      2) new_blueprint="debian_11";;
        3) new_blueprint="ubuntu_24_04";;   4) new_blueprint="ubuntu_22_04";;
        5) new_blueprint="ubuntu_20_04";;   6) new_blueprint="centos_9";;
        7) new_blueprint="almalinux_9";;    8) new_blueprint="amazon_linux_2023";;
        0) return;; *) echo -e "${RED}选择无效，返回菜单。${NC}"; return;;
    esac

    echo -e "\n${YELLOW}请选择机器配置套餐 (价格为含 IPv4 的参考月租):${NC}"
    echo "1. 月租 ~\$5  | 2核 CPU, 512MB RAM | 1TB 流量包 (nano_3_0)"
    echo "2. 月租 ~\$7  | 2核 CPU, 1GB RAM   | 2TB 流量包 (micro_3_0)"
    echo "3. 月租 ~\$12 | 2核 CPU, 2GB RAM   | 3TB 流量包 (small_3_0)"
    echo "4. 月租 ~\$24 | 2核 CPU, 4GB RAM   | 4TB 流量包 (medium_3_0)"
    echo "5. 月租 ~\$44 | 2核 CPU, 8GB RAM   | 5TB 流量包 (large_3_0)"
    echo "6. 月租 ~\$84 | 4核 CPU, 16GB RAM  | 6TB 流量包 (xlarge_3_0)"
    echo "0. 返回"
    read -p "请输入数字选择配置套餐 [0-6]: " bundle_choice
    case $bundle_choice in
        1) new_bundle="nano_3_0";;     2) new_bundle="micro_3_0";;
        3) new_bundle="small_3_0";;    4) new_bundle="medium_3_0";;
        5) new_bundle="large_3_0";;    6) new_bundle="xlarge_3_0";;
        0) return;; *) echo -e "${RED}选择无效，返回菜单。${NC}"; return;;
    esac

    # ---- 密钥上传与选择逻辑开始 ----
    echo -e "\n${CYAN}正在获取该地域 [$new_reg] 下已有的 SSH 密钥...${NC}"
    keys=$(aws lightsail get-key-pairs --region "$new_reg" --query "keyPairs[].name" --output text 2>/dev/null)
    key_array=($keys)

    # 封装一个上传密钥的子函数
    upload_new_key() {
        echo -e "\n--- ${YELLOW}上传新的 SSH 公钥${NC} ---"
        read -p "1. 请输入要保存的密钥名称 (例: my-macbook-key，不支持空格): " new_key_name
        if [[ -z "$new_key_name" ]]; then echo -e "${RED}名称不能为空！${NC}"; return 1; fi
        
        echo -e "2. 请粘贴您的 SSH 公钥内容 (通常以 ssh-rsa 或 ssh-ed25519 开头，按回车结束):"
        read -r pub_key_string
        if [[ -z "$pub_key_string" ]]; then echo -e "${RED}公钥内容不能为空！${NC}"; return 1; fi
        
        echo -e "${YELLOW}正在上传密钥到 $new_reg...${NC}"
        aws lightsail import-key-pair --region "$new_reg" --key-pair-name "$new_key_name" --public-key-base64 "$pub_key_string" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}密钥 [$new_key_name] 上传成功！${NC}"
            selected_key="$new_key_name"
            return 0
        else
            echo -e "${RED}密钥上传失败！可能是公钥格式不对，或者该名称已经存在。${NC}"
            return 1
        fi
    }

    if [[ -z "$keys" || "$keys" == "None" ]]; then
        echo -e "${YELLOW}提示：在当前地域 [$new_reg] 未找到任何已保存的 SSH 密钥。${NC}"
        read -p "AWS 要求必须绑定密钥。是否现在立即粘贴上传一个？(y/n): " up_choice
        if [[ "$up_choice" == "y" || "$up_choice" == "Y" ]]; then
            upload_new_key
            if [ $? -ne 0 ]; then read -n 1 -s -p "按任意键返回..."; return; fi
        else
            echo -e "${RED}必须配置 SSH 密钥才能创建实例。操作已取消。${NC}"
            read -n 1 -s -p "按任意键返回..."
            return
        fi
    else
        echo -e "${YELLOW}请选择要注入的 SSH 密钥:${NC}"
        for i in "${!key_array[@]}"; do echo "$((i+1)). ${key_array[$i]}"; done
        # 动态增加一个上传新密钥的选项
        upload_choice_num=$(( ${#key_array[@]} + 1 ))
        echo "${upload_choice_num}. [➕ 粘贴上传新公钥]"
        echo "0. 返回"
        read -p "请输入数字选择 [0-$upload_choice_num]: " key_choice
        
        if [[ "$key_choice" == "0" ]]; then return; fi
        if [[ "$key_choice" == "$upload_choice_num" ]]; then
            upload_new_key
            if [ $? -ne 0 ]; then read -n 1 -s -p "按任意键返回..."; return; fi
        elif (( key_choice >= 1 && key_choice <= ${#key_array[@]} )); then
            selected_key="${key_array[$((key_choice-1))]}"
        else
            echo -e "${RED}选择无效，返回菜单。${NC}"; return
        fi
    fi
    # ---- 密钥上传与选择逻辑结束 ----

    echo -e "\n=============================================="
    echo -e "即将创建实例："
    echo -e "名称: ${GREEN}$new_name${NC}"
    echo -e "地域: ${GREEN}$new_az${NC}"
    echo -e "系统: ${GREEN}$new_blueprint${NC}"
    echo -e "配置: ${GREEN}$new_bundle${NC}"
    echo -e "密钥: ${GREEN}$selected_key${NC}"
    echo -e "=============================================="
    read -p "确认执行创建操作吗？(y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}已取消创建。${NC}"
        sleep 1
        return
    fi
    
    echo -e "\n${YELLOW}正在向 AWS 发送创建指令...${NC}"
    aws lightsail create-instances --instance-names "$new_name" --availability-zone "$new_az" --blueprint-id "$new_blueprint" --bundle-id "$new_bundle" --key-pair-name "$selected_key" --region "$new_reg" > /dev/null 2>&1
    if [ $? -eq 0 ]; then 
        echo -e "${GREEN}实例 [$new_name] 创建任务已提交！请稍后重新扫描列表查看状态。${NC}"
    else 
        echo -e "${RED}创建失败，请检查参数或账户配额限制。${NC}"
    fi
    read -n 1 -s -p "按任意键返回上一级菜单..."
}

# ==========================================
# 5. 扫描实例与沉浸式操作菜单
# ==========================================
list_instances_and_manage() {
    regions="ap-northeast-1 ap-northeast-2 ap-southeast-1 ap-southeast-2 ap-south-1 us-east-1 us-east-2 us-west-2 eu-west-1 eu-west-2 eu-west-3 eu-central-1 eu-north-1 ca-central-1"
    > "$TEMP_INSTANCE_FILE"

    echo -e "\n${CYAN}正在扫描全球 Lightsail 实例 (获取流量数据较慢，请稍候)...${NC}"
    
    table_data="编号 | 实例名称 | 所在地区 | 状态 | IPv4 | IPv6 | 配置套餐 | 当月消耗 | 流量阈值(${ALERT_PERCENTAGE}%)\n"
    has_instances=false
    instance_count=0

    for reg in $regions; do
        instances=$(aws lightsail get-instances --region "$reg" --output json 2>/dev/null)
        if [[ $(echo "$instances" | jq '.instances | length') -gt 0 ]]; then
            has_instances=true
            
            while read -r row; do
                if [[ -z "$row" ]]; then continue; fi
                
                ((instance_count++))
                name=$(echo "$row" | jq -r '.name')
                state=$(echo "$row" | jq -r '.state.name')
                ipv4=$(echo "$row" | jq -r '.publicIpAddress // "无"')
                ipv6=$(echo "$row" | jq -r '.ipv6Addresses[0] // "无"')
                bundle=$(echo "$row" | jq -r '.bundleId')
                reg_name=$(get_region_name "$reg")
                
                echo "$instance_count:$name:$reg" >> "$TEMP_INSTANCE_FILE"
                
                start_time=$(date -u +"%Y-%m-01T00:00:00Z")
                end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                metrics=$(aws lightsail get-instance-metric-data --instance-name "$name" --metric-name "NetworkOut" --period 86400 --start-time "$start_time" --end-time "$end_time" --unit Bytes --statistics Sum --region "$reg" 2>/dev/null)
                total_bytes=$(echo "$metrics" | jq '[.metricData[].sum] | add // 0')
                used_gb=$(echo "scale=2; $total_bytes/1024/1024/1024" | bc)

                total_allowance_gb=$(get_bundle_allowance "$bundle")
                dynamic_threshold_gb=$(echo "$total_allowance_gb * $ALERT_PERCENTAGE / 100" | bc)

                table_data+="$instance_count | $name | $reg_name | $state | $ipv4 | $ipv6 | $bundle | ${used_gb} GB | ${dynamic_threshold_gb} GB\n"

                if (( $(echo "$used_gb >= $dynamic_threshold_gb" | bc -l) )); then
                    send_alert "⚠️ 【流量告警】\n实例: $name ($reg_name)\n套餐: $bundle (${total_allowance_gb}GB)\n消耗: ${used_gb} GB\n状态: 已达 ${ALERT_PERCENTAGE}% 告警线 (${dynamic_threshold_gb} GB)！" "$NOTIFY_CHANNEL"
                fi
            done <<< "$(echo "$instances" | jq -c '.instances[]')"
        fi
    done
    
    if [ "$has_instances" = true ]; then
        echo ""
        formatted_table=$(echo -e "$table_data" | column -t -s '|')
        echo "$formatted_table" | head -n 1
        echo "-------------------------------------------------------------------------------------------------------------------------------------------"
        echo "$formatted_table" | tail -n +2
    else
        echo -e "${YELLOW}未在当前账户下扫描到任何 Lightsail 实例。${NC}"
    fi
    
    while true; do
        echo -e "\n=== ${CYAN}实例操作菜单${NC} ==="
        echo "1. 开机 (Start)"
        echo "2. 关机 (Stop)"
        echo "3. 重启并换IP (Stop & Start)"
        echo "4. 删除实例 (Delete)"
        echo "5. 创建新实例 (Create)"
        echo "0. 返回主菜单"
        echo "======================"
        read -p "请选择对机器的操作 (输入数字): " sub_choice

        case $sub_choice in
            1|2|3|4)
                read -p "请输入要操作的 [机器编号 或 实例名称] (输入 0 取消): " inst_input
                if [[ "$inst_input" == "0" ]]; then continue; fi
                
                matched_line=$(awk -F':' -v input="$inst_input" '$1 == input || $2 == input {print $0; exit}' "$TEMP_INSTANCE_FILE")
                if [[ -z "$matched_line" ]]; then echo -e "${RED}找不到对应机器，请重试。${NC}"; continue; fi
                inst_name=$(echo "$matched_line" | cut -d':' -f2)
                inst_reg=$(echo "$matched_line" | cut -d':' -f3)

                case $sub_choice in
                    1) aws lightsail start-instance --instance-name "$inst_name" --region "$inst_reg" > /dev/null; echo -e "${GREEN}开机指令已发送！${NC}" ;;
                    2) aws lightsail stop-instance --instance-name "$inst_name" --region "$inst_reg" > /dev/null; echo -e "${GREEN}关机指令已发送！${NC}" ;;
                    3)
                        echo -e "${YELLOW}关机中(15秒)...${NC}"; aws lightsail stop-instance --instance-name "$inst_name" --region "$inst_reg" > /dev/null; sleep 15
                        echo -e "${YELLOW}开机中(10秒)...${NC}"; aws lightsail start-instance --instance-name "$inst_name" --region "$inst_reg" > /dev/null; sleep 10
                        new_ip=$(aws lightsail get-instance --instance-name "$inst_name" --region "$inst_reg" --query "instance.publicIpAddress" --output text)
                        echo -e "${GREEN}完成！新 IP 为: $new_ip${NC}" ;;
                    4)
                        read -p "警告：确定要彻底删除 [$inst_name] 吗？(y/n): " confirm
                        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                            aws lightsail delete-instance --instance-name "$inst_name" --region "$inst_reg" > /dev/null; echo -e "${GREEN}已删除！${NC}"
                        fi ;;
                esac
                ;;
            5) create_instance ;;
            0) break ;;
            *) echo -e "${RED}无效输入！${NC}" ;;
        esac
    done
}

# ==========================================
# 初始化与主菜单
# ==========================================
if ! command -v jq &> /dev/null; then echo -e "${RED}请先安装 jq${NC}"; exit 1; fi
export AWS_PAGER="" 

while true; do
    clear
    echo -e "=== ${CYAN}AWS Lightsail 自动化管理面板 (v11)${NC} ==="
    echo "1. 登录/切换 AWS 账户"
    echo "2. 扫描实例并进行管理 (开机/关机/换IP/删除/创建)"
    echo "3. 机器人通知与告警设置"
    echo "0. 退出脚本"
    echo "================================================="
    read -p "请输入对应数字选择功能: " choice

    case $choice in
        1) manage_account ;;
        2) list_instances_and_manage ;;
        3) setup_notifications ;;
        0) echo -e "${GREEN}已退出！${NC}"; exit 0 ;;
        *) echo -e "${RED}无效输入！${NC}"; sleep 1 ;;
    esac
done