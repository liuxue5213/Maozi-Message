import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

class ApiService {
  // 服务器地址 - 打包时修改为你的服务器IP
  static const String baseUrl = 'http://120.48.13.152:60175/api';

  static String? _fingerprint;

  static Future<String> _getFingerprint() async {
    if (_fingerprint != null) return _fingerprint!;
    final prefs = await SharedPreferences.getInstance();
    _fingerprint = prefs.getString('mz_fp');
    if (_fingerprint == null) {
      _fingerprint =
          DateTime.now().millisecondsSinceEpoch.toString() +
          (1000 + DateTime.now().microsecond % 9000).toString();
      await prefs.setString('mz_fp', _fingerprint!);
    }
    return _fingerprint!;
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Fingerprint': _fingerprint ?? '',
      };

  /// 获取今日留言列表
  static Future<List<Message>> getMessages({int limit = 200}) async {
    final fp = await _getFingerprint();
    final res = await http.get(
      Uri.parse('$baseUrl/messages?limit=$limit'),
      headers: {'X-Fingerprint': fp},
    );
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
    final fp = await _getFingerprint();
    final res = await http.get(
      Uri.parse('$baseUrl/messages/$id'),
      headers: {'X-Fingerprint': fp},
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return Message.fromJson(data['data']);
    }
    throw Exception(data['error'] ?? '加载失败');
  }

  /// 发布留言
  static Future<Message> createMessage({
    required String content,
    String? authorName,
    bool isAnonymous = true,
    String mood = 'neutral',
    String? color,
  }) async {
    final fp = await _getFingerprint();
    final res = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: {'X-Fingerprint': fp, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'content': content,
        'author_name': authorName,
        'is_anonymous': isAnonymous,
        'mood': mood,
        'color': color,
      }),
    );
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
    String? authorName,
    bool isAnonymous = true,
  }) async {
    final fp = await _getFingerprint();
    final res = await http.post(
      Uri.parse('$baseUrl/messages/$messageId/reply'),
      headers: {'X-Fingerprint': fp, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'content': content,
        'author_name': authorName,
        'is_anonymous': isAnonymous,
      }),
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return Reply.fromJson(data['data']);
    }
    throw Exception(data['error'] ?? '回复失败');
  }

  /// 投票（点赞/踩）
  static Future<Map<String, dynamic>> vote({
    required String type,
    required String id,
    required String voteType,
  }) async {
    final fp = await _getFingerprint();
    final endpoint = type == 'message'
        ? '$baseUrl/messages/$id/vote'
        : '$baseUrl/replies/$id/vote';
    final res = await http.post(
      Uri.parse(endpoint),
      headers: {'X-Fingerprint': fp, 'Content-Type': 'application/json'},
      body: jsonEncode({'vote_type': voteType}),
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return data['data'];
    }
    throw Exception(data['error'] ?? '投票失败');
  }

  /// 获取统计数据
  static Future<Map<String, dynamic>> getStats() async {
    final fp = await _getFingerprint();
    final res = await http.get(
      Uri.parse('$baseUrl/stats'),
      headers: {'X-Fingerprint': fp},
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      return data['data'];
    }
    throw Exception(data['error'] ?? '加载失败');
  }
}
