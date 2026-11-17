// StudyCardFlow 的口径测试：学习四选一 + 复习三档出口矩阵。
//
// 这一层是「这一张卡」的临时态，所以测试都围绕「点一下之后停在哪、写没写库」展开。
// 真实 SQLite 的异步写盘在假时钟里不会完成，涉及落盘的断言统一用
// `tester.runAsync` 或纯 Dart `test`（这里全是纯 Dart，没有 widget）。
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/core/vocab/review_step.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/viewmodels/study_card_flow.dart';
import 'package:dlaoshi_app/viewmodels/study_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/vocab_fixture.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

/// 四个有中文释义的词 —— 够 `meaningOptions` 出四选一。
List<VocabItem> _words() => [
      vocabItem(id: 'v1', word: 'alpha', meaning: '阿尔法'),
      vocabItem(id: 'v2', word: 'bravo', meaning: '好极了'),
      vocabItem(id: 'v3', word: 'charlie', meaning: '查理'),
      vocabItem(id: 'v4', word: 'delta', meaning: '三角洲'),
    ];

/// 词库里某条的最新复习状态（判分后从这里读，不依赖落盘）。
ReviewState _stateOf(StudyViewModel vm, String id) =>
    vm.session!.library.items.firstWhere((it) => it.id == id).reviewState;

/// 卡上「记错了」按钮该不该出现（与 view 同一个 core 判定）。
bool _canMistake(StudyCardFlow flow) {
  final pending = flow.reviewPending;
  return pending != null && reviewExitAllowsMistake(pending);
}

void main() {
  late Database db;
  late VocabRepository vocabRepo;
  late LearningRepository learningRepo;
  late StudyViewModel vm;
  late StudyCardFlow flow;

  setUp(() async {
    db = await _openMem();
    vocabRepo = VocabRepository(db);
    learningRepo = LearningRepository(db);
    vm = StudyViewModel(vocab: vocabRepo, learning: learningRepo);
    await vocabRepo.save(VocabLibrary(items: _words()));
    await vm.bootstrap();
    flow = StudyCardFlow(vm);
  });

  tearDown(() async {
    flow.dispose();
    vm.dispose();
    await db.close();
  });

  group('学习四选一：生词先选释义', () {
    test('开轮第一屏就是四选一（learnPhase 为真）', () {
      vm.startRound(entry: StudyEntry.learn);
      expect(flow.learnPhase, isTrue);
      expect(flow.learnGraded, isFalse);
      expect(flow.learnPick, isNull);
      expect(vm.session!.options, hasLength(4));
    });

    test('选对：绿色高亮正确项、停在原题、不换词', () async {
      vm.startRound(entry: StudyEntry.learn);
      final options = vm.session!.options;
      final right = options.indexWhere((o) => o.correct);
      final before = vm.session!.index;

      await flow.pickMeaning(right, true);

      expect(flow.learnGraded, isTrue);
      expect(flow.learnPick, right);
      expect(flow.learnWrong, isFalse);
      expect(flow.learnPhase, isFalse); // 判过就不再是「待选」态
      expect(vm.session!.index, before); // 关键：没有推进
    });

    test('选错：红色高亮错项、停在原题、不换词', () async {
      vm.startRound(entry: StudyEntry.learn);
      final options = vm.session!.options;
      final wrong = options.indexWhere((o) => !o.correct);
      final before = vm.session!.index;

      await flow.pickMeaning(wrong, false);

      expect(flow.learnGraded, isTrue);
      expect(flow.learnPick, wrong);
      expect(flow.learnWrong, isTrue);
      expect(vm.session!.index, before);
    });

    test('「不认识，看答案」：高亮正确项并停住', () async {
      vm.startRound(entry: StudyEntry.learn);
      final before = vm.session!.index;

      await flow.revealAnswer();

      expect(flow.learnGraded, isTrue);
      expect(flow.learnPick, isNull); // 没选任何一项
      expect(vm.session!.index, before);
    });

    test('点「继续」之后才进单词卡（learnContinued）', () async {
      vm.startRound(entry: StudyEntry.learn);
      await flow.pickMeaning(0, true);
      expect(flow.learnContinued, isFalse);

      await flow.continueAfterLearn();

      expect(flow.learnContinued, isTrue);
      expect(flow.revealed, isTrue);
    });

    test('选对已落库：点「继续」不再写一次（不双写 SRS）', () async {
      vm.startRound(entry: StudyEntry.learn);
      final options = vm.session!.options;
      final right = options.indexWhere((o) => o.correct);
      final id = vm.session!.card!.id;

      await flow.pickMeaning(right, true);
      final afterPick = _stateOf(vm, id);
      expect(afterPick.repetitions, 1, reason: '第一次选对判 hard');
      expect(afterPick.interval, 1);
      expect(flow.learnCommitted, isTrue);

      await flow.continueAfterLearn();

      final afterContinue = _stateOf(vm, id);
      expect(afterContinue.repetitions, afterPick.repetitions,
          reason: '进卡只是看一遍，不许再评一次');
      expect(afterContinue.interval, afterPick.interval);
      expect(flow.learnCommitted, isTrue);
    });

    test('看答案：停留期不写库，点「继续」才判 again', () async {
      vm.startRound(entry: StudyEntry.learn);
      final id = vm.session!.card!.id;

      await flow.revealAnswer();
      expect(_stateOf(vm, id).relearn, 0, reason: '停留高亮期间不改词库');
      expect(flow.learnCommitted, isFalse);

      await flow.continueAfterLearn();

      expect(_stateOf(vm, id).relearn, 1);
      expect(flow.learnCommitted, isTrue);
    });

    test('选错：点「继续」才判 again（停留期不写库）', () async {
      vm.startRound(entry: StudyEntry.learn);
      final options = vm.session!.options;
      final wrong = options.indexWhere((o) => !o.correct);
      final id = vm.session!.card!.id;

      await flow.pickMeaning(wrong, false);
      expect(_stateOf(vm, id).relearn, 0);
      expect(flow.learnCommitted, isFalse);

      await flow.continueAfterLearn();

      expect(_stateOf(vm, id).relearn, 1);
    });

    test('换下一张卡时四选一状态清空', () async {
      vm.startRound(entry: StudyEntry.learn);
      await flow.pickMeaning(0, true);
      expect(flow.learnGraded, isTrue);

      vm.forward();

      expect(flow.learnGraded, isFalse);
      expect(flow.learnPick, isNull);
      expect(flow.learnContinued, isFalse);
      expect(flow.learnPhase, isTrue); // 下一个生词重新四选一
    });
  });

  group('复习三档：评分后一律摊卡停住', () {
    /// 造出「有复习历史且到期」的库，让 `startRound(review)` 真的有卡。
    Future<void> startReview() async {
      final graded = [
        for (final w in _words())
          vocabItem(
            id: w.id,
            word: w.word,
            meaning: w.meaning,
            reviewState: ReviewState(
              ease: 2.5,
              interval: 1,
              repetitions: 1,
              lapses: 0,
              due: '2026-01-01T00:00:00.000Z',
            ),
          ),
      ];
      await vocabRepo.save(VocabLibrary(items: graded));
      await vm.bootstrap();
      vm.startRound(entry: StudyEntry.review);
    }

    test('认识：摊卡、不写库、不推进，给「下一词 / 记错了」', () async {
      await startReview();
      final before = vm.session!.index;

      await flow.chooseGrade(ReviewGrade.good);

      expect(flow.revealed, isTrue);
      expect(flow.reviewFuzzy, isTrue);
      expect(flow.reviewPending, ReviewGrade.good);
      expect(vm.session!.index, before); // 关键：没有推进
      expect(
        reviewExitAllowsMistake(flow.reviewPending!),
        isTrue,
      );
    });

    test('点一下看释义 = 点模糊：摊卡、待定 hard、不推进', () async {
      await startReview();
      final before = vm.session!.index;

      flow.reveal();

      expect(flow.revealed, isTrue);
      expect(flow.reviewFuzzy, isTrue);
      expect(flow.reviewPending, ReviewGrade.hard);
      expect(_canMistake(flow), isTrue);
      expect(vm.session!.index, before);
    });

    test('拼错过的卡：四选一判完放行释义门禁，不卡在释义页', () async {
      // 带「不认识」标签但已退出重学的词，出场要先过「选中文释义」门禁。
      await vocabRepo.save(VocabLibrary(items: [
        for (final w in _words())
          vocabItem(
            id: w.id,
            word: w.word,
            meaning: w.meaning,
            tags: w.id == 'v1' ? const [spellingMissTag] : const [],
            reviewState: ReviewState(
              ease: 2.5,
              interval: 1,
              repetitions: 0,
              lapses: 0,
              due: w.id == 'v1'
                  ? '2025-12-01T00:00:00.000Z'
                  : '2026-01-01T00:00:00.000Z',
            ),
          ),
      ]));
      await vm.bootstrap();
      vm.startRound(entry: StudyEntry.review);

      expect(vm.session!.card!.id, 'v1');
      expect(vm.session!.view.meaningGate, isTrue);

      final right = vm.session!.options.indexWhere((o) => o.correct);
      await flow.pickMeaning(right, true);

      expect(vm.session!.view.meaningGate, isFalse, reason: '判完必须放行');
      expect(flow.learnCommitted, isTrue);

      await flow.continueAfterLearn();
      expect(vm.session!.view.meaningGate, isFalse);
    });

    test('摊卡后点「记错了」：改判 again、继续停在卡上', () async {
      await startReview();
      final before = vm.session!.index;
      await flow.chooseGrade(ReviewGrade.good);
      expect(_canMistake(flow), isTrue);

      await flow.chooseReviewExit(ReviewExitChoice.missed);

      expect(vm.session!.index, before);
      expect(flow.reviewPending, isNull);
      expect(flow.reviewGraded, isTrue); // 只剩「下一词」
      expect(_canMistake(flow), isFalse);
    });

    test('「忘记了」不提供「记错了」出口', () async {
      await startReview();
      await flow.chooseGrade(ReviewGrade.again);

      expect(_canMistake(flow), isFalse);
    });

    test('模糊：摊卡停住', () async {
      await startReview();
      await flow.chooseGrade(ReviewGrade.hard);
      expect(flow.revealed, isTrue);
      expect(flow.reviewPending, ReviewGrade.hard);
      expect(reviewExitAllowsMistake(flow.reviewPending!), isTrue);
    });

    test('忘记了：摊卡停住，且只给「下一词」', () async {
      await startReview();
      await flow.chooseGrade(ReviewGrade.again);
      expect(flow.revealed, isTrue);
      expect(flow.reviewPending, ReviewGrade.again);
      expect(reviewExitAllowsMistake(flow.reviewPending!), isFalse);
    });

    test('认识 → 下一词：落 good 并推进', () async {
      await startReview();
      final before = vm.session!.index;
      await flow.chooseGrade(ReviewGrade.good);

      await flow.chooseReviewExit(ReviewExitChoice.next);

      expect(vm.session!.index, before + 1);
      expect(flow.reviewPending, isNull);
      expect(flow.reviewFuzzy, isFalse);
    });

    test('认识 → 记错了：只落 again，继续停在卡上', () async {
      await startReview();
      final before = vm.session!.index;
      await flow.chooseGrade(ReviewGrade.good);

      await flow.chooseReviewExit(ReviewExitChoice.missed);

      expect(vm.session!.index, before); // 仍停在这张
      expect(flow.reviewGraded, isTrue); // 只剩「下一词」
      expect(flow.reviewPending, isNull);
    });

    test('记错了之后再点「下一词」才换词', () async {
      await startReview();
      final before = vm.session!.index;
      await flow.chooseGrade(ReviewGrade.good);
      await flow.chooseReviewExit(ReviewExitChoice.missed);

      await flow.chooseReviewExit(ReviewExitChoice.next);

      expect(vm.session!.index, before + 1);
    });

    test('换卡后摊卡态全部清空', () async {
      await startReview();
      await flow.chooseGrade(ReviewGrade.good);
      expect(flow.reviewFuzzy, isTrue);

      await flow.chooseReviewExit(ReviewExitChoice.next);

      expect(flow.reviewFuzzy, isFalse);
      expect(flow.reviewGraded, isFalse);
      expect(flow.reviewPending, isNull);
      expect(flow.revealed, isFalse);
    });
  });
}
