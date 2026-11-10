// 拷打造句页的 smoke：空材料给出题空态，断言标题 / 顶栏 / 吸底按钮。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/drill_sentence.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/views/drill_sentence_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('DrillSentencePage 空题：记忆拷打标题与空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(
      tester,
      smokeApp(
        db,
        const DrillSentencePage(
          items: <VocabItem>[],
          results: <({String? id, String itemId})>[],
          kind: DrillSentenceKind.memory,
        ),
      ),
    );

    expect(find.text('记忆拷打 · 造句'), findsOneWidget);
    expect(find.text('这一轮没有题目'), findsOneWidget);
    expect(find.text('批改这一稿'), findsOneWidget);

    await smokeFinish(tester);
  });
}
