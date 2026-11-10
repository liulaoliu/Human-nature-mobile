// 金句挑句子视图的 smoke：空库给「先去精读」空态，onStarted 用顶层 _noop。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/golden_plan_view.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('GoldenPlanView 空库：还没有文章空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(
      tester,
      smokeApp(
        db,
        const Scaffold(body: SafeArea(child: GoldenPlanView(onStarted: _noop))),
      ),
    );

    expect(find.text('还没有文章。先去「精读」里粘一篇原文。'), findsOneWidget);

    await smokeFinish(tester);
  });
}

void _noop() {}
