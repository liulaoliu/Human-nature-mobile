// 精读文章列表页的 smoke：空库给空态 + 粘贴新建入口。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/articles_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('ArticlesPage 空库：标题、粘贴新建与空态文案', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const ArticlesPage()));

    expect(find.text('精读'), findsOneWidget);
    expect(find.text('粘贴新建'), findsOneWidget);
    expect(find.text('还没有文章'), findsOneWidget);
    expect(find.text('点右下角「粘贴新建」，把一段英文贴进来就能开始精读。'),
        findsOneWidget);

    await smokeFinish(tester);
  });
}
