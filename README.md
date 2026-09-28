# 帽子留言 🎩

匿名弹幕留言墙：实时弹幕展示 + 匿名/登录双身份 + 回复通知 + 举报管理。一套后端同时服务 Web 弹幕页和 Flutter App。

## 架构

```
backend/            Express + better-sqlite3 + WebSocket（单进程，含 Web 静态页）
  public/index.html Web 弹幕页（无构建，原生 JS 单文件）
  routes/           messages / auth / notifications
  moderation.js     敏感词过滤（词库 banned-words.txt，可换 BANNED_WORDS_FILE）
  scripts/          set-admin.js 授权管理员 / backup.sh 数据库备份
mobile/             Flutter App（Android 打包由 GitHub Actions 完成）
.github/workflows/  push main 自动构建 APK artifact
```

## 功能一览

- **弹幕墙**：恒速飞行、5 轨道、满轨排队不重叠；WS 实时推送 + 自适应轮询兜底（Web 30s / App 断线 30s 在线 2min）
- **身份**：免登录匿名（随机昵称+随机色），注册登录后用真实昵称和头像色；支持改资料、改密码（改密后全设备下线）、退出
- **互动**：回复、点赞点踩（匿名票绑服务端 IP+UA 指纹防刷，登录并账）、举报
- **通知中心**：别人回复你的留言落库通知，离线可见未读数（Web 铃铛 / App 角标+列表）
- **浏览**：按日期前后翻页（默认仅今天填充示例弹幕）、全库关键词搜索
- **管理端**：`users.is_admin` 用户可在 Web 处理举报、强删留言/回复、置顶留言
- **合规**：敏感词打码、举报入口、防刷屏（同身份 10 分钟内重复内容拒绝）、三级限流
- **弹幕底色**：跟随文字色 16% 透明度，深色页面更有层次

## 本地开发

```bash
# 后端（默认端口 60175）
cd backend && npm install && npm start
# Web 弹幕页: http://localhost:60175  健康检查: /health

# Flutter
cd mobile && flutter run --dart-define=API_BASE_URL=http://<你的IP>:60175/api
```

首次启动自动建表并迁移旧库（token_version / is_admin 列）。

## 部署

服务器约定：代码在 `/root/maozi-message`，pm2 进程名 `maozi-message`，Nginx 60170 反代到 Node 60175。

```bash
# 有 SSH 密钥时
./deploy.sh
# 无密钥（expect + 密码，读 DEPLOY_PASSWORD 环境变量）
DEPLOY_PASSWORD='xxx' ./deploy-expect.sh
```

脚本会排除 `.env` 和 `data.db`，不会覆盖线上配置与数据。

### 服务器上的运维

```bash
# 授予管理员（Web 端即出现 🛡 举报处理与置顶能力）
cd /root/maozi-message && node scripts/set-admin.js <用户名>
node scripts/set-admin.js <用户名> revoke   # 撤销

# 数据库备份（在线，不停服务；保留最近 14 份）
./scripts/backup.sh                     # 默认备份到 /root/maozi-backups
crontab -e                              # 建议加每日凌晨 3 点：
0 3 * * * /root/maozi-message/scripts/backup.sh >> /var/log/maozi-backup.log 2>&1

# 恢复备份（先停服务，替换库文件，再启动）
pm2 stop maozi-message
cp /root/maozi-backups/maozi_data_YYYYMMDD_HHMMSS.db /root/maozi-message/data.db
rm -f /root/maozi-message/data.db-shm /root/maozi-message/data.db-wal
pm2 start maozi-message
```

## 环境变量（backend/.env，参考 .env.example）

| 变量 | 说明 | 默认 |
|---|---|---|
| `TOKEN_SECRET` | 生产必填，随机长字符串 | — |
| `PORT` | 监听端口 | 60175 |
| `CORS_ORIGINS` | 放行的跨域来源，逗号分隔 | 同源 |
| `DISPLAY_TZ_OFFSET` | 展示时区（"今日"按此时区算） | 8（东八区） |
| `BANNED_WORDS_FILE` | 自定义敏感词库路径 | backend/banned-words.txt |
| `WS_HEARTBEAT_MS` | WS 心跳间隔 | 30000 |

## API 概览

```
POST /api/auth/register | login | change-password   PATCH /api/auth/profile   GET /api/auth/me
GET  /api/messages?date=YYYY-MM-DD | mine=1         GET /api/messages/search?q=
GET  /api/messages/:id     POST /api/messages       DELETE /api/messages/:id（作者或管理员）
POST /api/messages/:id/reply | vote | report        POST /api/messages/:id/pin（管理员）
POST /api/replies/:id/vote | report                 DELETE /api/replies/:id（管理员）
GET  /api/notifications    POST /api/notifications/read-all
GET  /api/admin/reports（管理员）                    GET /api/stats    GET /health
WS   /ws  事件: new_message / new_reply / reply_deleted / message_deleted / vote_update
```
