import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import 'detail_screen.dart';

/// 我的留言：当前登录用户发布的全部留言
class MyMessagesScreen extends StatefulWidget {
  const MyMessagesScreen({super.key});

  @override
  State<MyMessagesScreen> createState() => _MyMessagesScreenState();
}

class _MyMessagesScreenState extends State<MyMessagesScreen> {
  List<Message> _messages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final messages = await ApiService.getMessages(mine: true, limit: 100);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openDetail(Message msg) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(messageId: msg.id, preview: msg),
      ),
    ).then((_) => _load()); // 详情里可能删除/回复，返回后刷新
  }

  String _formatTime(String t) {
    try {
      final d = DateTime.parse(
        t.endsWith('Z') || t.contains('+') ? t : t.replaceFirst(' ', 'T') + 'Z',
      );
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
        title: const Text('我的留言', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF48dbfb)))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text('$_error',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF48dbfb)),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _messages.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined, color: Colors.white24, size: 48),
                          SizedBox(height: 12),
                          Text('还没有发过留言，去发一条吧~',
                              style: TextStyle(color: Colors.white38)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: const Color(0xFF48dbfb),
                      backgroundColor: const Color(0xFF1e1e3a),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          return Material(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openDetail(m),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.content,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 15, height: 1.5),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Text(
                                          _formatTime(m.createdAt),
                                          style: const TextStyle(
                                              color: Colors.white38, fontSize: 11),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '💬 ${m.repliesCount}  👍 ${m.likesCount}',
                                          style: const TextStyle(
                                              color: Colors.white38, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
