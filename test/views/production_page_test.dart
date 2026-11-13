// D老师奶牛工棚页的 smoke：三 Tab 文案齐全。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/production_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('ProductionPage：标题与出题 / 练习 / 历史三 Tab', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const ProductionPage()));

    expect(find.text('D老师奶牛工棚'), findsOneWidget);
    expect(find.text('出题'), findsOneWidget);
    expect(find.text('练习'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);

    await smokeFinish(tester);
  });
}
