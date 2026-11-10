// 金句本子视图的 smoke：空库给搜索框、筛出 0 句与空态文案。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/golden_bank_view.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('GoldenBankView 空库：搜索框、筛出 0 句与空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(
      tester,
      smokeApp(
        db,
        const Scaffold(body: SafeArea(child: GoldenBankView())),
      ),
    );

    expect(find.text('搜正文 / 译文 / 学习点'), findsOneWidget);
    expect(find.text('筛出 0 句'), findsOneWidget);
    expect(find.text('还没有金句课。先去「挑句」给一篇文章做一课。'),
        findsOneWidget);

    await smokeFinish(tester);
  });
}
