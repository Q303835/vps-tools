#!/bin/bash

# 确保脚本在遇到错误时立即停止执行
set -e

# 定义颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

echo -e "${BLUE}=== 开始安装 Dockge ===${NC}"

# 1. 权限检查（Dockge 及 Docker 操作通常需要 root 权限）
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}提示: 请使用 sudo 或 root 用户运行此脚本。${NC}"
    exit 1
fi

# 2. 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}错误: 未检测到 Docker，请先安装 Docker 再运行此脚本。${NC}"
    exit 1
fi

# 3. 创建 Stacks 目录和 Dockge 的数据目录
echo -e "${BLUE}正在创建目录...${NC}"
# 默认 Stacks 目录: /opt/stacks
# Dockge 自身配置目录: /opt/dockge
mkdir -p /opt/stacks /opt/dockge

# 4. 进入 Dockge 工作目录
cd /opt/dockge

# 5. 下载 compose.yaml
echo -e "${BLUE}正在从 GitHub 下载 compose.yaml...${NC}"
curl -sSL https://raw.githubusercontent.com/louislam/dockge/master/compose.yaml --output compose.yaml

# 6. 启动 Dockge 服务
echo -e "${BLUE}正在启动 Dockge 容器...${NC}"

# 优先使用现代的 'docker compose'，如果不支持则尝试旧版 'docker-compose'
if docker compose version &> /dev/null; then
    docker compose up -d
elif command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}检测到旧版 docker-compose，正在使用旧版命令启动...${NC}"
    docker-compose up -d
else
    echo -e "${YELLOW}未找到 docker compose 命令，请检查 Docker Compose 是否正确安装。${NC}"
    exit 1
fi

echo -e "${GREEN}=== Dockge 安装并启动成功！ ===${NC}"
echo -e "${GREEN}默认端口: 5001${NC}"
echo -e "${GREEN}默认 Stacks 目录: /opt/stacks${NC}"
