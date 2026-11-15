// 金句练习子视图的 smoke：未选题给「去挑句」空态；进填空轮次后顶部黑框撤掉。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/viewmodels/golden_drill_session.dart';
import 'package:dlaoshi_app/views/golden_drill_view.dart';
import 'smoke_harness.dart';

SavedArticle _article({
  String text = 'We keep up with the news every morning.',
  String translation = '我们每天早上都跟上新闻。',
  String target = 'keep up with',
  String targetZh = '跟上',
}) {
  final sentence = Sentence(
    id: 's1',
    paraId: 'p01',
    text: text,
    translation: translation,
  );
  return SavedArticle(
    id: 'a1',
    title: '测试篇',
    paragraphs: <Paragraph>[
      const Paragraph(id: 'p01', sentenceIds: <String>['s1']),
    ],
    sentences: <Sentence>[sentence],
    golden: GoldenLesson(
      source: GoldenSource.ai,
      sentences: <GoldenSentence>[
        GoldenSentence(
          id: 's1',
          zh: translation,
          targets: <GoldenTarget>[
            GoldenTarget(
              en: target,
              kind: GoldenTargetKind.collocation,
              zh: targetZh,
            ),
          ],
        ),
      ],
      selected: const <String>['s1'],
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

  testWidgets('填空按文章流排版：多个空排在同一行，不是一个空占一行', (tester) async {
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
      // 第 1 轮挖 `up with`：两个词两个空，应该并排出现在句子里。
      smokeGolden.drill.nextRound();
    });
    await tester.pump();
    await tester.pump();

    final first = find.byKey(const ValueKey<String>('golden-blank-0'));
    final second = find.byKey(const ValueKey<String>('golden-blank-1'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);

    // 空是 `Text.rich` 里的 WidgetSpan：跟正文一起换行，而不是一列盒子。
    expect(
      find.ancestor(of: first, matching: find.byType(RichText)),
      findsWidgets,
    );

    final a = tester.getRect(first);
    final b = tester.getRect(second);
    expect((a.top - b.top).abs(), lessThan(2), reason: '两个空应在同一行');
    expect(b.left, greaterThan(a.right), reason: '第二个空在第一个空右边');

    await smokeFinish(tester);
  });

  testWidgets('同一学习点出现两次：两个空位各自能聚焦，答案同步', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await tester.runAsync(() => ArticleRepository(db).save(_article(
          text: 'Day by day, day by day.',
          translation: '一天天，一天天。',
          target: 'day by day',
          targetZh: '一天天',
        )));
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
      while (smokeGolden.drill.roundIndex + 1 < smokeGolden.drill.roundCount) {
        smokeGolden.drill.nextRound();
      }
    });
    await tester.pump();
    await tester.pump();

    // 最后一轮整句挖空：day by day 出现两次 = 6 个词 = 6 个空（一词一空）。
    expect(find.byType(TextField), findsNWidgets(6));

    final first = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('golden-blank-0')),
    );
    final repeated = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('golden-blank-3')),
    );
    expect(first.controller, isNot(same(repeated.controller)));

    first.controller!.text = 'Day';
    await tester.pump();
    expect(repeated.controller!.text, isEmpty, reason: '每个空各管各的答案');

    // 两处空位各有焦点：一个 FocusNode 不能同时挂两个输入框。
    first.focusNode!.requestFocus();
    await tester.pump();
    expect(first.focusNode!.hasFocus, isTrue);
    expect(repeated.focusNode!.hasFocus, isFalse);
    repeated.focusNode!.requestFocus();
    await tester.pump();
    expect(repeated.focusNode!.hasFocus, isTrue);

    await smokeFinish(tester);
  });
}

void _noop() {}
