#!/bin/bash

# 1. 确保脚本以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以 root 权限运行。" 1>&2
    exit 1
fi

echo "开始配置 SSH：注入多个公钥、允许 Root 登录、禁用密码登录..."

# 2. 定义需要注入的公钥列表
PUB_KEYS=(
    "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA51NEd+1MywhVybvI2LVWMIS2pSwOGznIkEcxcjLI1oNw4j4xx7O95Nmap5Lk0tJd9rQ1Etxvmvdl3xsqwa8aS3gxeRve4R4XmDZOw1P+zK+L4zX2LRMEDO5PlWtqSMBBsl9bBsMFO3CtEPaJjP8w+rRpaR2S4Dx+1YJ9gLdmmfv8uvMvbrgA2/LeDdIKzDNJRgzydzSFCkDj1g3OvKnWWDjFdF53ESYhFyh8HKDasmH64r7udcSzoW4eMz9uGbW1KbYi0gBqm5g53pp23byYFtDzKzboKIOc+aNpL7OfyYELZio64YkIdp1vYT51h4rivwqjOPrKyxHUcSZ2sleUQw=="
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCk0bSnB28sJPaYGQ1QuVjdJKDctl6k6V10Hui5/B0phBEVnRhuPQEzn9p3t5wjA/PRNpcRyiknemXby6S6R2ad5L7/loZZU9Bfzcm57ew2ULG25tQ6lN1mSR6ROS6uBZDVicC5fc4RLgBAE4Ban+aBOA5uuKGjGTtvHv4EfGt+Xgn1ikUgD7yZHLWk0U0ISq09m9reObsT3+JJfqSf80AgskGgWuwc7y9n7PHtu/+u/ps8BkhWKzU5f4cJiVa8ELrpQ3ItWYk5hkQjMHMGB5PU1pIe7FKWfd9v93JqRSFZ6yXtP/s/0574x170D0DjHker/ABw5cX1c+yWtOZPkaAx AWS"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDMdwYVqG48ZMaGls8LKlZxZCWjnYUg/w53kLtw9RDTuyJru8QYDdTFs8INdOYJFUYBqkw+tA4SwMbc8k/0srJqn7QtuVp5D67h19NKbm4UOtz7O1BcJOIcn/R4ySbv/V8K1stEiqePCbLfGRynoFR5/FGZJxC4lY5QHS1mMFWF054+OI2m7D3XLc6iJHsB7vW+knEWEv9/77R70E4pAAfh0UMm899KNm4lrBjavr9yVQsQVZwkBtERD13yY6+YWCg7fp9dc5iSOsQ03w8WJWJ3EIHhrOVn9NmaFa1t31vf66GikOmavCYxvudnbb9+V4jVBFsr2L4TOp1jzz/qdWve8K0s9esjmsvh9B8CtbWCAt5WeOyXo8/ahpTYJbmHUGdQICV10ny21BlbNSyZd/gXLctNl2sXBNH4aO41gHVYZfXLmmvDnDiJlxSli1E2YyxuC1q27cyo5eYt99eZXrnOff+DxiRJGBLe6NH6V8Ac3ZobuLCil7oao9RARkSvtb0= Azure"
)

mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 循环写入公钥
for key in "${PUB_KEYS[@]}"; do
    grep -q -F "$key" /root/.ssh/authorized_keys 2>/dev/null || echo "$key" >> /root/.ssh/authorized_keys
done
chmod 600 /root/.ssh/authorized_keys
echo "-> 所有公钥已成功写入 /root/.ssh/authorized_keys"

# 3. 修改主 sshd_config 配置文件
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

# 3.5 核心新增：全面清理并修改 sshd_config.d 目录下的第三方干扰文件
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"
if [ -d "$SSHD_CONFIG_D" ]; then
    echo "-> 检测到存在 sshd_config.d 目录，正在清理可能覆盖主配置的子文件..."
    
    # 强制将该目录下所有 .conf 文件中的 PasswordAuthentication yes 改为 no
    # 同时将可能的 PermitRootLogin 冲突也一并纠正
    find "$SSHD_CONFIG_D" -type f -name "*.conf" | while read -r config_file; do
        # 备份子文件
        cp "$config_file" "${config_file}.bak_$(date +%F_%T)"
        
        # 强制修正密码验证和Root登录权限
        sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' "$config_file"
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/g' "$config_file"
        
        sed -i 's/PermitRootLogin.*/PermitRootLogin yes/g' "$config_file"
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/g' "$config_file"
        
        echo "   已处理子配置文件: $(basename "$config_file")"
    done
fi

# 4. 自动判断并重启 SSH 服务（增加对新版 Ubuntu socket 机制的支持）
echo "-> 正在重新加载并重启 SSH 服务..."

# 新版 Ubuntu 24.04+ 必须优先刷新 systemd daemon
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
echo "⚠️ 警告：请暂时不要关闭当前终端窗口！请立即新开一个本地终端，测试能否使用 'ssh -i 你的私钥路径 root@服务器IP' 成功登录。确认成功后再关闭当前窗口。"
