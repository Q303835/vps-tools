#!/bin/bash

# ==============================================================================
# 脚本名称: install_socks5.sh
# 描述: 一键在 Linux 上安装、配置或彻底卸载 Dante SOCKS5 代理服务器
# 使用方法:
#   sudo ./install_socks5.sh             -> 进入交互菜单
#   sudo ./install_socks5.sh --uninstall -> 快捷一键卸载
# ==============================================================================

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 默认配置变量
PROXY_PORT=1080
PROXY_USER="proxyuser"
CONFIG_FILE="/etc/danted.conf"
SERVICE_NAME="danted"

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

# ==================== 安装函数 ====================
do_install() {
    echo -e "${YELLOW}=== 开始自动化安装 Dante SOCKS5 服务器 ===${NC}"

    # 自动检测外网网卡接口名称
    EXT_IFACE=$(ip -o link show | awk -F': ' '$3 !~ /lo/ && $3 ~ /UP/ {print $2}' | head -n 1)
    if [ -z "$EXT_IFACE" ]; then
        EXT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
    fi

    if [ -z "$EXT_IFACE" ]; then
        echo -e "${RED}错误: 无法自动获取外网网卡名称，请检查网络配置！${NC}"
        exit 1
    fi

    echo -e "${GREEN}[+] 检测到操作系统:${NC} $OS"
    echo -e "${GREEN}[+] 自动匹配外网网卡:${NC} $EXT_IFACE"
    echo -e "${GREEN}[+] 准备部署代理端口:${NC} $PROXY_PORT"

    # 安装 Dante 软件
    echo -e "${YELLOW}[*] 正在安装 Dante Server...${NC}"
    case "$OS" in
        ubuntu|debian)
            apt-get update -y
            apt-get install dante-server -y
            ;;
        centos|rhel|almalinux|rocky)
            yum install epel-release -y
            yum install dante-server -y
            ;;
        *)
            echo -e "${RED}暂不支持此操作系统发行版: $OS${NC}"
            exit 1
            ;;
    esac

    # 备份并写入全新配置文件
    echo -e "${YELLOW}[*] 正在配置 Dante 策略...${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        mv "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    fi

    cat <<EOF > "$CONFIG_FILE"
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $PROXY_PORT
external: $EXT_IFACE
socksmethod: username
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF

    # 创建专用的代理用户
    echo -e "${YELLOW}[*] 正在创建代理专用账号...${NC}"
    if id "$PROXY_USER" &>/dev/null; then
        echo -e "${YELLOW}提示: 用户 $PROXY_USER 已存在，将直接重置其密码。${NC}"
    else
        useradd -r -s /bin/false "$PROXY_USER"
    fi

    # 交互式安全设置密码
    while true; do
        echo -e "${YELLOW}请输入要为代理用户 [$PROXY_USER] 设置的密码:${NC}"
        read -s PROXY_PASS
        echo
        echo -e "${YELLOW}请再次输入密码以确认:${NC}"
        read -s PROXY_PASS_CONFIRM
        echo
        if [ "$PROXY_PASS" = "$PROXY_PASS_CONFIRM" ] && [ -n "$PROXY_PASS" ]; then
            break
        else
            echo -e "${RED}两次输入的密码不一致或密码为空，请重新输入！${NC}"
        fi
    done

    echo "$PROXY_USER:$PROXY_PASS" | chpasswd
    echo -e "${GREEN}[+] 代理账号创建并配置成功。${NC}"

    # 重启并激活服务
    echo -e "${YELLOW}[*] 正在启动 SOCKS5 服务...${NC}"
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    systemctl enable "$SERVICE_NAME"

    # 检查运行状态
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        SERVER_IP=$(curl -s https://ifconfig.me || echo "你的服务器公网IP")
        echo -e "\n${GREEN}==================================================${NC}"
        echo -e "${GREEN}🎉 恭喜！Dante SOCKS5 一键安装并配置成功！${NC}"
        echo -e "${GREEN}==================================================${NC}"
        echo -e "🔗 ${YELLOW}代理连接信息：${NC}"
        echo -e "   - 服务器IP:   ${GREEN}$SERVER_IP${NC}"
        echo -e "   - 代理端口:   ${GREEN}$PROXY_PORT${NC}"
        echo -e "   - 认证用户名: ${GREEN}$PROXY_USER${NC}"
        echo -e "--------------------------------------------------"
        echo -e "💡 ${YELLOW}测试可用性命令（在其他机器执行）：${NC}"
        echo -e "   curl --socks5-hostname $PROXY_USER:你的密码@$SERVER_IP:$PROXY_PORT https://ifconfig.me"
        echo -e "=================================================="
    else
        echo -e "${RED}❌ 错误: Dante 服务未能成功启动，请检查日志。${NC}"
    fi
}

# ==================== 卸载函数 ====================
do_uninstall() {
    echo -e "${YELLOW}=== 开始卸载 Dante SOCKS5 服务器 ===${NC}"
    
    # 1. 停止并禁用服务
    echo -e "${YELLOW}[*] 正在停止并禁用 Dante 服务...${NC}"
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    
    # 2. 卸载安装包
    echo -e "${YELLOW}[*] 正在移除 Dante 软件包及依赖...${NC}"
    case "$OS" in
        ubuntu|debian)
            apt-get purge dante-server -y 2>/dev/null
            apt-get autoremove -y 2>/dev/null
            ;;
        centos|rhel|almalinux|rocky)
            yum remove dante-server -y 2>/dev/null
            ;;
    esac

    # 3. 删除遗留的配置与日志文件
    echo -e "${YELLOW}[*] 正在清理配置文件和日志...${NC}"
    rm -f "$CONFIG_FILE" "${CONFIG_FILE}.bak" 2>/dev/null
    rm -f /var/log/danted.log 2>/dev/null

    # 4. 删除专有代理用户
    if id "$PROXY_USER" &>/dev/null; then
        echo -e "${YELLOW}[*] 正在删除专有代理用户 [$PROXY_USER]...${NC}"
        userdel "$PROXY_USER" 2>/dev/null
    fi

    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}🎉 卸载完成！Dante SOCKS5 服务及相关配置已彻底清除！${NC}"
    echo -e "${GREEN}==================================================${NC}"
}

# ==================== 主流程控制 ====================
# 支持通过命令行参数直接卸载: ./install_socks5.sh -u 或 --uninstall
if [ "$1" = "-u" ] || [ "$1" = "--uninstall" ]; then
    do_uninstall
    exit 0
fi

# 交互式菜单
echo -e "${GREEN}欢迎使用 Dante SOCKS5 一键管理脚本${NC}"
echo -e "1. 安装 SOCKS5 服务"
echo -e "2. 彻底卸载 SOCKS5 服务"
read -p "请选择操作 [1-2]: " CHOICE

case "$CHOICE" in
    1)
        do_install
        ;;
    2)
        do_uninstall
        ;;
    *)
        echo -e "${RED}无效选择，脚本退出。${NC}"
        exit 1
        ;;
esac