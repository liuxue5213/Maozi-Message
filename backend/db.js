const Database = require('better-sqlite3');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const crypto = require('crypto');

const db = new Database(path.join(__dirname, 'data.db'));

// 启用 WAL 模式提升并发性能
db.pragma('journal_mode = WAL');
// 启用外键约束（ON DELETE CASCADE 需要）
db.pragma('foreign_keys = ON');

// 初始化数据库表
db.exec(`
  -- 留言表
  CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    author_name TEXT DEFAULT '匿名',
    author_id TEXT,
    color TEXT DEFAULT '#ffffff',
    bg_color TEXT DEFAULT 'rgba(0,0,0,0.6)',
    mood TEXT DEFAULT 'neutral',
    is_anonymous INTEGER DEFAULT 1,
    replies_count INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    expire_at TEXT,
    is_pinned INTEGER DEFAULT 0,
    deleted_at TEXT
  );

  -- 回复表
  CREATE TABLE IF NOT EXISTS replies (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    content TEXT NOT NULL,
    author_name TEXT DEFAULT '匿名',
    author_id TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT,
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
  );

  -- 用户投票表（记录谁对哪条留言投了什么票）
  CREATE TABLE IF NOT EXISTS votes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target_type TEXT NOT NULL CHECK(target_type IN ('message', 'reply')),
    target_id TEXT NOT NULL,
    user_fingerprint TEXT NOT NULL,
    vote_type TEXT NOT NULL CHECK(vote_type IN ('like', 'dislike')),
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(target_type, target_id, user_fingerprint)
  );

  -- 用户表
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    nickname TEXT NOT NULL,
    avatar_color TEXT DEFAULT '#48dbfb',
    created_at TEXT DEFAULT (datetime('now'))
  );

  -- 创建索引加速查询
  CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_messages_expire ON messages(expire_at);
  CREATE INDEX IF NOT EXISTS idx_replies_message ON replies(message_id);
  CREATE INDEX IF NOT EXISTS idx_votes_target ON votes(target_type, target_id);
  CREATE INDEX IF NOT EXISTS idx_votes_user_target ON votes(user_fingerprint, target_type, target_id);
`);

// 输入过滤：防 XSS
function sanitize(str) {
  if (typeof str !== 'string') return '';
  return str.replace(/[<>&"']/g, c => ({
    '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

// 生成设备指纹（优先使用客户端 X-Fingerprint 头）
function generateFingerprint(req) {
  const clientFp = req.headers['x-fingerprint'];
  if (clientFp && typeof clientFp === 'string' && clientFp.length > 0) {
    return clientFp.substring(0, 64);
  }
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
  const ua = req.headers['user-agent'] || '';
  const raw = `${ip}-${ua}`;
  let hash = 0;
  for (let i = 0; i < raw.length; i++) {
    const char = raw.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(36);
}

// 生成随机弹幕颜色
function randomColor() {
  const colors = [
    '#ff6b6b', '#feca57', '#48dbfb', '#ff9ff3',
    '#54a0ff', '#5f27cd', '#00d2d3', '#ff9f43',
    '#10ac84', '#ee5a24', '#c8d6e5', '#feca57',
  ];
  return colors[Math.floor(Math.random() * colors.length)];
}

// 生成随机昵称
function randomNickname() {
  const adj = ['快乐的', '神秘的', '慵懒的', '奔跑的', '发呆的', '追梦的', '沉睡的', '漫步的'];
  const nouns = ['小猫', '橘子', '星河', '晚风', '云朵', '月亮', '猫咪', '兔子'];
  return adj[Math.floor(Math.random() * adj.length)] + nouns[Math.floor(Math.random() * nouns.length)];
}

// 构建投票计数 JOIN 片段
function buildVoteJoin(targetType) {
  return `
    LEFT JOIN (
      SELECT target_id,
        SUM(CASE WHEN vote_type='like' THEN 1 ELSE 0 END) as vote_likes,
        SUM(CASE WHEN vote_type='dislike' THEN 1 ELSE 0 END) as vote_dislikes
      FROM votes WHERE target_type='${targetType}'
      GROUP BY target_id
    ) v ON v.target_id = m.id
    LEFT JOIN votes mv ON mv.target_type='${targetId}' AND mv.target_id=m.id AND mv.user_fingerprint=?
  `;
}

// 构建投票计数字段
function buildVoteColumns(alias = '') {
  const p = alias ? alias + '.' : '';
  return `
    COALESCE(${p}vote_likes, 0) as real_likes,
    COALESCE(${p}vote_dislikes, 0) as real_dislikes,
    ${p}mv.vote_type as my_vote
  `;
}

// 密码哈希（scrypt）
function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

// 验证密码
function verifyPassword(password, stored) {
  const [salt, hash] = stored.split(':');
  const testHash = crypto.scryptSync(password, salt, 64).toString('hex');
  return testHash === hash;
}

// 简单 Token（HMAC 签名 + Base64）
const TOKEN_SECRET = process.env.TOKEN_SECRET || 'maozi-secret-key-change-in-production';

function generateToken(userId, username, nickname) {
  const payload = JSON.stringify({ uid: userId, usr: username, nick: nickname, exp: Date.now() + 7 * 24 * 3600 * 1000 });
  const payloadB64 = Buffer.from(payload).toString('base64url');
  const sig = crypto.createHmac('sha256', TOKEN_SECRET).update(payloadB64).digest('base64url');
  return payloadB64 + '.' + sig;
}

function verifyToken(token) {
  if (!token || typeof token !== 'string') return null;
  try {
    const [payloadB64, sig] = token.split('.');
    const expectedSig = crypto.createHmac('sha256', TOKEN_SECRET).update(payloadB64).digest('base64url');
    if (sig !== expectedSig) return null;
    const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString());
    if (payload.exp < Date.now()) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

module.exports = {
  db,
  generateFingerprint,
  randomColor,
  randomNickname,
  sanitize,
  hashPassword,
  verifyPassword,
  generateToken,
  verifyToken,
};
