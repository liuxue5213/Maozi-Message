const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const { db, hashPassword, verifyPassword, generateToken, verifyToken, verifyTokenVersion, randomColor, serverFingerprint } = require('../db');

// 解析并校验 Authorization 头；token 版本号必须与用户当前 token_version 一致
function getAuthPayload(req) {
  const auth = req.headers.authorization;
  const payload = auth && auth.startsWith('Bearer ') ? verifyToken(auth.substring(7)) : null;
  if (!payload) return null;
  const row = db.prepare('SELECT token_version FROM users WHERE id = ?').get(payload.uid);
  if (!row) return null;
  return verifyTokenVersion(payload, row.token_version) ? payload : null;
}

// 登录时把该设备此前的匿名投票并入登录账号。
// 同一内容登录账号已投过的：丢弃匿名票；其余匿名票归账。
// 按两个维度找匿名票：客户端指纹（历史投票）+ 服务端 ip+ua 哈希（本轮起匿名投票的新身份）。
function mergeAnonVotesToUser(uid, fingerprints) {
  const uniq = [...new Set(fingerprints.filter(fp => fp && typeof fp === 'string' && fp !== uid))];
  if (uniq.length === 0) return;
  const run = db.transaction(() => {
    for (const fp of uniq) {
      db.prepare(`
        DELETE FROM votes WHERE user_fingerprint = ?
          AND EXISTS (SELECT 1 FROM votes v2
            WHERE v2.user_fingerprint = ?
              AND v2.target_type = votes.target_type
              AND v2.target_id = votes.target_id)
      `).run(fp, uid);
      db.prepare('UPDATE votes SET user_fingerprint = ? WHERE user_fingerprint = ?').run(uid, fp);
    }
  });
  run();
}

// 注册
router.post('/register', (req, res) => {
  try {
    const { username, password, nickname } = req.body;

    if (!username || username.trim().length < 3) {
      return res.status(400).json({ success: false, error: '用户名至少 3 个字符' });
    }
    if (!password || password.length < 6) {
      return res.status(400).json({ success: false, error: '密码至少 6 位' });
    }
    if (!nickname || nickname.trim().length === 0) {
      return res.status(400).json({ success: false, error: '昵称不能为空' });
    }
    if (nickname.length > 20) {
      return res.status(400).json({ success: false, error: '昵称最多 20 个字符' });
    }

    const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username.trim());
    if (existing) {
      return res.status(400).json({ success: false, error: '用户名已被注册' });
    }

    const id = uuidv4();
    const color = randomColor();

    db.prepare(`
      INSERT INTO users (id, username, password_hash, nickname, avatar_color)
      VALUES (?, ?, ?, ?, ?)
    `).run(id, username.trim(), hashPassword(password), nickname.trim(), color);

    const token = generateToken(id, username.trim(), nickname.trim(), 0);

    res.json({
      success: true,
      data: {
        token,
        user: { id, username: username.trim(), nickname: nickname.trim(), avatar_color: color, is_admin: 0 },
      },
    });
  } catch (err) {
    console.error('注册失败:', err);
    res.status(500).json({ success: false, error: '注册失败' });
  }
});

// 登录
router.post('/login', (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ success: false, error: '请输入用户名和密码' });
    }

    const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username.trim());
    if (!user || !verifyPassword(password, user.password_hash)) {
      return res.status(401).json({ success: false, error: '用户名或密码错误' });
    }

    // 此设备匿名期的投票并入该账号
    const clientFp = typeof req.headers['x-fingerprint'] === 'string'
      ? req.headers['x-fingerprint'].substring(0, 64)
      : null;
    mergeAnonVotesToUser(user.id, [clientFp, serverFingerprint(req)]);

    const token = generateToken(user.id, user.username, user.nickname, user.token_version || 0);

    res.json({
      success: true,
      data: {
        token,
        user: { id: user.id, username: user.username, nickname: user.nickname, avatar_color: user.avatar_color, is_admin: user.is_admin || 0 },
      },
    });
  } catch (err) {
    console.error('登录失败:', err);
    res.status(500).json({ success: false, error: '登录失败' });
  }
});

// 更新资料（昵称/头像颜色）。签发新 token（内含昵称）并返回，客户端整体替换会话。
router.patch('/profile', (req, res) => {
  try {
    const payload = getAuthPayload(req);
    if (!payload) {
      return res.status(401).json({ success: false, error: '未登录' });
    }

    const { nickname, avatar_color } = req.body;
    if (typeof nickname !== 'string' || !nickname.trim() || nickname.trim().length > 20) {
      return res.status(400).json({ success: false, error: '昵称应为 1 到 20 个字符' });
    }
    if (typeof avatar_color !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(avatar_color)) {
      return res.status(400).json({ success: false, error: '头像颜色格式无效' });
    }

    const result = db.prepare('UPDATE users SET nickname = ?, avatar_color = ? WHERE id = ?')
      .run(nickname.trim(), avatar_color, payload.uid);
    if (result.changes === 0) {
      return res.status(401).json({ success: false, error: '用户不存在' });
    }

    const { is_admin: isAdmin } = db.prepare('SELECT is_admin FROM users WHERE id = ?').get(payload.uid);
    const token = generateToken(payload.uid, payload.usr, nickname.trim(), payload.ver);
    res.json({
      success: true,
      data: {
        token,
        user: { id: payload.uid, username: payload.usr, nickname: nickname.trim(), avatar_color, is_admin: isAdmin || 0 },
      },
    });
  } catch (err) {
    console.error('更新资料失败:', err);
    res.status(500).json({ success: false, error: '更新失败' });
  }
});

// 修改密码：验证原密码 → 更新哈希 → token_version+1，所有旧 token（含其他设备）立即失效
router.post('/change-password', (req, res) => {
  try {
    const payload = getAuthPayload(req);
    if (!payload) {
      return res.status(401).json({ success: false, error: '未登录' });
    }

    const { old_password, new_password } = req.body;
    if (typeof new_password !== 'string' || new_password.length < 6) {
      return res.status(400).json({ success: false, error: '新密码至少 6 位' });
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(payload.uid);
    if (!user) {
      return res.status(401).json({ success: false, error: '用户不存在' });
    }
    if (!verifyPassword(typeof old_password === 'string' ? old_password : '', user.password_hash)) {
      return res.status(400).json({ success: false, error: '原密码错误' });
    }

    const newVersion = (user.token_version || 0) + 1;
    db.prepare('UPDATE users SET password_hash = ?, token_version = ? WHERE id = ?')
      .run(hashPassword(new_password), newVersion, user.id);

    const token = generateToken(user.id, user.username, user.nickname, newVersion);
    res.json({
      success: true,
      data: {
        token,
        user: { id: user.id, username: user.username, nickname: user.nickname, avatar_color: user.avatar_color, is_admin: user.is_admin || 0 },
      },
    });
  } catch (err) {
    console.error('修改密码失败:', err);
    res.status(500).json({ success: false, error: '修改失败' });
  }
});

// 获取当前用户信息
router.get('/me', (req, res) => {
  const payload = getAuthPayload(req);
  if (!payload) {
    return res.status(401).json({ success: false, error: '未登录' });
  }
  const user = db.prepare('SELECT id, username, nickname, avatar_color, is_admin FROM users WHERE id = ?').get(payload.uid);
  if (!user) {
    return res.status(401).json({ success: false, error: '用户不存在' });
  }
  res.json({ success: true, data: { ...user, is_admin: user.is_admin || 0 } });
});

module.exports = router;
