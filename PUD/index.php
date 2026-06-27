<?php
$decoded = null;
$error = null;
$pdu_input = '';

if ($_SERVER["REQUEST_METHOD"] == "POST" && !empty($_POST['pdu'])) {
    $pdu_input = trim($_POST['pdu']);
    
    // ⚠️ 关键配置：配置你的 Python 路径
    // 如果你之前使用了虚拟环境，必须写绝对路径，例如 '/root/venv/bin/python3'
    // 如果是全局安装的，直接用 'python3' 即可。
    $python_path = 'python3'; 
    $script_path = __DIR__ . '/pdu_api.py';
    
    // 使用 escapeshellarg 确保安全，防止恶意注入代码
    $command = escapeshellcmd("$python_path $script_path") . " " . escapeshellarg($pdu_input);
    
    // 执行后台调用
    $output = shell_exec($command);
    
    if ($output) {
        $response = json_decode($output, true);
        if (isset($response['success']) && $response['success']) {
            $decoded = $response;
        } else {
            $error = $response['error'] ?? "解析失败，可能 PDU 格式错误。";
        }
    } else {
        $error = "后台 Python 脚本执行失败，请检查 PHP 的 shell_exec 权限或 Python 路径。";
    }
}
?>

<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PDU 短信解码器</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background-color: #f4f4f9; color: #333; max-width: 800px; margin: 40px auto; padding: 0 20px; }
        h2 { color: #2c3e50; }
        .card { background: #fff; padding: 25px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); margin-bottom: 20px; }
        textarea { width: 100%; height: 120px; padding: 10px; border: 1px solid #ccc; border-radius: 4px; font-family: monospace; font-size: 14px; box-sizing: border-box; margin-bottom: 15px; }
        button { background: #3498db; color: #fff; border: none; padding: 10px 20px; font-size: 16px; border-radius: 4px; cursor: pointer; transition: background 0.3s; }
        button:hover { background: #2980b9; }
        .result-box { background: #e8f6f3; border-left: 4px solid #1abc9c; padding: 15px; margin-top: 20px; border-radius: 4px; }
        .error-box { background: #fdedec; border-left: 4px solid #e74c3c; padding: 15px; margin-top: 20px; color: #c0392b; border-radius: 4px; }
        .label { font-weight: bold; color: #7f8c8d; margin-top: 10px; display: block; font-size: 0.9em; }
        .value { font-size: 1.1em; margin-bottom: 10px; white-space: pre-wrap; word-break: break-all; }
    </style>
</head>
<body>

    <h2>📩 PDU 在线解码工具</h2>
    
    <div class="card">
        <form method="POST">
            <label for="pdu" style="display:block; margin-bottom:10px; font-weight:bold;">请输入模组返回的 PDU 数据:</label>
            <textarea name="pdu" id="pdu" placeholder="例如: 079144872000302324..."><?php echo htmlspecialchars($pdu_input); ?></textarea>
            <button type="submit">立即解码</button>
        </form>
    </div>

    <?php if ($decoded): ?>
        <div class="result-box">
            <span class="label">📱 发件人:</span>
            <div class="value"><?php echo htmlspecialchars($decoded['sender']); ?></div>
            
            <span class="label">⏰ 时间:</span>
            <div class="value"><?php echo htmlspecialchars($decoded['time']); ?></div>
            
            <span class="label">✉️ 正文内容:</span>
            <div class="value"><?php echo htmlspecialchars($decoded['content']); ?></div>
        </div>
    <?php endif; ?>

    <?php if ($error): ?>
        <div class="error-box">
            <strong>❌ 出错了:</strong> <?php echo htmlspecialchars($error); ?>
        </div>
    <?php endif; ?>

</body>
</html>