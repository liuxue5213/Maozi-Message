import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLogin = true;
  bool _busy = false;
  String _error = '';
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _nickname = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.length < 3) {
      setState(() => _error = '用户名至少 3 个字符');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '密码至少 6 位');
      return;
    }
    if (!_isLogin && _nickname.text.trim().isEmpty) {
      setState(() => _error = '请填写昵称');
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      if (_isLogin) {
        await ApiService.login(username: username, password: password);
      } else {
        await ApiService.register(
          username: username,
          password: password,
          nickname: _nickname.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        // Exception('xxx') 会带外层包装，剥掉显示友好信息
        var msg = e.toString();
        if (msg.startsWith('Exception: ')) msg = msg.substring(11);
        _error = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1e1e3a),
        title: Text(_isLogin ? '登录' : '注册',
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isLogin ? '欢迎回来 👋' : '创建新账号 ✨',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _username,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco('用户名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco('密码（至少6位）'),
              ),
              if (!_isLogin) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _nickname,
                  style: const TextStyle(color: Colors.white),
                  maxLength: 20,
                  decoration: _inputDeco('昵称（对外展示）'),
                  counterStyle:
                      const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
              const SizedBox(height: 8),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error,
                      style:
                          const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13)),
                ),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF48dbfb),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isLogin ? '登录' : '注册',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _isLogin = !_isLogin;
                          _error = '';
                        }),
                child: Text(
                  _isLogin ? '没有账号？去注册' : '已有账号？去登录',
                  style: const TextStyle(color: Color(0xFF48dbfb)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: const Color(0x1AFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF48dbfb)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}
