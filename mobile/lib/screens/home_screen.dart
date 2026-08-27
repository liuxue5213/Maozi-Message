import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../widgets/barrage_item.dart';
import 'detail_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  List<Message> _allMessages = [];
  List<Message> _displayQueue = [];
  final List<_ActiveBarrage> _activeBarrages = [];
  final Set<String> _displayedIds = {};
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;
  Timer? _schedulerTimer;
  int _todayCount = 0;
  int _totalCount = 0;

  static const int _trackCount = 5;
  static const int _maxOnScreen = 5;
  // 恒定弹幕速度（像素/毫秒），观感对齐 Web 端
  static const double _speedPxPerMs = 0.055;
  static const int _minDurationMs = 8000;
  static const int _maxDurationMs = 26000;

  Duration _calcGap() {
    final n = _allMessages.length;
    if (n <= 5) return const Duration(milliseconds: 800);
    if (n <= 15) return const Duration(milliseconds: 1500);
    if (n <= 30) return const Duration(milliseconds: 2500);
    return const Duration(milliseconds: 3500);
  }

  late final Ticker _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  // 只驱动弹幕层局部重建，绝不重建全页
  final ValueNotifier<int> _tickFrame = ValueNotifier(0);
  double _screenWidth = 400; // 每次 build 刷新，spawn 前兜底
  int _lastLaunchTimeMs = 0;

  // WebSocket 实时推送
  WebSocketChannel? _ws;
  Timer? _wsRetry;
  int _wsBackoffSec = 1;
  bool _disposing = false;
  bool _wsConnected = false;

  // 轮询频率自适应：WS 在线 2 分钟兜底一次；断线 30 秒高频补偿
  void _startPolling() {
    _refreshTimer?.cancel();
    final interval =
        _wsConnected ? const Duration(minutes: 2) : const Duration(seconds: 30);
    if (_disposing || !mounted) return;
    _refreshTimer = Timer.periodic(interval, (_) => _loadData());
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _connectWs();
    _loadData();
    _startPolling();
    _loadSession();
  }

  bool _loggedIn = false;
  String _nickname = '';
  String _avatarColor = '#48dbfb';

  Future<void> _loadSession() async {
    final logged = await ApiService.isLoggedIn();
    final user = await ApiService.getSession();
    if (!mounted) return;
    setState(() {
      _loggedIn = logged;
      _nickname = (user?['nickname'] as String?) ?? '';
      _avatarColor = (user?['avatar_color'] as String?) ?? '#48dbfb';
    });
  }

  Future<void> _openAccount() async {
    if (!_loggedIn) {
      final okLogin = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (okLogin == true && mounted) {
        await _loadSession();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('欢迎，$_nickname')),
        );
        _loadData(); // 拉取后 mine 标记随 token 生效
      }
      return;
    }
    // 已登录：底部弹层展示资料与注销
    final colorHex = _avatarColor.replaceFirst('#', 'ff');
    final avatarColor = Color(int.parse(colorHex, radix: 16));
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1e1e3a),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: avatarColor,
                    child: Text(
                      _nickname.isNotEmpty ? _nickname.characters.first : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_nickname,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 17)),
                        const SizedBox(height: 2),
                        Text('登录身份 · 留言显示真实昵称',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.45),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetCtx);
                  await ApiService.logout();
                  if (!mounted) return;
                  setState(() {
                    _loggedIn = false;
                    _nickname = '';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已退出登录')),
                  );
                  _loadData();
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('退出登录'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B6B),
                  side: BorderSide(color: Colors.red.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposing = true;
    _refreshTimer?.cancel();
    _schedulerTimer?.cancel();
    _wsRetry?.cancel();
    _ws?.sink.close();
    _ticker.dispose();
    _tickFrame.dispose();
    super.dispose();
  }

  // ws://host:60175/ws，由 http base 推导
  Uri get _wsUri => Uri.parse(
        ApiService.baseUrl
            .replaceFirst(RegExp(r'^http'), 'ws')
            .replaceFirst(RegExp(r'/api/?$'), '/ws'),
      );

  void _connectWs() {
    if (_disposing) return;
    try {
      _ws = WebSocketChannel.connect(_wsUri);
      _wsConnected = true;
      _wsBackoffSec = 1;
      _startPolling(); // 实时通道可用：轮询降为低频兜底
      _ws!.stream.listen(
        (raw) => _handleWsEvent(raw is String ? raw : utf8.decode(raw as List<int>)),
        onError: (_) => _onWsDown(),
        onDone: _onWsDown,
      );
    } catch (_) {
      _onWsDown();
    }
  }

  void _onWsDown() {
    if (_disposing) return;
    final wasConnected = _wsConnected;
    _wsConnected = false;
    _scheduleWsRetry();
    if (wasConnected) _startPolling(); // 断线恢复高频轮询兜底
  }

  void _scheduleWsRetry() {
    if (_disposing) return;
    _wsRetry?.cancel();
    _wsRetry = Timer(Duration(seconds: _wsBackoffSec), () {
      if (_disposing || !mounted) return;
      _connectWs();
      _wsBackoffSec = (_wsBackoffSec * 2).clamp(1, 30);
    });
  }

  void _handleWsEvent(String raw) {
    if (!mounted) return;
    try {
      final event = jsonDecode(raw) as Map<String, dynamic>;
      switch (event['type']) {
        case 'new_message':
          final msg = Message.fromJson((event['data'] ?? {}) as Map<String, dynamic>);
          if (msg.id.isEmpty || _displayedIds.contains(msg.id)) break;
          // 若本地已有同 ID（刚发布的临时数据被服务器刷新补齐），跳过
          if (_allMessages.any((m) => m.id == msg.id)) break;
          _allMessages.insert(0, msg);
          _displayQueue.insert(0, msg); // 插队头，下个空位立刻飞出
          // 空闲轮次中收到新留言：立即唤醒调度
          if (!_stopwatch.isRunning) {
            _stopwatch.start();
            _startScheduler();
          }
          break;
        case 'new_reply':
          final data = (event['data'] ?? {}) as Map<String, dynamic>;
          final mid = data['message_id'] as String?;
          final reply = data['reply'];
          if (mid == null || reply == null) break;
          final idx = _allMessages.indexWhere((m) => m.id == mid);
          if (idx != -1 && !_allMessages[idx].replies.any((r) => r.id == reply['id'])) {
            _allMessages[idx] = Message(
              id: _allMessages[idx].id,
              content: _allMessages[idx].content,
              authorName: _allMessages[idx].authorName,
              color: _allMessages[idx].color,
              bgColor: _allMessages[idx].bgColor,
              mood: _allMessages[idx].mood,
              isAnonymous: _allMessages[idx].isAnonymous,
              likesCount: _allMessages[idx].likesCount,
              dislikesCount: _allMessages[idx].dislikesCount,
              repliesCount: _allMessages[idx].repliesCount + 1,
              createdAt: _allMessages[idx].createdAt,
              myVote: _allMessages[idx].myVote,
              mine: _allMessages[idx].mine,
              replies: [..._allMessages[idx].replies, Reply.fromJson(reply)],
            );
          }
          break;
        case 'message_deleted':
          final id = (event['data'] ?? {})['id'];
          if (id is! String) break;
          _allMessages.removeWhere((m) => m.id == id);
          _displayQueue.removeWhere((m) => m.id == id);
          final before = _activeBarrages.length;
          _activeBarrages.removeWhere((b) => b.message.id == id);
          if (_activeBarrages.length != before) _tickFrame.value++;
          break;
        default:
          break; // vote_update 等事件由详情页自行拉取
      }
    } catch (_) {/* 坏包忽略 */}
  }

  // Ticker 回调：只做过期清理 + 循环检测 + 弹幕层帧通知
  void _onTick(Duration _) {
    if (_activeBarrages.isNotEmpty) {
      final now = _stopwatch.elapsedMilliseconds;
      _activeBarrages.removeWhere((b) => now - b.startTimeMs > b.durationMs);
    }
    if (_activeBarrages.isEmpty && _displayQueue.isEmpty) {
      _ticker.stop();
      _stopwatch.stop();
      _displayedIds.clear(); // 清空已显示记录，实现无限循环
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _initDisplayQueue();
      });
    }
    _tickFrame.value++;
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
        id: 'default_${DateTime.now().millisecondsSinceEpoch}_$i',
        content: defaults[rng.nextInt(defaults.length)],
        authorName: '匿名',
        isAnonymous: true,
        createdAt: DateTime.now().toIso8601String(),
        replies: [],
      ));
    }
  }

  void _initDisplayQueue() {
    // 排除已在队列中或正在显示的留言，避免重复
    final existingIds = _displayQueue.map((m) => m.id).toSet();
    for (final b in _activeBarrages) {
      existingIds.add(b.message.id);
    }
    final newMessages = _allMessages
        .where((m) => !_displayedIds.contains(m.id) && !existingIds.contains(m.id))
        .toList();
    _displayQueue = [..._displayQueue, ...newMessages]..shuffle();
    _startScheduler();
  }

  void _startScheduler() {
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _scheduleNext());

    if (!_stopwatch.isRunning) _stopwatch.start();

    // 开场连发 2-3 条（绕过间隔但受屏显上限约束）
    final burst = min(3, _displayQueue.length);
    for (int i = 0; i < burst; i++) {
      Future.delayed(Duration(milliseconds: i * 400), () {
        if (mounted) _launchOneNow();
      });
    }
  }

  void _scheduleNext() {
    if (!mounted || _displayQueue.isEmpty) return;
    if (_activeBarrages.length >= _maxOnScreen) return;
    final gapMs = _calcGap().inMilliseconds;
    if (_stopwatch.elapsedMilliseconds - _lastLaunchTimeMs < gapMs) return;
    _launchOneNow();
  }

  // 无视间隔立即发射一条（开场 burst / 自己刚发布的留言）
  void _launchOneNow({Message? direct}) {
    if (!mounted) return;
    if (_activeBarrages.length >= _maxOnScreen) return;
    final Message msg;
    if (direct != null) {
      msg = direct;
      _displayedIds.add(msg.id);
    } else {
      if (_displayQueue.isEmpty) return;
      msg = _displayQueue.removeAt(0);
      _displayedIds.add(msg.id);
    }
    _addActive(msg);
  }

  void _addActive(Message msg) {
    final track = _getAvailableTrack();
    final w = _estimateWidth(msg.content, msg.authorName);
    final distance = _screenWidth + w + 60;
    var durationMs = (distance / _speedPxPerMs).round();
    durationMs = durationMs.clamp(_minDurationMs, _maxDurationMs);

    _activeBarrages.add(_ActiveBarrage(
      message: msg,
      track: track,
      startTimeMs: _stopwatch.elapsedMilliseconds,
      durationMs: durationMs,
      distanceX: distance,
    ));
    _lastLaunchTimeMs = _stopwatch.elapsedMilliseconds;

    if (!_ticker.isActive) _ticker.start();
    _tickFrame.value++;
  }

  // 预估弹幕渲染宽度：文本 + 作者徽标 + 内边距 + 图标间隙
  double _estimateWidth(String content, String authorName) {
    final maxW = _screenWidth * 0.65;
    final tp = TextPainter(
      text: TextSpan(text: content, style: const TextStyle(fontSize: 14)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxW - 90);
    var w = tp.width + 90; // 90 ≈ padding(28)+图标(18)+间距(10)+作者+点赞余量
    tp.dispose();
    return w.clamp(120.0, maxW);
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
        builder: (_) => DetailScreen(messageId: msg.id, preview: msg),
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
              Text(
                _loggedIn ? '以「$_nickname」身份发布' : '匿名身份 · 右上角可登录',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 11),
              ),
              const SizedBox(height: 10),
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
                  _moodChip('happy', '😊', selectedMood, (m) => setDialogState(() => selectedMood = m)),
                  _moodChip('neutral', '😐', selectedMood, (m) => setDialogState(() => selectedMood = m)),
                  _moodChip('sad', '😢', selectedMood, (m) => setDialogState(() => selectedMood = m)),
                  _moodChip('excited', '🤩', selectedMood, (m) => setDialogState(() => selectedMood = m)),
                  _moodChip('calm', '😌', selectedMood, (m) => setDialogState(() => selectedMood = m)),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF48dbfb)),
              onPressed: () async {
                final content = controller.text.trim();
                if (content.isEmpty) return;
                try {
                  final created = await ApiService.createMessage(
                    content: content,
                    mood: selectedMood,
                    isAnonymous: !_loggedIn,
                  );
                  // 本地立刻上屏（不等轮询）；屏满则插队头等下一个空位
                  if (_activeBarrages.length < _maxOnScreen) {
                    if (!_stopwatch.isRunning) _stopwatch.start();
                    _launchOneNow(direct: created);
                  } else {
                    _displayQueue.insert(0, created);
                  }
                  if (mounted) Navigator.pop(ctx);
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
    _screenWidth = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a1a),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF48dbfb),
          backgroundColor: const Color(0xFF1e1e3a),
          child: Stack(
            children: [
              // 可滚动锚层：让 RefreshIndicator 的下拉手势生效
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(height: screenH),
                ),
              ),

              // 星空背景
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.3),
                      radius: 1.2,
                      colors: [Color(0xFF1a1a3e), Color(0xFF0a0a1a)],
                    ),
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

              // 账号入口（右上角）
              Positioned(
                top: 10,
                right: 16,
                child: GestureDetector(
                  onTap: _openAccount,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _loggedIn
                          ? const Color(0xFF48dbfb).withOpacity(0.15)
                          : Colors.black54,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _loggedIn
                            ? const Color(0xFF48dbfb).withOpacity(0.6)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _loggedIn
                              ? Icons.verified_user_rounded
                              : Icons.person_outline_rounded,
                          size: 14,
                          color: _loggedIn
                              ? const Color(0xFF48dbfb)
                              : Colors.white54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _loggedIn ? _nickname : '登录',
                          style: TextStyle(
                            color: _loggedIn
                                ? const Color(0xFF48dbfb)
                                : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 弹幕层：ValueListenableBuilder 只重建这一小层
              if (!_loading && _error == null)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: false,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _tickFrame,
                      builder: (context, _, __) {
                        final nowMs = _stopwatch.elapsedMilliseconds;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: _activeBarrages.map((barrage) {
                            final progress =
                                ((nowMs - barrage.startTimeMs) / barrage.durationMs).clamp(0.0, 1.0);
                            return Positioned(
                              left: _screenWidth + 50 - barrage.distanceX * progress,
                              top: (screenH - 120) / (_trackCount + 2) * (barrage.track + 0.8),
                              child: BarrageItem(
                                message: barrage.message,
                                onTap: () => _openDetail(barrage.message),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ),

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
}

class _ActiveBarrage {
  final Message message;
  final int track;
  final int startTimeMs;
  final int durationMs; // 各条独立时长（恒速飞行）
  final double distanceX; // 本次飞行的总距离

  String get id => message.id;

  _ActiveBarrage({
    required this.message,
    required this.track,
    required this.startTimeMs,
    required this.durationMs,
    required this.distanceX,
  });
}
