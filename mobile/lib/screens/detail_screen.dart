import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_service.dart';

class DetailScreen extends StatefulWidget {
  final String messageId;

  const DetailScreen({super.key, required this.messageId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Message? _message;
  bool _loading = true;
  String? _error;
  final _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMessage();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadMessage() async {
    try {
      final msg = await ApiService.getMessage(widget.messageId);
      if (mounted) {
        setState(() {
          _message = msg;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _voteMessage(String voteType) async {
    if (_message == null) return;
    try {
      final result = await ApiService.vote(
        type: 'message',
        id: _message!.id,
        voteType: voteType,
      );
      if (mounted) {
        setState(() {
          _message = Message(
            id: _message!.id,
            content: _message!.content,
            authorName: _message!.authorName,
            createdAt: _message!.createdAt,
            replies: _message!.replies,
            likesCount: result['likes'] ?? 0,
            dislikesCount: result['dislikes'] ?? 0,
            myVote: result['my_vote'],
          );
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('投票失败: $e')),
      );
    }
  }

  Future<void> _voteReply(String replyId, String voteType) async {
    if (_message == null) return;
    try {
      final result = await ApiService.vote(
        type: 'reply',
        id: replyId,
        voteType: voteType,
      );
      if (mounted) {
        setState(() {
          final updatedReplies = _message!.replies.map((r) {
            if (r.id == replyId) {
              return Reply(
                id: r.id,
                messageId: r.messageId,
                content: r.content,
                authorName: r.authorName,
                createdAt: r.createdAt,
                likesCount: result['likes'] ?? 0,
                dislikesCount: result['dislikes'] ?? 0,
                myVote: result['my_vote'],
              );
            }
            return r;
          }).toList();
          _message = Message(
            id: _message!.id,
            content: _message!.content,
            authorName: _message!.authorName,
            createdAt: _message!.createdAt,
            replies: updatedReplies,
            likesCount: _message!.likesCount,
            dislikesCount: _message!.dislikesCount,
            myVote: _message!.myVote,
          );
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('投票失败: $e')),
      );
    }
  }

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;

    try {
      await ApiService.replyToMessage(
        messageId: widget.messageId,
        content: content,
      );
      _replyController.clear();
      _loadMessage();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('回复成功！')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回复失败: $e')),
      );
    }
  }

  String _formatTime(String t) {
    try {
      final d = DateTime.parse(t);
      return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return t;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1e1e3a),
        title: const Text('留言详情', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF48dbfb)))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text('$_error', style: const TextStyle(color: Colors.white38)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadMessage,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF48dbfb)),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_message == null) return const SizedBox();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 留言内容
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x1AFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${_message!.authorName} · ${_formatTime(_message!.createdAt)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _message!.content,
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    // 投票区
                    Row(
                      children: [
                        _voteButton(
                          icon: '👍',
                          count: _message!.likesCount,
                          isActive: _message!.myVote == 'like',
                          onTap: () => _voteMessage('like'),
                        ),
                        const SizedBox(width: 12),
                        _voteButton(
                          icon: '👎',
                          count: _message!.dislikesCount,
                          isActive: _message!.myVote == 'dislike',
                          onTap: () => _voteMessage('dislike'),
                        ),
                        const Spacer(),
                        Text('💬 ${_message!.replies.length} 条回复',
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Text('回复', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),

              // 回复列表
              if (_message!.replies.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('暂无回复，来说两句~',
                        style: TextStyle(color: Colors.white24, fontSize: 13)),
                  ),
                )
              else
                ..._message!.replies.map((reply) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '@${reply.authorName} · ${_formatTime(reply.createdAt)}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reply.content,
                            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _smallVoteButton(
                                '👍',
                                reply.likesCount,
                                reply.myVote == 'like',
                                () => _voteReply(reply.id, 'like'),
                              ),
                              const SizedBox(width: 8),
                              _smallVoteButton(
                                '👎',
                                reply.dislikesCount,
                                reply.myVote == 'dislike',
                                () => _voteReply(reply.id, 'dislike'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),

        // 回复输入框
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1e1e3a),
            border: Border(top: BorderSide(color: const Color(0x1AFFFFFF))),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: null,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: '回复...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0x1AFFFFFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      counterStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendReply,
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF48dbfb)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _voteButton({
    required String icon,
    required int count,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF48dbfb).withOpacity(0.2)
              : const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? const Color(0xFF48dbfb) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                color: isActive ? const Color(0xFF48dbfb) : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallVoteButton(String icon, int count, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0x26FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: TextStyle(
                color: isActive ? Colors.white70 : Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
