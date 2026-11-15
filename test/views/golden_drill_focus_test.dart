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

  // 用户（2026-11-15）报的：「填多个空，在空之间切换的时候键盘会自动下滑又升起」。
  // 根因是 `TextField` 默认「点到外面就失焦」——点另一个空正好是「点到当前空
  // 的外面」，手指按下时旧空先失焦、textInput 排队隐藏，抬起后新空才要焦点。
  // 现在 `onTapOutside` 置空，旧空不失焦，新空直接接管连接。
  testWidgets('多空之间切换：键盘不掉，点哪个空光标就去哪个空', (tester) async {
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
      // 第 0 轮只挖一个词（`with`）；第 1 轮是 `up with`，两个空。
      smokeGolden.drill.nextRound();
    });
    await tester.pump();
    await tester.pump();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2), reason: '第 1 轮应该有两个空');

    // 进页面就聚焦第一个空，键盘已经起来了。
    expect(tester.testTextInput.isVisible, isTrue);
    final firstNode = tester.widget<TextField>(fields.at(0)).focusNode!;
    final secondNode = tester.widget<TextField>(fields.at(1)).focusNode!;
    expect(firstNode.hasFocus, isTrue);
    expect(secondNode.hasFocus, isFalse);

    // 点第二个空：焦点换过去，键盘连接不掉（这就是「键盘别下滑又升起」）。
    await tester.tap(find.byKey(const ValueKey<String>('golden-blank-1')));
    await tester.pump();
    expect(secondNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    // 再点回第一个空，同样不掉。
    await tester.tap(find.byKey(const ValueKey<String>('golden-blank-0')));
    await tester.pump();
    expect(firstNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await smokeFinish(tester);
  });

  // 用户（2026-11-15）要求：「键盘上点击回车，相当于点击『提交这一轮』」。
  testWidgets('键盘回车 = 交这一轮', (tester) async {
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

    final drill = smokeGolden.drill;
    expect(drill.roundScored, isFalse);

    await tester.enterText(find.byKey(const ValueKey<String>('golden-blank-0')), 'with');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(drill.roundScored, isTrue, reason: '回车应该等于点「交这一轮」');

    await smokeFinish(tester);
  });
}

void _noop() {}
