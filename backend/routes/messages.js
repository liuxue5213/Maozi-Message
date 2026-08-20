const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');
const { db, generateFingerprint, randomColor, randomNickname, sanitize, verifyToken } = require('../db');

// 获取 WebSocket 广播函数
function getBroadcast(req) {
  return req.app.get('wsBroadcast');
}

// 获取今天的留言列表（分页）
router.get('/messages', (req, res) => {
  try {
    const {
      date = new Date().toISOString().split('T')[0],
      limit = 20,
      offset = 0,
    } = req.query;
    const fp = generateFingerprint(req);

    const safeLimit = Math.min(parseInt(limit) || 20, 100);
    const safeOffset = Math.max(parseInt(offset) || 0, 0);

    const messages = db.prepare(`
      SELECT m.id, m.content, m.author_name, m.color, m.bg_color, m.mood,
        m.is_anonymous, m.replies_count, m.created_at, m.expire_at, m.is_pinned,
        COALESCE(v.vote_likes, 0) as real_likes,
        COALESCE(v.vote_dislikes, 0) as real_dislikes,
        mv.vote_type as my_vote
      FROM messages m
      LEFT JOIN (
        SELECT target_id,
          SUM(CASE WHEN vote_type='like' THEN 1 ELSE 0 END) as vote_likes,
          SUM(CASE WHEN vote_type='dislike' THEN 1 ELSE 0 END) as vote_dislikes
        FROM votes WHERE target_type='message'
        GROUP BY target_id
      ) v ON v.target_id = m.id
      LEFT JOIN votes mv ON mv.target_type='message' AND mv.target_id=m.id AND mv.user_fingerprint=?
      WHERE date(m.created_at) = ? AND m.deleted_at IS NULL
        AND (m.expire_at IS NULL OR m.expire_at > datetime('now'))
      ORDER BY m.is_pinned DESC, m.created_at DESC
      LIMIT ? OFFSET ?
    `).all(fp, date, safeLimit, safeOffset);

    // 获取回复（也用 JOIN 优化）
    const result = messages.map(msg => {
      const replies = db.prepare(`
        SELECT r.id, r.message_id, r.content, r.author_name, r.created_at,
          COALESCE(v.vote_likes, 0) as real_likes,
          COALESCE(v.vote_dislikes, 0) as real_dislikes,
          mv.vote_type as my_vote
        FROM replies r
        LEFT JOIN (
          SELECT target_id,
            SUM(CASE WHEN vote_type='like' THEN 1 ELSE 0 END) as vote_likes,
            SUM(CASE WHEN vote_type='dislike' THEN 1 ELSE 0 END) as vote_dislikes
          FROM votes WHERE target_type='reply'
          GROUP BY target_id
        ) v ON v.target_id = r.id
        LEFT JOIN votes mv ON mv.target_type='reply' AND mv.target_id=r.id AND mv.user_fingerprint=?
        WHERE r.message_id = ? AND r.deleted_at IS NULL
        ORDER BY r.created_at ASC
      `).all(fp, msg.id);
      return { ...msg, replies };
    });

    res.json({
      success: true,
      data: result,
      pagination: { limit: safeLimit, offset: safeOffset, total: result.length },
    });
  } catch (err) {
    console.error('获取留言失败:', err);
    res.status(500).json({ success: false, error: '加载失败' });
  }
});

// 获取单条留言详情（含回复）
router.get('/messages/:id', (req, res) => {
  try {
    const fp = generateFingerprint(req);
    const msg = db.prepare(`
      SELECT m.*,
        COALESCE(v.vote_likes, 0) as real_likes,
        COALESCE(v.vote_dislikes, 0) as real_dislikes,
        mv.vote_type as my_vote
      FROM messages m
      LEFT JOIN (
        SELECT target_id,
          SUM(CASE WHEN vote_type='like' THEN 1 ELSE 0 END) as vote_likes,
          SUM(CASE WHEN vote_type='dislike' THEN 1 ELSE 0 END) as vote_dislikes
        FROM votes WHERE target_type='message'
        GROUP BY target_id
      ) v ON v.target_id = m.id
      LEFT JOIN votes mv ON mv.target_type='message' AND mv.target_id=m.id AND mv.user_fingerprint=?
      WHERE m.id = ? AND m.deleted_at IS NULL
    `).get(fp, req.params.id);

    if (!msg) return res.status(404).json({ success: false, error: '留言不存在' });

    const replies = db.prepare(`
      SELECT r.id, r.message_id, r.content, r.author_name, r.created_at,
        COALESCE(v.vote_likes, 0) as real_likes,
        COALESCE(v.vote_dislikes, 0) as real_dislikes,
        mv.vote_type as my_vote
      FROM replies r
      LEFT JOIN (
        SELECT target_id,
          SUM(CASE WHEN vote_type='like' THEN 1 ELSE 0 END) as vote_likes,
          SUM(CASE WHEN vote_type='dislike' THEN 1 ELSE 0 END) as vote_dislikes
        FROM votes WHERE target_type='reply'
        GROUP BY target_id
      ) v ON v.target_id = r.id
      LEFT JOIN votes mv ON mv.target_type='reply' AND mv.target_id=r.id AND mv.user_fingerprint=?
      WHERE r.message_id = ? AND r.deleted_at IS NULL
      ORDER BY r.created_at ASC
    `).all(fp, msg.id);

    res.json({ success: true, data: { ...msg, replies } });
  } catch (err) {
    console.error('获取详情失败:', err);
    res.status(500).json({ success: false, error: '加载失败' });
  }
});

// 发布留言
router.post('/messages', (req, res) => {
  try {
    const { content, author_name, color, bg_color, mood, is_anonymous, expire_hours } = req.body;

    if (!content || content.trim().length === 0) {
      return res.status(400).json({ success: false, error: '留言内容不能为空' });
    }
    if (content.length > 500) {
      return res.status(400).json({ success: false, error: '留言最多500字' });
    }

    const validMoods = ['happy', 'neutral', 'sad', 'angry', 'excited', 'calm'];
    const id = uuidv4();
    const finalMood = validMoods.includes(mood) ? mood : 'neutral';
    const safeContent = sanitize(content.trim());

    // 检查是否已登录
    const auth = req.headers.authorization;
    const tokenPayload = auth && auth.startsWith('Bearer ') ? verifyToken(auth.substring(7)) : null;

    let finalName, finalColor, finalBgColor;

    if (tokenPayload) {
      // 已登录：用真实昵称和头像颜色
      const user = db.prepare('SELECT nickname, avatar_color FROM users WHERE id = ?').get(tokenPayload.uid);
      if (user) {
        finalName = user.nickname;
        finalColor = user.avatar_color;
        finalBgColor = 'rgba(0,0,0,0.6)';
      } else {
        finalName = randomNickname();
        finalColor = randomColor();
        finalBgColor = 'rgba(0,0,0,0.6)';
      }
    } else {
      // 未登录：匿名发布
      finalName = is_anonymous || !author_name ? randomNickname() : sanitize(author_name);
      finalColor = color || randomColor();
      finalBgColor = bg_color || 'rgba(0,0,0,0.6)';
    }

    let expireAt = null;
    if (expire_hours) {
      const d = new Date();
      d.setHours(d.getHours() + parseInt(expire_hours));
      expireAt = d.toISOString();
    }

    db.prepare(`
      INSERT INTO messages (id, content, author_name, color, bg_color, mood, is_anonymous, expire_at, author_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(id, safeContent, finalName, finalColor, finalBgColor, finalMood, tokenPayload ? 0 : 1, expireAt, tokenPayload ? tokenPayload.uid : generateFingerprint(req));

    const newMsg = { id, content: safeContent, author_name: finalName, color: finalColor, bg_color: finalBgColor, mood: finalMood, replies: [] };

    // 广播新留言
    getBroadcast(req)('new_message', newMsg);

    res.json({ success: true, data: newMsg });
  } catch (err) {
    console.error('发布留言失败:', err);
    res.status(500).json({ success: false, error: '发布失败' });
  }
});

// 回复留言
router.post('/messages/:id/reply', (req, res) => {
  try {
    const { content, author_name, is_anonymous } = req.body;

    if (!content || content.trim().length === 0) {
      return res.status(400).json({ success: false, error: '回复内容不能为空' });
    }
    if (content.length > 500) {
      return res.status(400).json({ success: false, error: '回复最多500字' });
    }

    const msg = db.prepare('SELECT id FROM messages WHERE id = ? AND deleted_at IS NULL').get(req.params.id);
    if (!msg) return res.status(404).json({ success: false, error: '留言不存在' });

    const id = uuidv4();
    const safeContent = sanitize(content.trim());

    // 检查是否已登录
    const auth = req.headers.authorization;
    const tokenPayload = auth && auth.startsWith('Bearer ') ? verifyToken(auth.substring(7)) : null;

    let finalName, fp;
    if (tokenPayload) {
      const user = db.prepare('SELECT nickname FROM users WHERE id = ?').get(tokenPayload.uid);
      finalName = user ? user.nickname : randomNickname();
      fp = tokenPayload.uid;
    } else {
      finalName = is_anonymous || !author_name ? randomNickname() : sanitize(author_name);
      fp = generateFingerprint(req);
    }

    db.prepare(`
      INSERT INTO replies (id, message_id, content, author_name, author_id)
      VALUES (?, ?, ?, ?, ?)
    `).run(id, req.params.id, safeContent, finalName, fp);

    db.prepare('UPDATE messages SET replies_count = replies_count + 1 WHERE id = ?').run(req.params.id);

    const newReply = { id, content: safeContent, author_name: finalName, message_id: req.params.id };

    // 广播新回复
    getBroadcast(req)('new_reply', { message_id: req.params.id, reply: newReply });

    res.json({ success: true, data: newReply });
  } catch (err) {
    console.error('回复失败:', err);
    res.status(500).json({ success: false, error: '回复失败' });
  }
});

// 点赞/踩 留言
router.post('/messages/:id/vote', (req, res) => {
  try {
    const { vote_type } = req.body;
    if (!['like', 'dislike'].includes(vote_type)) {
      return res.status(400).json({ success: false, error: '投票类型无效' });
    }

    const fp = generateFingerprint(req);
    const targetId = req.params.id;

    const msgExists = db.prepare('SELECT id FROM messages WHERE id = ? AND deleted_at IS NULL').get(targetId);
    if (!msgExists) return res.status(404).json({ success: false, error: '留言不存在' });

    const existing = db.prepare(`
      SELECT vote_type FROM votes WHERE target_type='message' AND target_id=? AND user_fingerprint=?
    `).get(targetId, fp);

    if (existing) {
      if (existing.vote_type === vote_type) {
        db.prepare(`DELETE FROM votes WHERE target_type='message' AND target_id=? AND user_fingerprint=?`).run(targetId, fp);
      } else {
        db.prepare(`UPDATE votes SET vote_type=? WHERE target_type='message' AND target_id=? AND user_fingerprint=?`).run(vote_type, targetId, fp);
      }
    } else {
      db.prepare(`INSERT INTO votes (target_type, target_id, user_fingerprint, vote_type) VALUES ('message', ?, ?, ?)`).run(targetId, fp, vote_type);
    }

    const counts = db.prepare(`
      SELECT
        (SELECT COUNT(*) FROM votes WHERE target_type='message' AND target_id=? AND vote_type='like') as likes,
        (SELECT COUNT(*) FROM votes WHERE target_type='message' AND target_id=? AND vote_type='dislike') as dislikes,
        (SELECT vote_type FROM votes WHERE target_type='message' AND target_id=? AND user_fingerprint=?) as my_vote
    `).get(targetId, targetId, targetId, fp);

    // 广播投票更新
    getBroadcast(req)('vote_update', { target_type: 'message', target_id: targetId, likes: counts.likes, dislikes: counts.dislikes });

    res.json({ success: true, data: counts });
  } catch (err) {
    console.error('投票失败:', err);
    res.status(500).json({ success: false, error: '投票失败' });
  }
});

// 点赞/踩 回复
router.post('/replies/:id/vote', (req, res) => {
  try {
    const { vote_type } = req.body;
    if (!['like', 'dislike'].includes(vote_type)) {
      return res.status(400).json({ success: false, error: '投票类型无效' });
    }

    const fp = generateFingerprint(req);
    const targetId = req.params.id;

    const replyExists = db.prepare('SELECT id FROM replies WHERE id = ? AND deleted_at IS NULL').get(targetId);
    if (!replyExists) return res.status(404).json({ success: false, error: '回复不存在' });

    const existing = db.prepare(`
      SELECT vote_type FROM votes WHERE target_type='reply' AND target_id=? AND user_fingerprint=?
    `).get(targetId, fp);

    if (existing) {
      if (existing.vote_type === vote_type) {
        db.prepare(`DELETE FROM votes WHERE target_type='reply' AND target_id=? AND user_fingerprint=?`).run(targetId, fp);
      } else {
        db.prepare(`UPDATE votes SET vote_type=? WHERE target_type='reply' AND target_id=? AND user_fingerprint=?`).run(vote_type, targetId, fp);
      }
    } else {
      db.prepare(`INSERT INTO votes (target_type, target_id, user_fingerprint, vote_type) VALUES ('reply', ?, ?, ?)`).run(targetId, fp, vote_type);
    }

    const counts = db.prepare(`
      SELECT
        (SELECT COUNT(*) FROM votes WHERE target_type='reply' AND target_id=? AND vote_type='like') as likes,
        (SELECT COUNT(*) FROM votes WHERE target_type='reply' AND target_id=? AND vote_type='dislike') as dislikes,
        (SELECT vote_type FROM votes WHERE target_type='reply' AND target_id=? AND user_fingerprint=?) as my_vote
    `).get(targetId, targetId, targetId, fp);

    getBroadcast(req)('vote_update', { target_type: 'reply', target_id: targetId, likes: counts.likes, dislikes: counts.dislikes });

    res.json({ success: true, data: counts });
  } catch (err) {
    console.error('投票失败:', err);
    res.status(500).json({ success: false, error: '投票失败' });
  }
});

// 删除留言（软删除，仅限作者本人）
router.delete('/messages/:id', (req, res) => {
  try {
    const fp = generateFingerprint(req);
    const msg = db.prepare('SELECT author_id FROM messages WHERE id = ? AND deleted_at IS NULL').get(req.params.id);
    if (!msg) return res.status(404).json({ success: false, error: '留言不存在' });

    if (msg.author_id !== fp) {
      return res.status(403).json({ success: false, error: '无权删除此留言' });
    }

    db.prepare("UPDATE messages SET deleted_at = datetime('now') WHERE id = ?").run(req.params.id);
    db.prepare("UPDATE replies SET deleted_at = datetime('now') WHERE message_id = ?").run(req.params.id);

    getBroadcast(req)('message_deleted', { id: req.params.id });

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, error: '删除失败' });
  }
});

// 获取统计数据
router.get('/stats', (req, res) => {
  try {
    const today = new Date().toISOString().split('T')[0];
    const totalMessages = db.prepare("SELECT COUNT(*) as count FROM messages WHERE deleted_at IS NULL").get().count;
    const todayMessages = db.prepare("SELECT COUNT(*) as count FROM messages WHERE date(created_at) = ? AND deleted_at IS NULL").get(today).count;
    const totalReplies = db.prepare("SELECT COUNT(*) as count FROM replies WHERE deleted_at IS NULL").get().count;
    const todayReplies = db.prepare("SELECT COUNT(*) as count FROM replies WHERE date(created_at) = ? AND deleted_at IS NULL").get(today).count;

    res.json({
      success: true,
      data: { totalMessages, todayMessages, totalReplies, todayReplies },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: '加载失败' });
  }
});

module.exports = router;
