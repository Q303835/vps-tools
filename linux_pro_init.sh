#!/bin/bash

# ====================================================
# 脚本名称: linux_pro_init.sh
# 包含工具: BBR, Zsh, Oh My Zsh, Tmux, Docker, Git, btop
# ====================================================

set -e

echo "🌟 开始部署全能 Linux 学习环境..."

# 1. 基础包安装
echo "--- 1/6 更新并安装基础工具 (Git/Tmux/btop) ---"
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget zsh tmux btop ufw

# 2. 网络优化 (BBR)
echo "--- 2/6 开启内核 BBR 加速 ---"
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
fi

# 3. Docker 安装
echo "--- 3/6 安装 Docker 环境 ---"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | bash
    # 允许当前用户免 sudo 运行 docker
    sudo usermod -aG docker $USER || true
fi

# 4. Oh My Zsh 核心安装
echo "--- 4/6 安装 Oh My Zsh ---"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    # --unattended 参数防止脚本卡在询问界面
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# 5. 插件增强 (自动补全 & 语法高亮)
echo "--- 5/6 配置 Zsh 增强插件 ---"
ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

# 自动补全
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && \
git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions

# 语法高亮
[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && \
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting

# 6. 自动修改配置文件
echo "--- 6/6 激活配置 ---"
# 修改插件列表，加入 docker, tmux, git 等自带插件和刚才下载的增强插件
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting docker tmux)/' ~/.zshrc

# 解决第一次进入 zsh 的提示
touch ~/.zshrc

echo "===================================================="
echo "✅ 全部工具安装完成！"
echo "👉 请输入 'zsh' 立即进入增强版终端"
echo "===================================================="
