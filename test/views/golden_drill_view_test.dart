// 金句练习子视图的 smoke：未选题给「去挑句」空态；进填空轮次后顶部黑框撤掉。
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

  testWidgets('GoldenDrillView 未选题：还没开始练与去挑句按钮', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(
      tester,
      smokeApp(
        db,
        const Scaffold(body: SafeArea(child: GoldenDrillView(onGoPlan: _noop))),
      ),
    );

    expect(find.text('还没开始练。'), findsOneWidget);
    expect(find.text('先去挑句页选一句，再回来练。'), findsOneWidget);
    expect(find.text('去挑句'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('填空阶段不画顶部黑框，进度挪进填空区', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await tester.runAsync(() => ArticleRepository(db).save(_article()));
    await smokePump(
      tester,
      smokeApp(
        db,
        const Scaffold(body: SafeArea(child: GoldenDrillView(onGoPlan: _noop))),
      ),
    );

    await tester.runAsync(() async {
      await smokeGolden.bootstrap();
      await smokeGolden.openArticle('a1');
      smokeGolden.drill.open('s1');
    });
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(smokeGolden.drill.phase, GoldenDrillPhase.fill);
    // 原来顶栏会重复显示一整句英文；现在撤掉，只留填空区里的进度小字。
    expect(find.text('We keep up with the news every morning.'), findsNothing);
    expect(find.textContaining('填空 1/'), findsOneWidget);

    await smokeFinish(tester);
  });
}

void _noop() {}
