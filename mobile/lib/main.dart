import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaoziMessageApp());
}

class MaoziMessageApp extends StatelessWidget {
  const MaoziMessageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '帽子留言',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0a1a),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF48dbfb),
          secondary: const Color(0xFF48dbfb),
          surface: const Color(0xFF1e1e3a),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1e1e3a),
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF48dbfb),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
