const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const { db, hashPassword, verifyPassword, generateToken, verifyToken, randomColor } = require('../db');

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

    const token = generateToken(id, username.trim(), nickname.trim());

    res.json({
      success: true,
      data: {
        token,
        user: { id, username: username.trim(), nickname: nickname.trim(), avatar_color: color },
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

    const token = generateToken(user.id, user.username, user.nickname);

    res.json({
      success: true,
      data: {
        token,
        user: { id: user.id, username: user.username, nickname: user.nickname, avatar_color: user.avatar_color },
      },
    });
  } catch (err) {
    console.error('登录失败:', err);
    res.status(500).json({ success: false, error: '登录失败' });
  }
});

// 获取当前用户信息
router.get('/me', (req, res) => {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: '未登录' });
  }
  const payload = verifyToken(auth.substring(7));
  if (!payload) {
    return res.status(401).json({ success: false, error: '登录已过期' });
  }
  const user = db.prepare('SELECT id, username, nickname, avatar_color FROM users WHERE id = ?').get(payload.uid);
  if (!user) {
    return res.status(401).json({ success: false, error: '用户不存在' });
  }
  res.json({ success: true, data: user });
});

module.exports = router;
