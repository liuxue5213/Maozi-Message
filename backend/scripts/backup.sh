#!/usr/bin/env bash
# 帽子留言 - 数据库在线备份
# 用法: ./backup.sh [备份目录]   （默认 /root/maozi-backups）
# 通过 better-sqlite3 的 backup API 做在线备份，WAL 模式下也能保证一致性，
# 服务无需停机。建议加 cron 每日执行：
#   0 3 * * * /root/maozi-message/scripts/backup.sh >> /var/log/maozi-backup.log 2>&1
set -e

DIR="${1:-/root/maozi-backups}"
KEEP=14  # 保留最近 14 份
STAMP=$(date +%Y%m%d_%H%M%S)
TARGET="$DIR/maozi_data_$STAMP.db"

cd "$(cd "$(dirname "$0")/.." && pwd)"
[ -f data.db ] || { echo "❌ 未找到 data.db"; exit 1; }

mkdir -p "$DIR"
node -e "require('better-sqlite3')('data.db').backup(process.argv[1]).then(()=>console.log('done')).catch(e=>{console.error(e.message);process.exit(1)})" "$TARGET" > /dev/null

# 保留策略：只留最近 KEEP 份
ls -1t "$DIR"/maozi_data_*.db 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

SIZE=$(du -h "$TARGET" | cut -f1)
echo "✅ 备份完成: $TARGET ($SIZE)"
