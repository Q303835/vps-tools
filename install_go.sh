#!/bin/bash

set -e

# ===== 配置 =====
INSTALL_ROOT="/usr/local"
USER_ROOT="$HOME/.local/go"
PROFILE_FILE="/etc/profile"
USER_PROFILE="$HOME/.bashrc"

# ===== 架构检测 =====
ARCH=$(uname -m)
case $ARCH in
    x86_64) GOARCH="amd64" ;;
    aarch64 | arm64) GOARCH="arm64" ;;
    *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
esac

# ===== 选择安装方式 =====
choose_install_path() {
    echo ""
    echo "安装方式："
    echo "1) 系统级安装 (/usr/local) [需要 sudo]"
    echo "2) 用户级安装 (~/.local/go)"
    read -p "选择 [1-2]: " MODE

    if [ "$MODE" == "1" ]; then
        INSTALL_DIR="$INSTALL_ROOT"
        PROFILE="$PROFILE_FILE"
        NEED_SUDO="sudo"
    else
        INSTALL_DIR="$USER_ROOT"
        PROFILE="$USER_PROFILE"
        NEED_SUDO=""
    fi
}

# ===== 获取版本列表 =====
get_versions() {
    echo "📡 获取 Go 版本列表..."
    curl -s https://go.dev/dl/ | grep -o 'go[0-9.]*\.linux-'$GOARCH'\.tar\.gz' | sed 's/\.linux.*//' | sort -Vr | uniq | head -n 10
}

# ===== 选择版本 =====
choose_version() {
    echo ""
    echo "可用版本（最新10个）："
    VERSIONS=($(get_versions))

    for i in "${!VERSIONS[@]}"; do
        echo "$((i+1))) ${VERSIONS[$i]}"
    done

    echo "0) 手动输入版本"
    read -p "选择版本: " NUM

    if [ "$NUM" == "0" ]; then
        read -p "输入版本号 (如 1.22.3): " GOVERSION
        GOVERSION="go$GOVERSION"
    else
        GOVERSION="${VERSIONS[$((NUM-1))]}"
    fi
}

# ===== 下载方式 =====
choose_mirror() {
    echo ""
    echo "下载源："
    echo "1) 官方 (go.dev)"
    echo "2) 国内加速 (golang.google.cn)"
    read -p "选择 [1-2]: " SRC

    FILE="${GOVERSION}.linux-${GOARCH}.tar.gz"

    if [ "$SRC" == "2" ]; then
        URL="https://golang.google.cn/dl/$FILE"
    else
        URL="https://go.dev/dl/$FILE"
    fi
}

# ===== 安装 =====
install_go() {
    choose_install_path
    choose_version
    choose_mirror

    echo ""
    echo "⬇️ 下载 $URL"
    wget -q --show-progress "$URL" -O /tmp/$FILE || {
        echo "❌ 下载失败"
        exit 1
    }

    TARGET_DIR="$INSTALL_DIR/$GOVERSION"

    echo "📦 安装到 $TARGET_DIR"
    $NEED_SUDO mkdir -p "$TARGET_DIR"
    $NEED_SUDO tar -C "$TARGET_DIR" --strip-components=1 -xzf /tmp/$FILE

    echo "🔗 设置当前版本"
    $NEED_SUDO ln -sfn "$TARGET_DIR" "$INSTALL_DIR/go"

    echo "🔧 配置 PATH"

    grep -q "$INSTALL_DIR/go/bin" "$PROFILE" || \
    echo "export PATH=\$PATH:$INSTALL_DIR/go/bin" >> "$PROFILE"

    source "$PROFILE" 2>/dev/null || true

    echo "🎉 安装完成："
    $INSTALL_DIR/go/bin/go version
}

# ===== 卸载 =====
uninstall_go() {
    choose_install_path

    echo ""
    echo "⚠️ 将删除所有 Go 版本！确认？(y/n)"
    read CONFIRM

    if [[ "$CONFIRM" != "y" ]]; then
        exit 0
    fi

    $NEED_SUDO rm -rf "$INSTALL_DIR/go" "$INSTALL_DIR"/go*

    sed -i '/go\/bin/d' "$PROFILE" 2>/dev/null || true

    echo "✅ 已卸载"
}

# ===== 切换版本 =====
switch_version() {
    choose_install_path

    echo ""
    echo "📂 已安装版本："
    ls "$INSTALL_DIR" | grep '^go[0-9]' || {
        echo "❌ 没有安装任何版本"
        exit 1
    }

    read -p "输入要切换的版本 (如 go1.22.3): " VER

    if [ ! -d "$INSTALL_DIR/$VER" ]; then
        echo "❌ 版本不存在"
        exit 1
    fi

    $NEED_SUDO ln -sfn "$INSTALL_DIR/$VER" "$INSTALL_DIR/go"

    echo "🔄 已切换"
    $INSTALL_DIR/go/bin/go version
}

# ===== 菜单 =====
echo ""
echo "====== Go 管理脚本 ======"
echo "1) 安装 Go"
echo "2) 卸载 Go"
echo "3) 切换版本"
echo ""

read -p "选择操作: " ACTION

case $ACTION in
    1) install_go ;;
    2) uninstall_go ;;
    3) switch_version ;;
    *) echo "❌ 无效操作" ;;
esac
