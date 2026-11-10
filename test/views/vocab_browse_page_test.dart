// 词库浏览页的 smoke：空库给搜索框与空态文案。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/vocab_browse_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('VocabBrowsePage 空库：词库计数、搜索框与空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const VocabBrowsePage()));

    expect(find.text('词库（0）'), findsOneWidget);
    expect(find.text('搜单词 / 释义 / 笔记'), findsOneWidget);
    expect(find.text('这个筛选下没有词。换个范围或清掉日期试试。'),
        findsOneWidget);

    await smokeFinish(tester);
  });
}
