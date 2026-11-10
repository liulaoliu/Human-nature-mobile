// 跟读页的 smoke：无文章时给空态文案。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/shadowing_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('ShadowingPage 空库：标题与「先去精读」空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const ShadowingPage()));

    expect(find.text('跟读'), findsOneWidget);
    expect(find.text('还没有文章。先去「精读」粘一篇原文，再回来跟读。'),
        findsOneWidget);

    await smokeFinish(tester);
  });
}
