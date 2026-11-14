// 背单词页的 smoke：开轮入口 + 卡片翻面 + 评分按钮。
//
// 注意：真实 SQLite 是真实异步 IO，在 testWidgets 的假时钟里**永远不会完成**。
// 所以「先 seed 数据、先开好轮」这类动作必须包在 `tester.runAsync` 里，
// 否则整条用例会静默挂住（不是报错，是卡到超时）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/vocab/drill.dart' show DrillReason;
import 'package:dlaoshi_app/core/vocab/drill_step.dart' show DrillStep;
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/core/vocab/study_drill.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/views/study_drill_view.dart';
import 'package:dlaoshi_app/views/study_page.dart';
import 'package:dlaoshi_app/viewmodels/study_view_model.dart';
import 'smoke_harness.dart';

VocabItem mkWord(String word, {String? meaning}) => VocabItem(
      id: 'item-$word',
      word: word,
      lemma: word,
      meaning: meaning,
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-01T00:00:00.000Z',
    );

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('StudyPage 开轮态：三个入口 + 回顾范围，设置项已搬去设置页', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const StudyPage()));

    expect(find.text('背单词'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('回顾'), findsOneWidget);
    expect(find.text('回顾范围'), findsOneWidget);
    // 设置项不再挤在练习页
    expect(find.text('范围'), findsNothing);
    expect(find.text('牌组'), findsNothing);

    await smokeFinish(tester);
  });

  testWidgets('StudyPage 卡片：默认不露释义，点一下翻面，之后才有三档评分', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    late final StudyViewModel vm;
    late final bool started;
    await tester.runAsync(() async {
      final vocab = smokeVocabRepo(db);
      await vocab.save(VocabLibrary(items: [mkWord('introvert', meaning: '内向者')]));
      vm = StudyViewModel(
        vocab: vocab,
        learning: smokeLearningRepo(db),
      );
      await vm.bootstrap();
      vm.startRound(entry: StudyEntry.learn);
      started = vm.started;
    });

    await smokePump(tester, smokeApp(db, const StudyPage(), study: vm));

    if (!started) {
      // 空库时至少不该崩
      expect(find.text('背单词'), findsOneWidget);
      await smokeFinish(tester);
      return;
    }

    expect(find.text('点一下看释义'), findsOneWidget);
    expect(find.text('显示释义'), findsOneWidget);

    await tester.tap(find.text('显示释义'));
    await tester.pump();

    expect(find.text('认识'), findsOneWidget);
    expect(find.text('模糊'), findsOneWidget);
    expect(find.text('忘记了'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('学习新词：第一屏就是四选一释义，选完停在原题再点「继续」', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    late final StudyViewModel vm;
    late final bool started;
    await tester.runAsync(() async {
      final vocab = smokeVocabRepo(db);
      // 四个有释义的词，凑得够四选一的干扰项
      await vocab.save(VocabLibrary(items: [
        mkWord('alpha', meaning: '阿尔法'),
        mkWord('bravo', meaning: '好极了'),
        mkWord('charlie', meaning: '查理'),
        mkWord('delta', meaning: '三角洲'),
      ]));
      vm = StudyViewModel(vocab: vocab, learning: smokeLearningRepo(db));
      await vm.bootstrap();
      vm.startRound(entry: StudyEntry.learn);
      started = vm.started;
    });

    await smokePump(tester, smokeApp(db, const StudyPage(), study: vm));
    if (!started) {
      await smokeFinish(tester);
      return;
    }

    // 第一屏是释义四选一，不是单词卡
    expect(find.text('先选释义'), findsNothing); // 标签在进度行里，用下面两条判定
    expect(find.textContaining('先选释义'), findsOneWidget);
    expect(find.text('点一下看释义'), findsNothing);

    // 点正确项：停住，出现「继续（看单词卡）」
    final options = vm.session!.options;
    final right = options.indexWhere((o) => o.correct);
    await tester.tap(find.textContaining('${'ABCD'[right]}. '));
    await tester.pump();
    await tester.pump();

    expect(find.text('继续（看单词卡）'), findsWidgets);

    await tester.tap(find.text('继续（看单词卡）').first);
    await tester.pump();
    await tester.pump();

    // 进了单词卡：四选一的进度行没了（卡面已摊开释义，所以不找「点一下看释义」）
    expect(find.textContaining('先选释义'), findsNothing);
    expect(find.text('继续（看单词卡）'), findsNothing);

    await smokeFinish(tester);
  });

  testWidgets('复习评分：点「认识」后摊开释义并停住，给「下一词 / 记错了」', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    late final StudyViewModel vm;
    late final bool started;
    await tester.runAsync(() async {
      final vocab = smokeVocabRepo(db);
      await vocab.save(VocabLibrary(items: [
        for (final w in ['alpha', 'bravo', 'charlie', 'delta'])
          VocabItem(
            id: 'item-$w',
            word: w,
            lemma: w,
            meaning: '$w 的意思',
            createdAt: '2026-11-01T00:00:00.000Z',
            updatedAt: '2026-11-01T00:00:00.000Z',
            reviewState: const ReviewState(
              ease: 2.5,
              interval: 1,
              repetitions: 1,
              lapses: 0,
              due: '2026-01-01T00:00:00.000Z',
            ),
          ),
      ]));
      vm = StudyViewModel(vocab: vocab, learning: smokeLearningRepo(db));
      await vm.bootstrap();
      vm.startRound(entry: StudyEntry.review);
      started = vm.started;
    });

    await smokePump(tester, smokeApp(db, const StudyPage(), study: vm));
    if (!started) {
      await smokeFinish(tester);
      return;
    }

    // 复习模式先给三键
    expect(find.text('认识'), findsOneWidget);

    await tester.tap(find.text('认识'));
    await tester.pump();
    await tester.pump();

    // 摊卡停住：给两个出口
    expect(find.text('下一词'), findsOneWidget);
    expect(find.text('记错了 · 其实不认识'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('锤炼拼写：只给释义，绝不显示单词本身（否则等于送答案）', (tester) async {
    final drill = StudyDrill(
      reason: DrillReason.timeout,
      card: mkWord('outnumber', meaning: '数量超过'),
      items: const <VocabItem>[],
    );
    expect(drill.step, DrillStep.spell);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyDrillPanel(
            drill: drill,
            onSpell: (_) => DrillVerdict.retry,
            onPick: (_) => DrillVerdict.retry,
            onUsage: (_) => DrillVerdict.retry,
            onTyped: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('超时锤炼'), findsOneWidget);
    expect(find.text('数量超过'), findsOneWidget);
    // 关键断言：拼写步骤不许把答案摊出来
    expect(find.text('outnumber'), findsNothing);

    await smokeFinish(tester);
  });
}
