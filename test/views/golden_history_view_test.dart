// 金句历史子视图的 smoke：未挑文章给「先挑一篇文章」空态。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/golden_history_view.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('GoldenHistoryView 未挑文章：先挑一篇文章空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(
      tester,
      smokeApp(
        db,
        const Scaffold(body: SafeArea(child: GoldenHistoryView())),
      ),
    );

    expect(find.text('先挑一篇文章，才看得到它的练习记录。'), findsOneWidget);

    await smokeFinish(tester);
  });
}
