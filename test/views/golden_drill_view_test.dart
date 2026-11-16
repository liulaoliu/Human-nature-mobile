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
  List<GoldenTarget>? targets,
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
          targets: targets ??
              <GoldenTarget>[
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

  testWidgets('拼句阶段：原文挖空显示，词块点过就置灰、不能反复选', (tester) async {
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
      while (smokeGolden.drill.roundIndex + 1 < smokeGolden.drill.roundCount) {
        smokeGolden.drill.nextRound();
      }
      smokeGolden.drill.nextRound();
    });
    await tester.pump();
    await tester.pump();

    final drill = smokeGolden.drill;
    expect(drill.phase, GoldenDrillPhase.assemble);

    // 1. 原文不整句露面，学习点换成 [1] 空位。
    expect(find.text('We keep up with the news every morning.'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('golden-assemble-slot-0')),
      findsOneWidget,
    );
    expect(find.text('[1]'), findsOneWidget);

    // 2. 词块点一次就用掉：按钮置灰，再点不进去。
    final chip = find.widgetWithText(ActionChip, 'keep up with');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pump();
    expect(drill.order, <String>['keep up with']);
    expect(tester.widget<ActionChip>(chip).onPressed, isNull);

    await tester.tap(chip, warnIfMissed: false);
    await tester.pump();
    expect(drill.order, <String>['keep up with'], reason: '一个词块只有一份');

    // 3. 点已拼的词块 ×：撤回。
    await tester.tap(
      find.byKey(const ValueKey<String>('golden-assemble-undo')),
    );
    await tester.pump();
    expect(drill.order, isEmpty);
    expect(tester.widget<ActionChip>(chip).onPressed, isNotNull);

    await smokeFinish(tester);
  });

  testWidgets('填空：填对自动跳下一个空，填错不跳、可手动点', (tester) async {
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
      // 这一轮挖 `up with`：两个相邻的空，正好看「填对自动跳」。
      smokeGolden.drill.nextRound();
    });
    await tester.pump();
    await tester.pump();

    final first = find.byKey(const ValueKey<String>('golden-blank-0'));
    final second = find.byKey(const ValueKey<String>('golden-blank-1'));
    TextField field(Finder f) => tester.widget<TextField>(f);

    // 填对第一个：焦点自动到第二个。
    await tester.enterText(first, 'up');
    await tester.pump();
    expect(field(second).focusNode!.hasFocus, isTrue);
    expect(field(first).focusNode!.hasFocus, isFalse);

    // 填错第一个：不跳，焦点留在自己身上。
    await tester.enterText(first, 'zz');
    await tester.pump();
    expect(field(first).focusNode!.hasFocus, isTrue);
    expect(field(second).focusNode!.hasFocus, isFalse);

    // 手动点第二个空：照样能输入。
    await tester.tap(second);
    await tester.pump();
    expect(field(second).focusNode!.hasFocus, isTrue);

    await smokeFinish(tester);
  });

  testWidgets('拼句选错：只说不对，不把正确顺序报出来', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await tester.runAsync(() => ArticleRepository(db).save(_article(
          targets: const <GoldenTarget>[
            GoldenTarget(
              en: 'keep up with',
              kind: GoldenTargetKind.collocation,
              zh: '跟上',
            ),
            GoldenTarget(
              en: 'every morning',
              kind: GoldenTargetKind.word,
              zh: '每天早上',
            ),
          ],
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
      smokeGolden.drill.nextRound();
      // 倒着点两个词块 → 顺序必然错。
      smokeGolden.drill.pick('every morning');
      smokeGolden.drill.pick('keep up with');
    });
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('交拼句'));
    await tester.pump();
    await tester.pump();

    expect(smokeGolden.drill.assembleScored, isTrue);
    expect(smokeGolden.drill.assembleOk, isFalse);
    expect(find.text('顺序不对，再试一次。'), findsOneWidget);
    expect(
      find.textContaining('→'),
      findsNothing,
      reason: '报出正确顺序等于把答案送了',
    );
    expect(find.textContaining('every morning → keep up with'), findsNothing);

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
