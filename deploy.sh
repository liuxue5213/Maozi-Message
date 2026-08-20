#!/bin/bash
# 帽子留言 - 后端部署脚本
# 用法: ./deploy.sh

SERVER="root@120.48.13.152"
REMOTE_DIR="/root/maozi-message"
BACKEND_DIR="$(dirname "$0")/backend"

echo "🚀 开始部署后端到服务器..."

# 1. 在服务器上创建目录
echo "📁 创建远程目录..."
ssh $SERVER "mkdir -p $REMOTE_DIR"

# 2. 上传后端代码
echo "📤 上传后端文件..."
scp -r $BACKEND_DIR/* $SERVER:$REMOTE_DIR/

# 3. 在服务器上安装依赖并启动
echo "⚙️  安装依赖并启动服务..."
ssh $SERVER "cd $REMOTE_DIR && \
  npm install --production && \
  mkdir -p data && \
  (pm2 stop maozi-message 2>/dev/null || true) && \
  pm2 start server.js --name maozi-message --env production && \
  pm2 save && \
  echo '✅ 服务已启动'"

# 4. 设置 Nginx 反向代理（如果尚未配置）
echo "🌐 配置 Nginx..."
ssh $SERVER "if [ ! -f /etc/nginx/sites-available/maozi-message ]; then
  cat > /etc/nginx/sites-available/maozi-message << 'NGINX'
server {
    listen 60170;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:60175;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}

server {
    listen 60175;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:60175;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX
  ln -sf /etc/nginx/sites-available/maozi-message /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx
  echo '✅ Nginx 已配置'
else
  echo 'ℹ️  Nginx 配置已存在，跳过'
fi"

echo ""
echo "🎉 部署完成！"
echo "📺 Web弹幕页: http://120.48.13.152:60170"
echo "📡 API地址: http://120.48.13.152:60175/api"
echo "❤️  健康检查: http://120.48.13.152:60175/health"
