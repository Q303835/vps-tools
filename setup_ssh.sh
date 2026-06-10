#!/bin/bash

# 1. 确保脚本以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以 root 权限运行。" 1>&2
    exit 1
fi

echo "开始配置 SSH：清理云镜像拦截、规范目录、注入多个公钥、允许 Root 登录、禁用密码登录..."

# 2. 定义需要注入的公钥列表（已加入你的最新 ed25519 纯净公钥）
PUB_KEYS=(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKB4ddzNxWtYCXvzlvVEYeDM8rGpMcT9gR8nyRzKkhP5 lxy.me"
    "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA51NEd+1MywhVybvI2LVWMIS2pSwOGznIkEcxcjLI1oNw4j4xx7O95Nmap5Lk0tJd9rQ1Etxvmvdl3xsqwa8aS3gxeRve4R4XmDZOw1P+zK+L4zX2LRMEDO5PlWtqSMBBsl9bBsMFO3CtEPaJjP8w+rRpaR2S4Dx+1YJ9gLdmmfv8uvMvbrgA2/LeDdIKzDNJRgzydzSFCkDj1g3OvKnWWDjFdF53ESYhFyh8HKDasmH64r7udcSzoW4eMz9uGbW1KbYi0gBqm5g53pp23byYFtDzKzboKIOc+aNpL7OfyYELZio64YkIdp1vYT51h4rivwqjOPrKyxHUcSZ2sleUQw== Google"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCk0bSnB28sJPaYGQ1QuVjdJKDctl6k6V10Hui5/B0phBEVnRhuPQEzn9p3t5wjA/PRNpcRyiknemXby6S6R2ad5L7/loZZU9Bfzcm57ew2ULG25tQ6lN1mSR6ROS6uBZDVicC5fc4RLgBAE4Ban+aBOA5uuKGjGTtvHv4EfGt+Xgn1ikUgD7yZHLWk0U0ISq09m9reObsT3+JJfqSf80AgskGgWuwc7y9n7PHtu/+u/ps8BkhWKzU5f4cJiVa8ELrpQ3ItWYk5hkQjMHMGB5PU1pIe7FKWfd9v93JqRSFZ6yXtP/s/0574x170D0DjHker/ABw5cX1c+yWtOZPkaAx PEM-rsa-import-20260307-AWS"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDMdwYVqG48ZMaGls8LKlZxZCWjnYUg/w53kLtw9RDTuyJru8QYDdTFs8INdOYJFUYBqkw+tA4SwMbc8k/0srJqn7QtuVp5D67h19NKbm4UOtz7O1BcJOIcn/R4ySbv/V8K1stEiqePCbLfGRynoFR5/FGZJxC4lY5QHS1mMFWF054+OI2m7D3XLc6iJHsB7vW+knEWEv9/77R70E4pAAfh0UMm899KNm4lrBjavr9yVQsQVZwkBtERD13yY6+YWCg7fp9dc5iSOsQ03w8WJWJ3EIHhrOVn9NmaFa1t31vf66GikOmavCYxvudnbb9+V4jVBFsr2L4TOp1jzz/qdWve8K0s9esjmsvh9B8CtbWCAt5WeOyXo8/ahpTYJbmHUGdQICV10ny21BlbNSyZd/gXLctNl2sXBNH4aO41gHVYZfXLmmvDnDiJlxSli1E2YyxuC1q27cyo5eYt99eZXrnOff+DxiRJGBLe6NH6V8Ac3ZobuLCil7oao9RARkSvtb0= Azure"
)

AUTH_KEYS="/root/.ssh/authorized_keys"

# 3. 确保 /root 目录自身及 .ssh 权限规范（防止出现 bad ownership or modes 报错）
chmod 700 /root
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 4. 【关键修复 1】执行初始化清理：如果文件已存在，直接精准剔除云厂商整行强导向拦截命令
if [ -f "$AUTH_KEYS" ]; then
    sed -i '/Please login as the user/d' "$AUTH_KEYS"
    sed -i '/no-port-forwarding/d' "$AUTH_KEYS"
    echo "-> 已成功清除文件中可能存在的旧厂商拦截策略"
fi

# 5. 循环安全写入公钥（精确排重）
echo "-> 开始检查并注入公钥列表..."
for key in "${PUB_KEYS[@]}"; do
    # 提取备注，方便输出日志
    note=$(echo "$key" | awk '{print $NF}')
    
    # 检查该公钥是否已在文件中存在
    grep -q -F "$key" "$AUTH_KEYS" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "$key" >> "$AUTH_KEYS"
        echo "   [成功] 已写入公钥: $note"
    else
        echo "   [跳过] 公钥已存在: $note"
    fi
done

# 确保文件权限及所属权
chmod 600 "$AUTH_KEYS"
chown -R root:root /root/.ssh
echo "-> 密钥目录与权限规范化完毕"

# 6. 修改主 sshd_config 配置文件
SSHD_CONFIG="/etc/ssh/sshd_config"

# 备份原配置文件以防万一
cp $SSHD_CONFIG "${SSHD_CONFIG}.bak_$(date +%F_%T)"

# 允许 Root 登录 (替换或追加)
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' $SSHD_CONFIG
grep -q "^PermitRootLogin yes" $SSHD_CONFIG || echo "PermitRootLogin yes" >> $SSHD_CONFIG

# 禁用密码登录
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' $SSHD_CONFIG
grep -q "^PasswordAuthentication no" $SSHD_CONFIG || echo "PasswordAuthentication no" >> $SSHD_CONFIG

# 开启公钥登录
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' $SSHD_CONFIG
grep -q "^PubkeyAuthentication yes" $SSHD_CONFIG || echo "PubkeyAuthentication yes" >> $SSHD_CONFIG

echo "-> 主 SSH 配置文件修改完毕"

# 7. 【核心升级 2】强行清空子目录下的所有云配置干扰（不采用 sed 替换，避免漏掉顽固冲突）
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"
if [ -d "$SSHD_CONFIG_D" ]; then
    echo "-> 检测到存在 sshd_config.d 目录，正在强行清理并移除可能存在的子文件冲突..."
    
    # 将可能存在的配置全部移除并放入单独的备份夹，防止其高优先级覆盖主配置
    mkdir -p /etc/ssh/sshd_config_d_bak
    if ls "$SSHD_CONFIG_D"/*.conf &>/dev/null; then
        mv "$SSHD_CONFIG_D"/*.conf /etc/ssh/sshd_config_d_bak/ 2>/dev/null
        echo "   已清空并移走所有第三方子配置文件（已安全备份至 /etc/ssh/sshd_config_d_bak/）"
    fi
fi

# 8. 自动判断并重启 SSH 服务
echo "-> 正在重新加载并重启 SSH 服务..."

# 新版 Ubuntu 24.04+ 必须优先刷新 systemd daemon 并重启 socket
if systemctl list-units --type=socket | grep -q "ssh.socket"; then
    systemctl daemon-reload
    systemctl restart ssh.socket
    echo "-> 成功重启 ssh.socket (检测到新版托管机制)"
fi

# 传统的 service 状态检查与重启作为兜底/主服务重启
if systemctl is-active --quiet ssh; then
    systemctl restart ssh
    echo "-> 成功重启 ssh 服务"
elif systemctl is-active --quiet sshd; then
    systemctl restart sshd
    echo "-> 成功重启 sshd 服务"
else
    service ssh restart || service sshd restart
    echo "-> SSH 服务已通过 fallback 方式重启"
fi

echo ""
echo "✅ 配置全部完成！"
echo "⚠️ 警告：请暂时不要关闭当前终端窗口！请立即新开一个本地终端，测试能否使用新生成的 ED25519 私钥登录。"
