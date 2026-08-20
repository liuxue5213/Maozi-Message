#!/bin/bash
# 使用 expect 自动输入密码部署
SERVER="root@120.48.13.152"
PASSWORD="liuxue5213"
REMOTE_DIR="/root/maozi-message"
BACKEND_DIR="$(cd "$(dirname "$0")/backend" && pwd)"

echo "🚀 开始部署..."

# 1. 创建远程目录
expect <<EOF
spawn ssh -o StrictHostKeyChecking=no $SERVER "mkdir -p $REMOTE_DIR/data"
expect {
  "password:*" { send "$PASSWORD\r"; exp_continue }
  eof
}
EOF
echo "📁 目录已创建"

# 2. 打包本地文件
cd "$BACKEND_DIR"
tar czf /tmp/maozi-backend.tar.gz --exclude='node_modules' --exclude='data.db' .
echo "📦 已打包"

# 3. 上传压缩包
expect <<EOF
spawn scp -o StrictHostKeyChecking=no /tmp/maozi-backend.tar.gz $SERVER:$REMOTE_DIR/
expect {
  "password:*" { send "$PASSWORD\r"; exp_continue }
  eof
}
EOF
echo "📤 压缩包已上传"

# 4. 远程解压、安装、启动
expect <<EOF
set timeout 60
spawn ssh -o StrictHostKeyChecking=no $SERVER
expect {
  "password:*" { send "$PASSWORD\r"; exp_continue }
  "#" {}
}
send "cd $REMOTE_DIR && tar xzf maozi-backend.tar.gz && rm maozi-backend.tar.gz\r"
expect "#"
send "cd $REMOTE_DIR && npm install --production 2>&1 | tail -10\r"
expect "#"
send "pm2 stop maozi-message 2>/dev/null; pm2 delete maozi-message 2>/dev/null; pm2 start $REMOTE_DIR/server.js --name maozi-message\r"
expect "#"
send "pm2 save\r"
expect "#"
send "sleep 2 && curl -s http://localhost:60175/health\r"
expect "#"
send "exit\r"
expect eof
EOF

rm -f /tmp/maozi-backend.tar.gz
echo ""
echo "🎉 部署完成！"
echo "📺 Web弹幕页: http://120.48.13.152:60170"
echo "📡 API地址: http://120.48.13.152:60175/api"
echo "❤️  健康检查: http://120.48.13.152:60175/health"
