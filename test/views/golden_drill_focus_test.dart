// 金句练习：进填空界面就自动聚焦第一个空，不用用户先点一下输入框。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/viewmodels/golden_drill_session.dart';
import 'package:dlaoshi_app/views/golden_drill_view.dart';
import 'smoke_harness.dart';

SavedArticle _article() {
  const sentence = Sentence(
    id: 's1',
    paraId: 'p01',
    text: 'We keep up with the news every morning.',
    translation: '我们每天早上都跟上新闻。',
  );
  return SavedArticle(
    id: 'a1',
    title: '测试篇',
    paragraphs: <Paragraph>[
      const Paragraph(id: 'p01', sentenceIds: <String>['s1']),
    ],
    sentences: const <Sentence>[sentence],
    golden: const GoldenLesson(
      source: GoldenSource.ai,
      sentences: <GoldenSentence>[
        GoldenSentence(
          id: 's1',
          zh: '我们每天早上都跟上新闻。',
          targets: <GoldenTarget>[
            GoldenTarget(
              en: 'keep up with',
              kind: GoldenTargetKind.collocation,
              zh: '跟上',
            ),
          ],
        ),
      ],
      selected: <String>['s1'],
    ).toJson(),
    updatedAt: '2026-11-13T00:00:00.000Z',
  );
}

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('填空界面：进来第一个空就有光标，不用点', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    // 真 SQLite 是真实异步 IO，必须放在 runAsync 里，否则在假时钟下永远不完成。
    await tester.runAsync(() => ArticleRepository(db).save(_article()));

    await smokePump(
      tester,
      smokeApp(
        db,
        const Scaffold(body: SafeArea(child: GoldenDrillView(onGoPlan: _noop))),
      ),
    );

    // 把这个 VM 拉到「某一句正在练填空」的状态。
    await tester.runAsync(() async {
      await smokeGolden.bootstrap();
      await smokeGolden.openArticle('a1');
      smokeGolden.drill.open('s1');
    });
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(smokeGolden.drill.phase, GoldenDrillPhase.fill);
    final fields = find.byType(TextField);
    expect(fields, findsWidgets);

    // 第一个空的 focusNode 拿到了焦点 —— 用户不用点，直接就能打字。
    final first = tester.widget<TextField>(fields.first);
    expect(first.focusNode, isNotNull);
    expect(first.focusNode!.hasFocus, isTrue);
    expect(
      tester.binding.focusManager.primaryFocus,
      same(first.focusNode),
      reason: '第一个空应该是主焦点',
    );

    await smokeFinish(tester);
  });
}

void _noop() {}
