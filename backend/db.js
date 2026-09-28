const Database = require('better-sqlite3');
const path = require('path');
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
    token_version INTEGER DEFAULT 0,
    is_admin INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
  );

  -- 举报记录（供管理端核查，不对外暴露）
  CREATE TABLE IF NOT EXISTS reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target_type TEXT NOT NULL CHECK(target_type IN ('message', 'reply')),
    target_id TEXT NOT NULL,
    reason TEXT DEFAULT '',
    reporter_fingerprint TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
  );

  -- 通知中心：别人回复了"注册用户"的留言时落库，离线也能看到
  CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    type TEXT DEFAULT 'reply',
    message_id TEXT NOT NULL,
    reply_id TEXT,
    sender_name TEXT DEFAULT '',
    preview TEXT DEFAULT '',
    read INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
  );

  -- 创建索引加速查询
  CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_messages_expire ON messages(expire_at);
  CREATE INDEX IF NOT EXISTS idx_replies_message ON replies(message_id);
  CREATE INDEX IF NOT EXISTS idx_votes_target ON votes(target_type, target_id);
  CREATE INDEX IF NOT EXISTS idx_votes_user_target ON votes(user_fingerprint, target_type, target_id);
  CREATE INDEX IF NOT EXISTS idx_reports_target ON reports(target_type, target_id);
  CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, read);
`);

// 旧库迁移：users.token_version（修改密码后吊销全部旧 token 用）
const userCols = db.pragma('table_info(users)');
if (!userCols.some(c => c.name === 'token_version')) {
  db.exec("ALTER TABLE users ADD COLUMN token_version INTEGER DEFAULT 0");
  console.log('🛠 users 表已迁移：新增 token_version 列');
}
// 旧库迁移：users.is_admin（管理端：举报处理/置顶/强删）
if (!userCols.some(c => c.name === 'is_admin')) {
  db.exec("ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0");
  console.log('🛠 users 表已迁移：新增 is_admin 列');
}

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

// 服务端自证身份：不信任客户端指纹头（可随意伪造）。
// 用于投票等防刷场景——匿名身份绑定 ip+ua，刷票必须换 IP 才有效。
// 代价：同一 NAT（公司/校园网）下的匿名用户共享投票身份，登录用户不受影响。
function serverFingerprint(req) {
  const fwd = req.headers['x-forwarded-for'];
  const ip = (typeof fwd === 'string' ? fwd.split(',')[0].trim() : req.socket.remoteAddress) || '';
  const ua = req.headers['user-agent'] || '';
  return crypto.createHash('sha256').update(`${ip}|${ua}`).digest('hex').slice(0, 32);
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

// 密码哈希（scrypt）
function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

// 验证密码
function verifyPassword(password, stored) {
  try {
    const [salt, hash] = stored.split(':');
    const testHash = crypto.scryptSync(password, salt, 64).toString('hex');
    const expected = Buffer.from(hash, 'hex');
    const actual = Buffer.from(testHash, 'hex');
    return expected.length === actual.length && crypto.timingSafeEqual(actual, expected);
  } catch (_) {
    return false;
  }
}

// 简单 Token（HMAC 签名 + Base64）。ver 为 token_version，修改密码后旧版本全部失效
if (process.env.NODE_ENV === 'production' && !process.env.TOKEN_SECRET) {
  throw new Error('生产环境必须设置 TOKEN_SECRET');
}
const TOKEN_SECRET = process.env.TOKEN_SECRET || 'development-only-secret';

function generateToken(userId, username, nickname, ver = 0) {
  const payload = JSON.stringify({ uid: userId, usr: username, nick: nickname, ver, exp: Date.now() + 7 * 24 * 3600 * 1000 });
  const payloadB64 = Buffer.from(payload).toString('base64url');
  const sig = crypto.createHmac('sha256', TOKEN_SECRET).update(payloadB64).digest('base64url');
  return payloadB64 + '.' + sig;
}

function verifyToken(token) {
  if (!token || typeof token !== 'string') return null;
  try {
    const [payloadB64, sig] = token.split('.');
    const expectedSig = crypto.createHmac('sha256', TOKEN_SECRET).update(payloadB64).digest('base64url');
    if (!sig || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expectedSig))) return null;
    const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString());
    if (payload.exp < Date.now()) return null;
    payload.ver = payload.ver ?? 0; // 老版本 token 视为 ver 0，与默认列值兼容
    return payload;
  } catch (_) {
    return null;
  }
}

// 校验 token 且版本号与用户当前 token_version 一致（改密后旧 token 全部失效）
function verifyTokenVersion(payload, currentVersion) {
  return !!payload && (payload.ver ?? 0) === (currentVersion || 0);
}

// 弹幕底色：跟随文字色的低透明度版本，深色页面上更有层次
function tintBg(hex, alpha) {
  if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return 'rgba(0,0,0,0.6)';
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${alpha})`;
}

module.exports = {
  db,
  generateFingerprint,
  serverFingerprint,
  randomColor,
  randomNickname,
  sanitize,
  hashPassword,
  verifyPassword,
  generateToken,
  verifyToken,
  verifyTokenVersion,
  tintBg,
};
