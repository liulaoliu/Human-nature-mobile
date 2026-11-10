// 仿写历史子视图的 smoke：空库给空态 + 本篇 / 全库筛选。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/writing_history_view.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('WritingHistoryView 空库：范围筛选与空态文案', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(
      tester,
      smokeApp(
        db,
        const Scaffold(body: SafeArea(child: WritingHistoryView())),
      ),
    );

    expect(find.text('本篇'), findsOneWidget);
    expect(find.text('全库'), findsOneWidget);
    expect(find.text('这个范围内还没有记录。'), findsOneWidget);

    await smokeFinish(tester);
  });
}
