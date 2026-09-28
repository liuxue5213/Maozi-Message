#!/usr/bin/env node
// 授予/撤销管理员权限。用法：
//   node scripts/set-admin.js <用户名>          # 授予
//   node scripts/set-admin.js <用户名> revoke   # 撤销
const Database = require('better-sqlite3');
const path = require('path');

const [username, mode] = process.argv.slice(2);
if (!username) {
  console.error('用法: node scripts/set-admin.js <用户名> [revoke]');
  process.exit(1);
}

const db = new Database(path.join(__dirname, '..', 'data.db'));
const user = db.prepare('SELECT id, username, is_admin FROM users WHERE username = ?').get(username);
if (!user) {
  console.error(`用户 ${username} 不存在`);
  process.exit(1);
}

const next = mode === 'revoke' ? 0 : 1;
db.prepare('UPDATE users SET is_admin = ? WHERE id = ?').run(next, user.id);
console.log(`✅ ${user.username} is_admin => ${next}`);
db.close();
