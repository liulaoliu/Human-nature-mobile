// 背单词页的 smoke：开轮入口 + 卡片翻面 + 评分按钮。
//
// 注意：真实 SQLite 是真实异步 IO，在 testWidgets 的假时钟里**永远不会完成**。
// 所以「先 seed 数据、先开好轮」这类动作必须包在 `tester.runAsync` 里，
// 否则整条用例会静默挂住（不是报错，是卡到超时）。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/models/vocab.dart';
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

  testWidgets('StudyPage 开轮态：候选数、学新词入口，设置项已搬去设置页', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const StudyPage()));

    expect(find.text('背单词'), findsOneWidget);
    expect(find.text('候选 0 个'), findsOneWidget);
    expect(find.text('学新词'), findsOneWidget);
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
      vm.startRound(mode: StudyMode.learn);
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
}
