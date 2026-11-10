// 产出历史子视图的 smoke：空库给空态文案。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/production_history_view.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('ProductionHistoryView 空库：还没有产出记录空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(
      tester,
      smokeApp(
        db,
        const Scaffold(body: SafeArea(child: ProductionHistoryView())),
      ),
    );

    expect(find.text('还没有产出记录。练几题，这里就会有统计。'), findsOneWidget);

    await smokeFinish(tester);
  });
}
