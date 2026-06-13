#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 权限或 sudo 运行此脚本！"
  exit 1
fi  # 🛠️ 修复：这里之前错打成了 Dil

echo "=========================================="
echo "          开始安装 Docker & Compose        "
echo "=========================================="

# 1. 检测系统架构与发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "❌ 无法检测到操作系统类型"
    exit 1
fi

echo "ℹ️ 检测到系统类型: $OS"

# 2. 安装必要的基础依赖并配置官方源
case "$OS" in
    ubuntu|debian)
        echo "🔄 正在更新系统软件包并安装依赖..."
        apt-get update -y && apt-get install -y ca-certificates curl gnupg lsb-release
        
        echo "🔑 正在添加 Docker 官方 GPG 密钥..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -y --yes -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo "✍️ 正在添加 Docker 软件源..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        echo "🔄 再次更新源并安装 Docker..."
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
        
    centos|rhel|rocky|almalinux)
        echo "🔄 正在安装 yum-utils 依赖..."
        yum install -y yum-utils
        
        echo "✍️ 正在添加 Docker 软件源..."
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        
        echo "🔄 正在安装 Docker..."
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
        
    *)
        echo "❌ 暂不支持当前操作系统: $OS"
        exit 1
        ;;
esac

# 3. 启动 Docker 并设置开机自启
echo "⚙️ 正在启动 Docker 服务..."
systemctl start docker
systemctl enable docker

# 4. 配置海外环境优化参数 (去掉国内镜像源，保留日志限流，防止爆盘)
echo "🚀 正在配置 Docker 优化参数..."
mkdir -p /etc/docker
cat <<EOF | tee /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  }
}
EOF

# 重启守护进程和 Docker 使配置生效
systemctl daemon-reload
systemctl restart docker

echo "------------------------------------------"
echo "✅ Docker 和 Docker Compose 安装完成！"
echo "------------------------------------------"
echo "🐳 Docker 版本:" && docker --version
echo "🐙 Compose 版本:" && docker compose version
echo "=========================================="
