// 金句课页的 smoke：四 Tab 文案齐全。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/golden_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('GoldenPage：标题与挑句 / 练习 / 金句本 / 历史四 Tab',
      (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const GoldenPage()));

    expect(find.text('D老师小课堂'), findsOneWidget);
    expect(find.text('挑句'), findsOneWidget);
    expect(find.text('练习'), findsOneWidget);
    expect(find.text('金句本'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);

    await smokeFinish(tester);
  });
}
