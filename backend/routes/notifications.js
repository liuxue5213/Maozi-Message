const express = require('express');
const router = express.Router();
const { db, verifyToken, verifyTokenVersion } = require('../db');

function getAuthPayload(req) {
  const auth = req.headers.authorization;
  const payload = auth && auth.startsWith('Bearer ') ? verifyToken(auth.substring(7)) : null;
  if (!payload) return null;
  const row = db.prepare('SELECT token_version FROM users WHERE id = ?').get(payload.uid);
  if (!row) return null;
  return verifyTokenVersion(payload, row.token_version) ? payload : null;
}

// 我的通知列表（最新在前），附未读数
router.get('/', (req, res) => {
  try {
    const payload = getAuthPayload(req);
    if (!payload) return res.status(401).json({ success: false, error: '请登录后查看通知' });

    const safeLimit = Math.max(1, Math.min(parseInt(req.query.limit) || 30, 50));
    const safeOffset = Math.max(parseInt(req.query.offset) || 0, 0);

    const items = db.prepare(`
      SELECT id, type, message_id, reply_id, sender_name, preview, read, created_at
      FROM notifications WHERE user_id = ?
      ORDER BY id DESC LIMIT ? OFFSET ?
    `).all(payload.uid, safeLimit, safeOffset);
    const unread = db.prepare('SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND read = 0')
      .get(payload.uid).count;

    res.json({ success: true, data: { items, unread } });
  } catch (err) {
    console.error('获取通知失败:', err);
    res.status(500).json({ success: false, error: '加载失败' });
  }
});

// 全部标记已读
router.post('/read-all', (req, res) => {
  try {
    const payload = getAuthPayload(req);
    if (!payload) return res.status(401).json({ success: false, error: '请登录后操作' });

    const result = db.prepare('UPDATE notifications SET read = 1 WHERE user_id = ? AND read = 0').run(payload.uid);
    res.json({ success: true, data: { updated: result.changes } });
  } catch (err) {
    console.error('标记已读失败:', err);
    res.status(500).json({ success: false, error: '操作失败' });
  }
});

module.exports = router;
