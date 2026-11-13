// 仿写页的 smoke：两 Tab 文案齐全。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/writing_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('WritingPage：标题与仿写 / 历史两 Tab', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const WritingPage()));

    // 标题与第一个 Tab 都叫「仿写」。
    expect(find.text('仿写'), findsNWidgets(2));
    expect(find.text('历史'), findsOneWidget);

    await smokeFinish(tester);
  });
}
