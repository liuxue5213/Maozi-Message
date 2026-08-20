const express = require('express');
const rateLimit = require('express-rate-limit');
const cors = require('cors');
const path = require('path');
const { WebSocketServer } = require('ws');
const http = require('http');
const messagesRouter = require('./routes/messages');
const authRouter = require('./routes/auth');

const app = express();
const PORT = 60175;

// 创建 HTTP 服务（WebSocket 需要）
const server = http.createServer(app);

// WebSocket 服务
const wss = new WebSocketServer({ server, path: '/ws' });

// WebSocket 广播：新留言、新回复、投票更新
function broadcast(type, data) {
  const msg = JSON.stringify({ type, data });
  wss.clients.forEach(client => {
    if (client.readyState === 1) { // WebSocket.OPEN
      client.send(msg);
    }
  });
}

// 导出 broadcast 给 routes 使用
app.set('wsBroadcast', broadcast);

wss.on('connection', (ws) => {
  console.log('🔌 WebSocket 客户端已连接');
  ws.on('close', () => console.log('❌ WebSocket 客户端已断开'));
});

// 中间件
app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// 速率限制
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,   // 1 分钟
  max: 60,                // 普通接口最多 60 次
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: '请求过于频繁，稍后再试' },
});

const postLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,                // 发布/回复/投票最多 20 次/分钟
  message: { success: false, error: '操作过于频繁，稍后再试' },
});

// API 路由（挂载限速中间件）
app.use('/api/auth', authRouter);
app.use('/api', apiLimiter, messagesRouter);

// 对发布/回复/投票接口额外限速
app.use('/api/messages', postLimiter);
app.use('/api/replies', postLimiter);

// 静态文件服务（Web前端弹幕页）
app.use(express.static(path.join(__dirname, 'public')));

// 健康检查
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// 兜底：所有未匹配的前端路由返回页面
app.get('*', (req, res) => {
  if (req.path.startsWith('/api')) {
    return res.status(404).json({ success: false, error: 'API 不存在' });
  }
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 猫子留言后端服务已启动: http://localhost:${PORT}`);
  console.log(`📺 弹幕展示页: http://localhost:${PORT}`);
  console.log(`📡 API 地址: http://localhost:${PORT}/api`);
  console.log(`🔌 WebSocket: ws://localhost:${PORT}/ws`);
});
