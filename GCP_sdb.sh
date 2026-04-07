#!/bin/bash

# 配置变量
DISK_DEV="/dev/sdb"
MOUNT_POINT="/home/docker"

echo "--- 开始执行自动挂载脚本 ---"

# 1. 检查磁盘是否存在
if [ ! -b "$DISK_DEV" ]; then
    echo "错误: 未找到磁盘 $DISK_DEV，请确认设备名称是否正确。"
    exit 1
fi

# 2. 格式化磁盘 (ext4)
# 注意：这里加了 -F 强制格式化，请确保磁盘内无重要数据
echo "正在格式化 $DISK_DEV..."
sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard -F $DISK_DEV

# 3. 创建挂载点
echo "创建目录 $MOUNT_POINT..."
sudo mkdir -p $MOUNT_POINT

# 4. 获取磁盘 UUID
DISK_UUID=$(sudo blkid -s UUID -o value $DISK_DEV)
echo "磁盘 UUID 为: $DISK_UUID"

# 5. 写入 /etc/fstab 实现开机自启
# 先备份原有的 fstab 防止意外
sudo cp /etc/fstab /etc/fstab.bak
echo "已备份 fstab 到 /etc/fstab.bak"

# 检查是否已经配置过该 UUID，防止重复写入
if grep -q "$DISK_UUID" /etc/fstab; then
    echo "警告: $DISK_UUID 已经存在于 /etc/fstab 中，跳过写入。"
else
    echo "正在写入 /etc/fstab..."
    echo "UUID=$DISK_UUID $MOUNT_POINT ext4 discard,defaults 0 2" | sudo tee -a /etc/fstab
fi

# 6. 重新加载并执行挂载
echo "正在加载系统服务并挂载..."
sudo systemctl daemon-reload
sudo mount -a

# 7. 设置权限（方便 Docker 使用）
sudo chmod 777 $MOUNT_POINT

echo "--- 挂载完成！以下是当前磁盘状态 ---"
df -h | grep $MOUNT_POINT
