#!/bin/bash

# ==============================================================================
# 脚本名称: install_socks5.sh
# 描述: 一键在 Linux (Ubuntu/Debian/CentOS) 上安装并配置 Dante SOCKS5 代理服务器
# ==============================================================================

# 颜色定义
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 默认配置变量
PROXY_PORT=1080

echo -e "${YELLOW}=== 开始自动化安装 Dante SOCKS5 服务器 ===${NC}"

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 用户或通过 sudo 运行此脚本！${NC}"
    exit 1
fi

# 2. 自动检测操作系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}无法识别的操作系统类型，脚本退出。${NC}"
    exit 1
fi

# 3. 自动检测外网网卡接口名称
EXT_IFACE=$(ip -o link show | awk -F': ' '$3 !~ /lo/ && $3 ~ /UP/ {print $2}' | head -n 1)

if [ -z "$EXT_IFACE" ]; then
    EXT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
fi

if [ -z "$EXT_IFACE" ]; then
    echo -e "${RED}错误: 无法自动获取外网网卡名称，请手动检查网络配置！${NC}"
    exit 1
fi

echo -e "${GREEN}[+] 检测到操作系统:${NC} $OS"
echo -e "${GREEN}[+] 自动匹配外网网卡:${NC} $EXT_IFACE"
echo -e "${GREEN}[+] 准备部署代理端口:${NC} $PROXY_PORT"

# 4. 安装 Dante 软件
echo -e "${YELLOW}[*] 正在安装 Dante Server...${NC}"
case "$OS" in
    ubuntu|debian)
        apt-get update -y
        apt-get install dante-server -y
        wget http://ftp.debian.org/debian/pool/main/d/dante/dante-server_1.4.4+dfsg-1+b1_amd64.deb
        apt install ./dante-server_1.4.4+dfsg-1+b1_amd64.deb
        CONFIG_FILE="/etc/danted.conf"
        SERVICE_NAME="danted"
        ;;
    centos|rhel|almalinux|rocky)
        yum install epel-release -y
        yum install dante-server -y
        CONFIG_FILE="/etc/danted.conf"
        SERVICE_NAME="danted"
        ;;
    *)
        echo -e "${RED}暂不支持此操作系统发行版: $OS${NC}"
        exit 1
        ;;
esac

# 5. 备份并写入全新配置文件
echo -e "${YELLOW}[*] 正在配置 Dante 策略...${NC}"
if [ -f "$CONFIG_FILE" ]; then
    mv "$CONFIG_FILE" "${CONFIG_FILE}.bak"
fi

cat <<EOF > "$CONFIG_FILE"
logoutput: /var/log/danted.log

# 监听所有内网/外网 IP 请求
internal: 0.0.0.0 port = $PROXY_PORT

# 动态绑定的外部出口网卡
external: $EXT_IFACE

# 认证方式：使用系统用户名与密码
socksmethod: username
clientmethod: none

# 客户端连接权限控制
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

# 转发数据规则策略
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF

# 6. 配置代理账号（支持自定义、默认值与随机生成）
echo -e "${YELLOW}[*] 正在配置代理账号...${NC}"

# 6.1 处理用户名
echo -e "${YELLOW}请输入代理用户名 (直接回车将随机生成10位数字字母组合):${NC}"
read PROXY_USER

if [ -z "$PROXY_USER" ]; then
    # 随机生成10位大小写字母+数字
    PROXY_USER=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 10)
    echo -e "${GREEN}[+] 已自动生成10位用户名: ${NC}$PROXY_USER"
elif [ "$PROXY_USER" = "user" ]; then
    echo -e "${GREEN}[+] 使用默认用户名: ${NC}user"
fi

# 检查用户是否已存在，存在则先删除以确保干净
if id "$PROXY_USER" &>/dev/null; then
    echo -e "${YELLOW}提示: 用户 $PROXY_USER 已存在，正在更新其权限与密码...${NC}"
else
    useradd -r -s /bin/false "$PROXY_USER"
fi

# 6.2 处理密码
while true; do
    echo -e "${YELLOW}请输入密码 (直接回车将使用默认密码并启用随机生成机制):${NC}"
    echo -e "${YELLOW}注: 直接回车后，可选 [1] 使用固定默认密码 或 [2] 随机生成20位密码${NC}"
    read -s PROXY_PASS
    echo
    
    if [ -z "$PROXY_PASS" ]; then
        echo -e "${YELLOW}检测到留空，请选择预设动作:${NC}"
        echo -e "  ${GREEN}[1]${NC} 使用默认密码 (CAzfvHtTB4FcqHMdNqwD)"
        echo -e "  ${GREEN}[2]${NC} 随机生成 20 位复杂密码"
        read -p "请输入序号 (1-2, 默认2): " ACTION_CHOICE
        
        if [ "$ACTION_CHOICE" = "1" ]; then
            PROXY_PASS="CAzfvHtTB4FcqHMdNqwD"
            echo -e "${GREEN}[+] 已应用默认密码。${NC}"
        else
            PROXY_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)
            echo -e "${GREEN}[+] 已自动生成20位复杂密码。${NC}"
        fi
        break
    else
        # 如果用户手动输入了密码，进行二次确认
        echo -e "${YELLOW}请再次输入密码以确认:${NC}"
        read -s PROXY_PASS_CONFIRM
        echo
        if [ "$PROXY_PASS" = "$PROXY_PASS_CONFIRM" ]; then
            break
        else
            echo -e "${RED}两次输入的密码不一致，请重新配置！${NC}\n"
        fi
    fi
done

# 写入系统密码
echo "$PROXY_USER:$PROXY_PASS" | chpasswd
echo -e "${GREEN}[+] 代理账号 [$PROXY_USER] 配置成功。${NC}"

# 7. 重启并激活服务
echo -e "${YELLOW}[*] 正在启动 SOCKS5 服务...${NC}"
systemctl daemon-reload
systemctl restart "$SERVICE_NAME"
systemctl enable "$SERVICE_NAME"

# 8. 检查运行状态并输出连接信息
if systemctl is-active --quiet "$SERVICE_NAME"; then
    SERVER_IP=$(curl -s https://ifconfig.me || echo "你的服务器公网IP")
    
    echo -e "\n${GREEN}==================================================${NC}"
    echo -e "${GREEN}🎉 恭喜！Dante SOCKS5 一键安装并配置成功！${NC}"
    echo -e "${GREEN}==================================================${NC}"
    echo -e "🔗 ${YELLOW}代理连接信息（常规）：${NC}"
    echo -e "   - 服务器IP:   ${GREEN}$SERVER_IP${NC}"
    echo -e "   - 代理端口:   ${GREEN}$PROXY_PORT${NC}"
    echo -e "   - 认证用户名: ${GREEN}$PROXY_USER${NC}"
    echo -e "   - 认证密码:   ${GREEN}$PROXY_PASS${NC}"
    echo -e "--------------------------------------------------"
    echo -e "📦 ${YELLOW}指纹浏览器导入格式（IP:端口:账号:密码{备注}）：${NC}"
    echo -e "   ${SERVER_IP}:${PROXY_PORT}:${PROXY_USER}:${PROXY_PASS}{Dante代理}"
    echo -e "--------------------------------------------------"
    echo -e "💡 ${YELLOW}测试可用性命令（在其他机器执行）：${NC}"
    echo -e "   curl --socks5-hostname ${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:${PROXY_PORT} https://ifconfig.me"
    echo -e "--------------------------------------------------"
    echo -e "⚠️  ${RED}重要提醒：${NC}如果连接失败，请务必检查你的云厂商安全组/防火墙是否放行了 ${RED}$PROXY_PORT${NC} 端口（TCP）。"
else
    echo -e "${RED}❌ 错误: Dante 服务未能成功启动，请检查 /var/log/danted.log 查看错误日志。${NC}"
fi
