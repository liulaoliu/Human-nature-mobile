import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/core/vocab/learn_step.dart';
import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
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

/// 四个单词 + 一份足够的干扰项，让「选释义」能真的出题。
List<VocabItem> _words() => [
      vocabItem(id: 'v1', word: 'alpha', meaning: '阿尔法'),
      vocabItem(id: 'v2', word: 'bravo', meaning: '好极了'),
      vocabItem(id: 'v3', word: 'charlie', meaning: '查理'),
      vocabItem(id: 'v4', word: 'delta', meaning: '三角洲'),
    ];

VocabLibrary _lib(List<VocabItem> items) => VocabLibrary(items: items);

void main() {
  late Database db;
  late VocabRepository vocabRepo;
  late LearningRepository learningRepo;
  late StudyViewModel vm;

  setUp(() async {
    db = await _openMem();
    vocabRepo = VocabRepository(db);
    learningRepo = LearningRepository(db);
    vm = StudyViewModel(vocab: vocabRepo, learning: learningRepo);
    await vocabRepo.save(_lib(_words()));
    await vm.bootstrap();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('设置', () {
    test('bootstrap 读出词库；默认范围是「没掌握」、牌组是单词', () {
      expect(vm.library.items, hasLength(4));
      expect(vm.scope, StudyScope.unmastered);
      expect(vm.deck, StudyDeck.word);
      expect(vm.error, isNull);
    });

    test('开始前 pool 按范围 + 牌组筛；换牌组后搭配池为空', () {
      expect(vm.pool, hasLength(4));
      vm.setDeck(StudyDeck.collocation);
      expect(vm.pool, isEmpty);
    });

    test('组大小生效值：手动设了就用手动的', () {
      expect(vm.effectiveGroupSize, defaultStudyGroupSize);
      vm.setGroupSize(5);
      expect(vm.effectiveGroupSize, 5);
      vm.setGroupSize(-3);
      expect(vm.groupSize, 0);
    });

    test('counts 分清「该复习」与「没学过」', () {
      final counts = vm.poolCounts;
      expect(counts.total, 4);
      expect(counts.fresh, 4);
      expect(counts.due, 0);
    });
  });

  group('开轮', () {
    test('学新词：装 4 张卡，分母是 4', () {
      final n = vm.startRound();
      expect(n, 4);
      expect(vm.started, isTrue);
      expect(vm.session!.roundTotal, 4);
      expect(vm.session!.card!.word, 'alpha');
    });

    test('复习到期的：没有到期的词时开不出轮', () {
      expect(vm.startRound(mode: StudyMode.review), 0);
      expect(vm.started, isFalse);
      expect(vm.session, isNull);
    });

    test('空词库开不出轮', () async {
      await vocabRepo.clear();
      await vm.bootstrap();
      expect(vm.startRound(), 0);
      expect(vm.started, isFalse);
    });

    test('endRound 回到设置页', () {
      vm.startRound();
      vm.endRound();
      expect(vm.started, isFalse);
      expect(vm.lastOutcome, isNull);
    });
  });

  group('评分与落盘', () {
    test('评「认识」：词库写进 SRS、进度推进、给出提示', () async {
      vm.startRound();
      await vm.grade(ReviewGrade.good);

      expect(vm.lastOutcome!.label, '认识');
      expect(vm.session!.index, 1);
      final saved = (await vocabRepo.load())!;
      final alpha = saved.items.firstWhere((it) => it.id == 'v1');
      expect(alpha.reviewState.repetitions, 1);
      expect(alpha.reviewState.interval, 1);
      expect(alpha.reviewState.due, isNotNull);
    });

    test('评「忘记」：lapses 记一笔、词被退回队尾加练', () async {
      vm.startRound();
      await vm.grade(ReviewGrade.again);

      final saved = (await vocabRepo.load())!;
      final alpha = saved.items.firstWhere((it) => it.id == 'v1');
      expect(alpha.reviewState.lapses, 1);
      expect(alpha.reviewState.relearn > 0, isTrue);
      expect(vm.session!.queue.length, 5);
      expect(vm.session!.counts.forgot, 1);
    });

    test('落盘失败不炸会话：saveError 记下来，界面还能继续', () async {
      vm.startRound();
      // 把词库表换成一个不存在的形状，制造写失败
      await db.execute('DROP TABLE vocab_snapshots');
      await vm.grade(ReviewGrade.good);
      expect(vm.saveError, isNotNull);
      expect(vm.session!.index, 1);
    });

    test('猜词面：清掉提示后 lastOutcome 为空', () async {
      vm.startRound();
      await vm.grade(ReviewGrade.good);
      expect(vm.lastOutcome, isNotNull);
      vm.clearLastOutcome();
      expect(vm.lastOutcome, isNull);
    });

    test('没开始的会话里评分是空操作', () async {
      await vm.grade(ReviewGrade.good);
      expect(vm.lastOutcome, isNull);
    });
  });

  group('选中文释义', () {
    test('选对：第一次给「模糊」、第二次起给「认识」，并写 meaningPasses', () async {
      vm.startRound();
      expect(vm.session!.options, hasLength(4));
      final step = await vm.learnStep(LearnAction.correct);
      expect(step!.label, startsWith('模糊'));
      expect(vm.session!.meaningCleared || vm.session!.index == 1, isTrue);
    });

    test('词库不够出题时退回 fallback（不写库）', () async {
      await vocabRepo.save(
        _lib([vocabItem(id: 'v1', word: 'alpha', meaning: '阿尔法')]),
      );
      await vm.bootstrap();
      vm.startRound();
      expect(vm.session!.options, isEmpty);
      final step = await vm.learnStep(LearnAction.correct);
      expect(step!.kind.name, 'fallback');
    });
  });

  group('拼写', () {
    test('卡面拼写对了算「认识」', () async {
      vm.startRound();
      expect(await vm.checkSpelling('alpha'), isTrue);
      expect(vm.session!.index, 1);
    });

    test('卡面拼错：落库为「不认识」+ 打标签 + 回队尾', () async {
      vm.startRound();
      expect(await vm.checkSpelling('alfa'), isFalse);
      final saved = (await vocabRepo.load())!;
      final alpha = saved.items.firstWhere((it) => it.id == 'v1');
      expect(alpha.tags, contains('不认识'));
      expect(alpha.reviewState.relearn > 0, isTrue);
    });

    test('组末拼写：拼错后要照着重打一遍才放行', () async {
      await vocabRepo.clear();
      await vm.bootstrap();
      await vocabRepo.save(_lib(_words().take(2).toList()));
      await vm.bootstrap();
      vm.setGroupSize(2);
      vm.startRound();

      await vm.grade(ReviewGrade.good); // 第 1 个
      await vm.grade(ReviewGrade.good); // 第 2 个 → 组末
      expect(vm.session!.spelling!.active, isTrue);
      expect(vm.session!.spelling!.total, 2);

      vm.forward(); // 拼写测试期间 forward 无效
      expect(vm.session!.spelling!.active, isTrue);

      expect(await vm.checkSpelling('alpha'), isTrue);
      expect(vm.session!.spelling!.index, 1);
      expect(await vm.checkSpelling('bravoo'), isFalse);
      expect(vm.session!.spelling!.miss, isNotNull);
      // 组末拼错**不**回队尾：验收不是加练
      expect(vm.session!.queue.length, 2);
      expect(vm.session!.spelling!.miss!.word, 'bravo');
    });
  });

  group('学习记账', () {
    test('评分会记「今天学过这个词」，flushLedger 落到 studiedDays + activity', () async {
      vm.startRound();
      await vm.grade(ReviewGrade.good);
      expect(vm.studiedToday, 1);

      await vm.flushLedger();
      final data = await learningRepo.load();
      expect(data.studiedDays, hasLength(1));
      expect(data.studiedDays.first.ids, ['v1']);
      final today = data.activity.firstWhere((d) => d.countOf(ActivityCat.vocab) > 0);
      expect(today.countOf(ActivityCat.vocab), 1);
    });

    test('同一个词重复评只记一次', () async {
      vm.startRound();
      await vm.grade(ReviewGrade.good);
      vm.back();
      await vm.grade(ReviewGrade.good);
      expect(vm.studiedToday, 1);
    });

    test('没背过就不写学习记录', () async {
      await vm.flushLedger();
      final data = await learningRepo.load();
      expect(data.studiedDays, isEmpty);
    });
  });

  group('收尾重练', () {
    test('忘记过的词可以重练一次，第二次不再给', () async {
      vm.startRound();
      await vm.grade(ReviewGrade.again);
      expect(vm.session!.canRetryForgot, isTrue);
      expect(vm.retryForgot(), isTrue);
      expect(vm.session!.retrying, isTrue);
      expect(vm.retryForgot(), isFalse);
    });
  });
}
