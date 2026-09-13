import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

class ApiService {
  // 通过 --dart-define=API_BASE_URL=https://example.com/api 配置生产地址。
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://120.48.13.152:60175/api',
  );
  static const Duration _timeout = Duration(seconds: 15);

  static const String _tokenKey = 'mz_token';
  static const String _userKey = 'mz_user';
  static const String _fpKey = 'mz_fp';

  static String? _fingerprint;
  static String? _token;

  // ---------- 会话 ----------

  static Future<String> _getFingerprint() async {
    if (_fingerprint != null) return _fingerprint!;
    final prefs = await SharedPreferences.getInstance();
    _fingerprint = prefs.getString(_fpKey);
    if (_fingerprint == null) {
      _fingerprint =
          DateTime.now().millisecondsSinceEpoch.toString() +
          (1000 + DateTime.now().microsecond % 9000).toString();
      await prefs.setString(_fpKey, _fingerprint!);
    }
    return _fingerprint!;
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    return _token != null;
  }

  /// 登录后缓存的用户资料 {id, username, nickname, avatar_color}
  static Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  static Future<void> _saveSession(String token, Map<String, dynamic> user) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));
  }

  // ---------- 请求头 ----------

  static Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    await _loadToken();
    await _getFingerprint();
    return <String, String>{
      'X-Fingerprint': _fingerprint ?? '',
      if (jsonBody) 'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  static Future<void> _loadToken() async {
    if (_token != null) return;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  // ---------- 认证 ----------

  /// 注册并保存会话，返回用户资料
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String nickname,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/auth/register'),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({
            'username': username,
            'password': password,
            'nickname': nickname,
          }),
        )
        .timeout(_timeout);
    return _finishAuth(res);
  }

  /// 登录并保存会话，返回用户资料
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/auth/login'),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(_timeout);
    return _finishAuth(res);
  }

  static Future<Map<String, dynamic>> _finishAuth(http.Response res) async {
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      final token = data['data']['token'] as String?;
      final user = (data['data']['user'] ?? {}) as Map<String, dynamic>;
      if (token == null) throw Exception('服务未返回令牌');
      await _saveSession(token, user);
      return user;
    }
    throw Exception(data['error'] ?? '认证失败');
  }

  // ---------- 留言 ----------

  /// 当前身份标识：登录用户取 uid，匿名取设备指纹（与后端 author_id 规则一致）
  static Future<String> myIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_tokenKey) != null) {
      final user = await getSession();
      final id = user?['id'];
      if (id is String && id.isNotEmpty) return id;
    }
    return _getFingerprint();
  }

  /// 获取留言列表：默认今日；date 指定日期；mine=true 查当前登录用户的全部留言
  static Future<List<Message>> getMessages({int limit = 200, String? date, bool mine = false}) async {
    final params = <String>['limit=$limit'];
    if (date != null) params.add('date=$date');
    if (mine) params.add('mine=1');
    final res = await http.get(
      Uri.parse('$baseUrl/messages?${params.join('&')}'),
      headers: await _headers(),
    ).timeout(_timeout);
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return (data['data'] as List)
          .map((m) => Message.fromJson(m))
          .toList();
    }
    throw Exception(data['error'] ?? '加载失败');
  }

  /// 获取单条留言详情
  static Future<Message> getMessage(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/messages/$id'),
      headers: await _headers(),
    ).timeout(_timeout);
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return Message.fromJson(data['data']);
    }
    throw Exception(data['error'] ?? '加载失败');
  }

  /// 发布留言（登录则用真实昵称，未登录匿名）
  static Future<Message> createMessage({
    required String content,
    bool isAnonymous = true,
    String mood = 'neutral',
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/messages'),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({
            'content': content,
            'is_anonymous': isAnonymous,
            'mood': mood,
          }),
        )
        .timeout(_timeout);
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return Message.fromJson(data['data']);
    }
    throw Exception(data['error'] ?? '发布失败');
  }

  /// 回复留言
  static Future<Reply> replyToMessage({
    required String messageId,
    required String content,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/messages/$messageId/reply'),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'content': content}),
        )
        .timeout(_timeout);
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return Reply.fromJson(data['data']);
    }
    throw Exception(data['error'] ?? '回复失败');
  }

  /// 投票（点赞/踩），返回 {likes, dislikes, my_vote}
  static Future<Map<String, dynamic>> vote({
    required String type,
    required String id,
    required String voteType,
  }) async {
    final endpoint = type == 'message'
        ? '$baseUrl/messages/$id/vote'
        : '$baseUrl/replies/$id/vote';
    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'vote_type': voteType}),
        )
        .timeout(_timeout);
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return data['data'];
    }
    throw Exception(data['error'] ?? '投票失败');
  }

  /// 删除自己的留言（需登录）
  static Future<void> deleteMessage(String id) async {
    final res = await http
        .delete(Uri.parse('$baseUrl/messages/$id'), headers: await _headers())
        .timeout(_timeout);
    final data = jsonDecode(res.body);
    if (data['success'] != true) {
      throw Exception(data['error'] ?? '删除失败');
    }
  }

  /// 举报留言/回复（匿名可举报）
  static Future<void> report({
    required String type,
    required String id,
    String reason = '',
  }) async {
    final endpoint = type == 'message'
        ? '$baseUrl/messages/$id/report'
        : '$baseUrl/replies/$id/report';
    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'reason': reason}),
        )
        .timeout(_timeout);
    final data = jsonDecode(res.body);
    if (data['success'] != true) {
      throw Exception(data['error'] ?? '举报失败');
    }
  }

  /// 获取统计数据
  static Future<Map<String, dynamic>> getStats() async {
    final res = await http.get(
      Uri.parse('$baseUrl/stats'),
      headers: await _headers(),
    ).timeout(_timeout);
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return data['data'];
    }
    throw Exception(data['error'] ?? '加载失败');
  }
}
