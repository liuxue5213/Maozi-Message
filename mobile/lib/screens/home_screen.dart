import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../widgets/barrage_item.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  List<Message> _allMessages = [];
  List<Message> _displayQueue = [];
  List<_ActiveBarrage> _activeBarrages = [];
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;
  Timer? _schedulerTimer;
  int _todayCount = 0;
  int _totalCount = 0;

  // 弹幕队列配置
  static const int _trackCount = 5;
  static const int _maxOnScreen = 5;
  static const Duration _scrollDuration = Duration(seconds: 15);
  static const Duration _minGap = Duration(seconds: 3);

  // 单控制器 + Stopwatch 计时
  late final Ticker _ticker;
  final _stopwatch = Stopwatch();
  double _screenWidth = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _schedulerTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    // 清理已完成的弹幕
    if (_activeBarrages.isNotEmpty) {
      final now = _stopwatch.elapsedMilliseconds;
      final scrollMs = _scrollDuration.inMilliseconds;
      final before = _activeBarrages.length;
      _activeBarrages.removeWhere((b) => now - b.startTimeMs > scrollMs);
      if (_activeBarrages.isEmpty && _displayQueue.isEmpty) {
        _ticker.stop();
        _stopwatch.stop();
      }
      if (_activeBarrages.length != before) setState(() {});
    }
    setState(() {});
  }

  Future<void> _loadData() async {
    try {
      final messages = await ApiService.getMessages();
      final stats = await ApiService.getStats();
      if (mounted) {
        setState(() {
          _allMessages = messages;
          _todayCount = stats['todayMessages'] ?? 0;
          _totalCount = stats['totalMessages'] ?? 0;
          _loading = false;
          _error = null;
        });
        _ensureMinMessages();
        _initDisplayQueue();
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

  void _ensureMinMessages() {
    if (_allMessages.length >= 15) return;
    const defaults = [
      '今天天气真好 ☀️', '路过... 有猫吗？🐱', '刚看完一部电影，推荐！',
      '下班好累 😫', '来都来了，留句话吧~', '今天有什么想说的？',
      '有人在吗？打个招呼 👋', '午饭吃什么好呢 🍜', '晚安，明天见 🌙',
      '突然想喝奶茶 🧋', '这个地方好安静', '今天的心情是蓝色',
    ];
    final fillCount = 15 - _allMessages.length;
    final rng = Random();
    for (int i = 0; i < fillCount; i++) {
      _allMessages.add(Message(
        id: 'default_$i',
        content: defaults[rng.nextInt(defaults.length)],
        authorName: 'Anonymous',
        isAnonymous: true,
        createdAt: DateTime.now().toIso8601String(),
        replies: [],
      ));
    }
  }

  void _initDisplayQueue() {
    _displayQueue = [..._allMessages]..shuffle();
    _startScheduler();
  }

  void _startScheduler() {
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _scheduleNext();
    });

    // 启动计时器
    if (!_stopwatch.isRunning) _stopwatch.start();

    // 初始同时发射2-3条
    final burst = min(3, _displayQueue.length);
    for (int i = 0; i < burst; i++) {
      Future.delayed(Duration(milliseconds: i * 600), () {
        if (mounted) _launchBarrage();
      });
    }
  }

  void _scheduleNext() {
    if (!mounted) return;
    if (_activeBarrages.length < _maxOnScreen && _displayQueue.isNotEmpty) {
      _launchBarrage();
    }
  }

  void _launchBarrage() {
    if (_displayQueue.isEmpty || !mounted) return;

    final msg = _displayQueue.removeAt(0);
    final track = _getAvailableTrack();
    final startTimeMs = _stopwatch.elapsedMilliseconds;

    setState(() => _activeBarrages.add(_ActiveBarrage(
      message: msg,
      track: track,
      startTimeMs: startTimeMs,
    )));

    // 启动 Ticker（如果还没启动）
    if (!_ticker.isActive) _ticker.start();

    // 队列还有就继续
    if (_displayQueue.isNotEmpty) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _launchBarrage();
      });
    } else if (_activeBarrages.isEmpty) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _initDisplayQueue();
      });
    }
  }

  int _getAvailableTrack() {
    final busyTracks = _activeBarrages.map((b) => b.track).toSet();
    final available = List.generate(_trackCount, (i) => i)
        .where((t) => !busyTracks.contains(t))
        .toList();
    if (available.isNotEmpty) {
      return available[Random().nextInt(available.length)];
    }
    return Random().nextInt(_trackCount);
  }

  void _openDetail(Message msg) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(messageId: msg.id),
      ),
    ).then((_) => _loadData());
  }

  Future<void> _showPostDialog() async {
    final controller = TextEditingController();
    String selectedMood = 'neutral';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1e1e3a),
          title: const Text('发布留言', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: '说点什么...',
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF48dbfb)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _moodChip('happy', '😊', selectedMood, (m) {
                    setDialogState(() => selectedMood = m);
                  }),
                  _moodChip('neutral', '😐', selectedMood, (m) {
                    setDialogState(() => selectedMood = m);
                  }),
                  _moodChip('sad', '😢', selectedMood, (m) {
                    setDialogState(() => selectedMood = m);
                  }),
                  _moodChip('excited', '🤩', selectedMood, (m) {
                    setDialogState(() => selectedMood = m);
                  }),
                  _moodChip('calm', '😌', selectedMood, (m) {
                    setDialogState(() => selectedMood = m);
                  }),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF48dbfb),
              ),
              onPressed: () async {
                if (controller.text.trim().isEmpty) return;
                try {
                  await ApiService.createMessage(
                    content: controller.text.trim(),
                    mood: selectedMood,
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('发布成功！')),
                  );
                  _loadData();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('发布失败: $e')),
                  );
                }
              },
              child: const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moodChip(String mood, String emoji, String selected, Function(String) onTap) {
    final isSelected = selected == mood;
    return GestureDetector(
      onTap: () => onTap(mood),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF48dbfb).withOpacity(0.3) : const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF48dbfb) : Colors.transparent,
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a1a),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF48dbfb),
          backgroundColor: const Color(0xFF1e1e3a),
          child: Stack(
            children: [
              // 星空背景
              Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.3),
                    radius: 1.2,
                    colors: [Color(0xFF1a1a3e), Color(0xFF0a0a1a)],
                  ),
                ),
              ),

              // 统计栏
              Positioned(
                top: 12,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '📊 今日: $_todayCount 条 | 总计: $_totalCount 条',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ),

              // 弹幕区域（Ticker 驱动重绘）
              if (!_loading && _error == null)
                ..._buildBarrageLayers(),

              // 加载/错误状态
              if (_loading)
                const Center(child: CircularProgressIndicator(color: Color(0xFF48dbfb)))
              else if (_error != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text('$_error', style: const TextStyle(color: Colors.white38)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadData,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF48dbfb)),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),

              // 空状态
              if (!_loading && _error == null && _allMessages.isEmpty && _activeBarrages.isEmpty)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('💬', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text('今天还没有留言，快来抢沙发！',
                          style: TextStyle(color: Colors.white38, fontSize: 15)),
                    ],
                  ),
                ),

              // 底部发布按钮
              Positioned(
                bottom: 20,
                right: 20,
                child: FloatingActionButton.extended(
                  onPressed: _showPostDialog,
                  backgroundColor: const Color(0xFF48dbfb),
                  icon: const Icon(Icons.edit, color: Colors.white),
                  label: const Text('留言', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBarrageLayers() {
    if (_screenWidth == 0) _screenWidth = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final trackHeight = (screenH - 120) / (_trackCount + 2);
    final now = _stopwatch.elapsedMilliseconds;
    final scrollMs = _scrollDuration.inMilliseconds;

    // 过滤已完成的弹幕
    _activeBarrages.removeWhere((b) => now - b.startTimeMs > scrollMs);

    return _activeBarrages.map((barrage) {
      final elapsed = now - barrage.startTimeMs;
      final progress = (elapsed / scrollMs).clamp(0.0, 1.0);
      final x = _screenWidth + 50 + (-_screenWidth - 350) * progress;
      final y = trackHeight * (barrage.track + 0.8);

      return Positioned(
        left: x,
        top: y,
        child: BarrageItem(
          message: barrage.message,
          onTap: () => _openDetail(barrage.message),
        ),
      );
    }).toList();
  }
}

class _ActiveBarrage {
  final Message message;
  final int track;
  final int startTimeMs;

  _ActiveBarrage({
    required this.message,
    required this.track,
    required this.startTimeMs,
  });
}
