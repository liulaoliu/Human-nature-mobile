// 阅读页的 smoke：空库（没有打开文章）时给空态文案。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/reader_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('ReaderPage 空态：没有打开的文章', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const ReaderPage()));

    // 该页特有的空态文案（不是只 find.byType）。
    expect(find.text('没有打开的文章'), findsOneWidget);

    await smokeFinish(tester);
  });
}
