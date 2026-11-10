// AI 跑批页的 smoke：连接设置 / 本轮进度卡片与按钮文案。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/ai_batch_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('AiBatchPage：标题、连接设置与开始跑批', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const AiBatchPage()));

    expect(find.text('AI 跑批'), findsOneWidget);
    expect(find.text('连接设置'), findsOneWidget);
    expect(find.text('本轮进度'), findsOneWidget);
    expect(find.text('保存到本机'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('开始跑批'), findsOneWidget);

    await smokeFinish(tester);
  });
}
