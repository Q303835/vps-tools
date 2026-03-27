#!/bin/bash

set -e

# ===== 基础变量 =====
GO_INSTALL_DIR="/usr/local/go"
PROFILE_FILE="/etc/profile"

# ===== 检测架构 =====
ARCH=$(uname -m)

case $ARCH in
    x86_64)
        GOARCH="amd64"
        ;;
    aarch64 | arm64)
        GOARCH="arm64"
        ;;
    *)
        echo "❌ 不支持的架构: $ARCH"
        exit 1
        ;;
esac

echo "✅ 当前架构: $GOARCH"

# ===== 功能菜单 =====
echo ""
echo "请选择操作："
echo "1) 安装 Go"
echo "2) 卸载 Go"
read -p "输入选项 [1-2]: " ACTION

# ===== 卸载函数 =====
uninstall_go() {
    echo "🗑️ 正在卸载 Go..."

    rm -rf $GO_INSTALL_DIR

    # 删除环境变量
    sed -i '/\/usr\/local\/go\/bin/d' $PROFILE_FILE

    echo "✅ Go 已卸载完成"
}

# ===== 安装函数 =====
install_go() {
    read -p "请输入要安装的 Go 版本 (例如 1.22.3): " GOVERSION

    if [ -z "$GOVERSION" ]; then
        echo "❌ 版本不能为空"
        exit 1
    fi

    FILE_NAME="go${GOVERSION}.linux-${GOARCH}.tar.gz"
    DOWNLOAD_URL="https://go.dev/dl/${FILE_NAME}"

    echo "⬇️ 下载: $DOWNLOAD_URL"

    wget -q --show-progress $DOWNLOAD_URL -O /tmp/$FILE_NAME || {
        echo "❌ 下载失败，请检查版本号"
        exit 1
    }

    echo "🧹 清理旧版本..."
    rm -rf $GO_INSTALL_DIR

    echo "📦 解压安装..."
    tar -C /usr/local -xzf /tmp/$FILE_NAME

    echo "🔧 配置环境变量..."

    # 避免重复写入
    grep -q "/usr/local/go/bin" $PROFILE_FILE || echo "export PATH=\$PATH:/usr/local/go/bin" >> $PROFILE_FILE

    source $PROFILE_FILE

    echo "🎉 安装完成！"
    go version
}

# ===== 执行 =====
case $ACTION in
    1)
        install_go
        ;;
    2)
        uninstall_go
        ;;
    *)
        echo "❌ 无效选项"
        exit 1
        ;;
esac
