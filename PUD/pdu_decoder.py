import sys

# 启动时检查是否安装了依赖库，并引入正确的解码模块
try:
    from smspdudecoder.easy import read_incoming_sms
except ImportError:
    print("❌ 启动失败：未找到 'smspdudecoder' 库。")
    sys.exit(1)

def main():
    print("=" * 45)
    print("🚀 SMS PDU 交互式解码器已启动 (修复版)")
    print("💡 提示: 直接粘贴 PDU 字符串并回车。输入 'q' 退出。")
    print("=" * 45)

    while True:
        try:
            # 接收用户输入并去除首尾空格
            pdu_input = input("\n📝 请输入 PDU (输入 q 退出) > ").strip()
            
            # 处理空输入
            if not pdu_input:
                continue
                
            # 退出指令
            if pdu_input.lower() in ['q', 'quit', 'exit']:
                print("👋 感谢使用，已退出。")
                break
                
            print("⏳ 正在解码...")
            
            # 使用正确的 API 进行解码
            decoded_data = read_incoming_sms(pdu_input)
            
            # 美化输出结果
            print("\n✅ 解码成功！")
            print("-" * 40)
            print(f"📱 发 件 人 : {decoded_data.get('sender', '未知')}")
            
            # 格式化时间输出 (如果不做处理，默认会带有时区对象)
            date_info = decoded_data.get('date')
            date_str = date_info.strftime('%Y-%m-%d %H:%M:%S') if date_info else '未知'
            print(f"⏰ 发送时间 : {date_str}")
            
            print(f"✉️ 短信内容 :\n{decoded_data.get('content', '无正文')}")
            print("-" * 40)

        except Exception as e:
            # 捕获解码过程中的错误
            print(f"\n❌ 解码失败！请检查 PDU 码是否复制完整。")
            print(f"   错误详情: {e}")

if __name__ == "__main__":
    # 捕获 Ctrl+C 中断，防止抛出难看的堆栈报错
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n👋 检测到中断信号，已退出程序。")
        sys.exit(0)
