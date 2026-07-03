#!/bin/bash

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 权限运行此脚本 (sudo bash setup_netboot.sh)"
  exit 1
fi

echo "=== 开始配置 netboot.xyz 救援系统 ==="

# 1. 检测架构并下载对应的 EFI 文件
ARCH=$(uname -m)
mkdir -p /boot/efi/EFI/netboot

if [ "$ARCH" = "x86_64" ]; then
    echo "✅ 检测到 AMD (x86_64) 架构，正在下载引导文件..."
    wget -q -O /boot/efi/EFI/netboot/netboot.xyz.efi https://boot.netboot.xyz/ipxe/netboot.xyz.efi
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    echo "✅ 检测到 ARM (aarch64) 架构，正在下载引导文件..."
    wget -q -O /boot/efi/EFI/netboot/netboot.xyz.efi https://boot.netboot.xyz/ipxe/netboot.xyz-arm64.efi
else
    echo "❌ 未知的系统架构: $ARCH，脚本中止。"
    exit 1
fi

# 2. 写入 GRUB 菜单 (先清理旧配置防重复)
echo "✅ 正在配置 GRUB 引导菜单..."
sed -i '/netboot.xyz Rescue System/d' /etc/grub.d/40_custom
sed -i '/search --no-floppy --set=root --file \/EFI\/netboot\/netboot.xyz.efi/d' /etc/grub.d/40_custom
sed -i '/chainloader \/EFI\/netboot\/netboot.xyz.efi/d' /etc/grub.d/40_custom

cat << 'INNER_EOF' >> /etc/grub.d/40_custom
menuentry 'netboot.xyz Rescue System' {
    search --no-floppy --set=root --file /EFI/netboot/netboot.xyz.efi
    chainloader /EFI/netboot/netboot.xyz.efi
}
INNER_EOF

# 3. 修改 GRUB 倒计时，强制显示菜单
echo "✅ 正在修改 GRUB 显示设置 (强制显示菜单并等待 10 秒)..."
sed -i 's/GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/g' /etc/default/grub
sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=10/g' /etc/default/grub

# 针对云镜像的特殊文件处理
if [ -f /etc/default/grub.d/50-cloudimg-settings.cfg ]; then
    echo "✅ 检测到云镜像专属配置文件，正在覆盖倒计时限制..."
    sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=10/g' /etc/default/grub.d/50-cloudimg-settings.cfg
fi

# 4. 更新系统引导记录
echo "✅ 正在更新系统引导记录 (update-grub)..."
update-grub > /dev/null 2>&1

echo "========================================"
echo "🎉 配置完成！"
echo "下一次重启时，你可以在控制台拦截 10 秒的 GRUB 菜单，进入急救系统。"
echo "========================================"
