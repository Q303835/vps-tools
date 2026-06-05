#!/bin/bash

# 1. 确保脚本以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以 root 权限运行。请使用 sudo ./setup_ssh.sh" 1>&2
    exit 1
fi

echo "开始配置 SSH：注入公钥、允许 Root 登录、禁用密码登录..."

# 2. 注入你的公钥到 root 目录
PUB_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA51NEd+1MywhVybvI2LVWMIS2pSwOGznIkEcxcjLI1oNw4j4xx7O95Nmap5Lk0tJd9rQ1Etxvmvdl3xsqwa8aS3gxeRve4R4XmDZOw1P+zK+L4zX2LRMEDO5PlWtqSMBBsl9bBsMFO3CtEPaJjP8w+rRpaR2S4Dx+1YJ9gLdmmfv8uvMvbrgA2/LeDdIKzDNJRgzydzSFCkDj1g3OvKnWWDjFdF53ESYhFyh8HKDasmH64r7udcSzoW4eMz9uGbW1KbYi0gBqm5g53pp23byYFtDzKzboKIOc+aNpL7OfyYELZio64YkIdp1vYT51h4rivwqjOPrKyxHUcSZ2sleUQw=="

mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 将公钥追加写入（避免覆盖可能存在的其他有效密钥），并检查是否已存在
grep -q -F "$PUB_KEY" /root/.ssh/authorized_keys 2>/dev/null || echo "$PUB_KEY" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "-> 公钥已成功写入 /root/.ssh/authorized_keys"

# 3. 修改 sshd_config 配置文件
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

echo "-> SSH 配置文件已修改完毕"

# 4. 自动判断并重启 SSH 服务
if systemctl is-active --quiet ssh; then
    systemctl restart ssh
    echo "-> SSH 服务 (ssh) 已重启"
elif systemctl is-active --quiet sshd; then
    systemctl restart sshd
    echo "-> SSH 服务 (sshd) 已重启"
else
    service ssh restart || service sshd restart
    echo "-> SSH 服务已通过 fallback 方式重启"
fi

echo ""
echo "✅ 配置全部完成！"
echo "⚠️ 警告：请暂时不要关闭当前终端窗口！请立即新开一个本地终端，测试能否使用 'ssh -i 你的私钥路径 root@服务器IP' 成功登录。确认成功后再关闭当前窗口。"
