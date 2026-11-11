// 首页的 smoke：纯 MaterialApp 即可，不需要 Provider / SQLite。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/home_page.dart';

void main() {
  testWidgets('HomePage 能渲染标题与十条入口', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();

    expect(find.text('D哥帮你办'), findsOneWidget);
    expect(find.text('今天想练什么？'), findsOneWidget);
    expect(find.text('精读'), findsOneWidget);
    expect(find.text('速读'), findsOneWidget);
    expect(find.text('AI 跑批'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(10));
  });
}
