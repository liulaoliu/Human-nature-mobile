import 'package:flutter/material.dart';

import 'views/home_page.dart';

void main() {
  runApp(const DlaoshiApp());
}

/// 应用根。现在只有主题与首页；仓储 / ViewModel 的注入等一期主链路
/// （词库 → 精读 → 背单词）接上后再加到 `MultiProvider` 里。
class DlaoshiApp extends StatelessWidget {
  const DlaoshiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D老师帮你办',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D7EFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
