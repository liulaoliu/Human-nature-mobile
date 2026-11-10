// 金句练习子视图的 smoke：未选题给「去挑句」空态，onGoPlan 用顶层 _noop。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/golden_drill_view.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('GoldenDrillView 未选题：还没开始练与去挑句按钮', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(
      tester,
      smokeApp(
        db,
        const Scaffold(body: SafeArea(child: GoldenDrillView(onGoPlan: _noop))),
      ),
    );

    expect(find.text('还没开始练。'), findsOneWidget);
    expect(find.text('先去挑句页选一句，再回来练。'), findsOneWidget);
    expect(find.text('去挑句'), findsOneWidget);

    await smokeFinish(tester);
  });
}

void _noop() {}
