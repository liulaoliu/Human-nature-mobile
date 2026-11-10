// 背单词页的 smoke：未开轮时给设置面板（范围 / 学新词 / 候选数）。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/study_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('StudyPage 设置态：标题、范围与学新词入口', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const StudyPage()));

    expect(find.text('背单词'), findsOneWidget);
    expect(find.text('范围'), findsOneWidget);
    expect(find.text('学新词'), findsOneWidget);
    expect(find.text('候选 0 个'), findsOneWidget);

    await smokeFinish(tester);
  });
}
