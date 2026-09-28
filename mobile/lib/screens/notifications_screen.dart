import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'detail_screen.dart';

/// 通知中心：别人回复我的留言的持久化列表
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _Notif {
  final int id;
  final String messageId;
  final String senderName;
  final String preview;
  final bool read;
  final String createdAt;
  _Notif({
    required this.id,
    required this.messageId,
    required this.senderName,
    required this.preview,
    required this.read,
    required this.createdAt,
  });

  factory _Notif.fromJson(Map<String, dynamic> j) => _Notif(
        id: (j['id'] as num?)?.toInt() ?? 0,
        messageId: j['message_id'] ?? '',
        senderName: j['sender_name'] ?? '有人',
        preview: j['preview'] ?? '',
        read: j['read'] == 1 || j['read'] == true,
        createdAt: j['created_at'] ?? '',
      );
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_Notif> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getNotifications();
      if (!mounted) return;
      setState(() {
        _items = ((data['items'] as List?) ?? [])
            .map((j) => _Notif.fromJson(j as Map<String, dynamic>))
            .toList();
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

  Future<void> _markAllRead() async {
    try {
      await ApiService.markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        _items = _items.map((n) => _Notif(
              id: n.id,
              messageId: n.messageId,
              senderName: n.senderName,
              preview: n.preview,
              read: true,
              createdAt: n.createdAt,
            )).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  void _openTarget(_Notif n) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(messageId: n.messageId),
      ),
    ).then((_) => _load()); // 详情页可能有新回复，返回时刷新
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
        title: const Text('通知', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _items.isEmpty ? null : _markAllRead,
            child: const Text('全部已读',
                style: TextStyle(color: Color(0xFF48dbfb), fontSize: 13)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF48dbfb)))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_off_outlined,
                          color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text('$_error',
                          style:
                              const TextStyle(color: Colors.white38, fontSize: 12),
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
              : _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none_rounded,
                              color: Colors.white24, size: 48),
                          SizedBox(height: 12),
                          Text('还没有通知\n别人回复你的留言时会在这里提醒',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white38, height: 1.6)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: const Color(0xFF48dbfb),
                      backgroundColor: const Color(0xFF1e1e3a),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final n = _items[i];
                          return Material(
                            color: n.read
                                ? Colors.white.withOpacity(0.05)
                                : const Color(0xFF48dbfb).withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openTarget(n),
                              child: Container(
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border(
                                    left: n.read
                                        ? BorderSide.none
                                        : const BorderSide(
                                            color: Color(0xFF48dbfb), width: 3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '💬 ${n.senderName} 回复了你的留言',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: n.read
                                                  ? Colors.white54
                                                  : const Color(0xFF48dbfb),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          _formatTime(n.createdAt),
                                          style: const TextStyle(
                                              color: Colors.white24, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      n.preview,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: n.read
                                            ? Colors.white70
                                            : Colors.white,
                                        fontSize: 14,
                                        height: 1.45,
                                      ),
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
