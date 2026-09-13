const fs = require('fs');
const path = require('path');

// 词库：默认读同目录 banned-words.txt，可用 BANNED_WORDS_FILE 指向自定义文件
const WORDS_FILE = process.env.BANNED_WORDS_FILE || path.join(__dirname, 'banned-words.txt');

let words = [];
try {
  words = fs.readFileSync(WORDS_FILE, 'utf8')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(line => line && !line.startsWith('#'));
} catch (err) {
  console.error('敏感词库加载失败（跳过过滤）:', err.message);
}

// 长词优先，避免短词先命中拆散长词
words.sort((a, b) => b.length - a.length);

const PATTERN = words.length > 0
  ? new RegExp(words.map(w => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'gi')
  : null;

if (PATTERN) console.log(`🛡 敏感词过滤已启用，词库 ${words.length} 条`);

// 命中敏感词的字符替换为等长 *；未配置词库时原样返回
function maskBannedWords(text) {
  if (!PATTERN || typeof text !== 'string') return text;
  return text.replace(PATTERN, m => '*'.repeat(m.length));
}

module.exports = { maskBannedWords };
