import sys
import json

try:
    from smspdudecoder.easy import read_incoming_sms
except ImportError:
    print(json.dumps({"success": False, "error": "未找到 smspdudecoder 库"}))
    sys.exit(1)

def main():
    # 检查是否传入了参数
    if len(sys.argv) < 2:
        print(json.dumps({"success": False, "error": "没有收到 PDU 数据"}))
        return

    pdu_input = sys.argv[1].strip()
    
    try:
        decoded_data = read_incoming_sms(pdu_input)
        
        date_info = decoded_data.get('date')
        date_str = date_info.strftime('%Y-%m-%d %H:%M:%S') if date_info else '未知时间'
        
        # 将结果打包成 JSON 返回给 PHP
        result = {
            "success": True,
            "sender": decoded_data.get('sender', '未知'),
            "time": date_str,
            "content": decoded_data.get('content', '无正文')
        }
        print(json.dumps(result))
        
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))

if __name__ == "__main__":
    main()