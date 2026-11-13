import 'package:dlaoshi_app/core/learning.dart';
import 'package:dlaoshi_app/core/mistakes.dart';
import 'package:dlaoshi_app/core/practice.dart';
import 'package:dlaoshi_app/core/quiz_drill.dart';
import 'package:dlaoshi_app/core/vocab/review.dart' show ReviewGrade, reviewItem;
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/viewmodels/current_article_view_model.dart';
import 'package:dlaoshi_app/viewmodels/drill_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/vocab_fixture.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await ensureSchema(db);
  return db;
}

/// 四个有释义的单词 —— 够选义题凑干扰项（要 3 个）。
List<VocabItem> _words({String? articleId}) => [
      for (final w in const ['alpha', 'beta', 'gamma', 'delta'])
        vocabItem(
          id: 'v-$w',
          word: w,
          meaning: '$w 的意思',
          status: VocabStatus.queried,
          source: articleId == null
              ? null
              : VocabSource(articleId: articleId, fileName: 'growth.txt'),
        ),
    ];

void main() {
  late Database db;
  late ArticleRepository articles;
  late VocabRepository vocabRepo;
  late LearningRepository learningRepo;
  late PrefsStore store;
  late CurrentArticleViewModel current;
  late DrillViewModel vm;

  setUp(() async {
    db = await _openMem();
    articles = ArticleRepository(db);
    vocabRepo = VocabRepository(db);
    learningRepo = LearningRepository(db);
    store = PrefsStore.memory();
    current = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
    vm = DrillViewModel(
      vocab: vocabRepo,
      learning: learningRepo,
      articles: articles,
      currentArticle: current,
      prefsStore: store,
    );
  });

  tearDown(() async {
    vm.dispose();
    current.dispose();
    await db.close();
  });

  Future<void> seed(List<VocabItem> items) async {
    await vocabRepo.save(VocabLibrary(items: items));
  }

  group('初始化', () {
    test('bootstrap 读出词库；默认档位是记忆拷打、10 题', () async {
      await seed(_words());
      await vm.bootstrap();
      expect(vm.kind, QuizDrillKind.memory);
      expect(vm.limit, defaultDrillLimit);
      expect(vm.error, isNull);
      expect(vm.poolSize, greaterThan(0));
    });

    test('换档位读各自存下的题量', () async {
      await seed(_words());
      await vm.bootstrap();
      vm.setKind(QuizDrillKind.chunk);
      await vm.setLimit(5);
      expect(vm.limit, 5);
      expect(vm.limits[QuizDrillKind.chunk], 5);
      // 记忆拷打那档还是默认值。
      expect(vm.limits[QuizDrillKind.memory], defaultDrillLimit);
      vm.setKind(QuizDrillKind.memory);
      expect(vm.limit, defaultDrillLimit);
    });

    test('题量落盘：换一个 ViewModel 能读回', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.setLimit(20);
      final again = DrillViewModel(
        vocab: vocabRepo,
        learning: learningRepo,
        articles: articles,
        currentArticle: current,
        prefsStore: store,
      );
      await again.bootstrap();
      expect(again.limit, 20);
      again.dispose();
    });

    test('非档位值回落到默认 10', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.setLimit(7);
      expect(vm.limit, defaultDrillLimit);
    });
  });

  group('出卷', () {
    test('记忆拷打：按题量出题，题都来自词库', () async {
      await seed(_words());
      await vm.bootstrap();
      final n = await vm.start(limit: 3);
      expect(n, 3);
      expect(vm.total, 3);
      expect(vm.hasQueue, isTrue);
      expect(vm.question, isNotNull);
      expect(vm.error, isNull);
    });

    test('词库为空：0 题并给出原因', () async {
      await vm.bootstrap();
      final n = await vm.start();
      expect(n, 0);
      expect(vm.hasQueue, isFalse);
      expect(vm.error, contains('没有能出的题'));
    });

    test('没有释义的词出不了题', () async {
      await seed([
        for (final w in const ['alpha', 'beta', 'gamma', 'delta'])
          vocabItem(id: 'v-$w', word: w),
      ]);
      await vm.bootstrap();
      expect(await vm.start(), 0);
      expect(vm.error, contains('缺释义'));
    });

    test('本篇范围：只考这一篇收进来的词', () async {
      await seed([
        ..._words(articleId: 'a1'),
        // 另一篇（没挂文章）的四个词不该出现在本篇考题里。
        for (final w in const ['zeta', 'eta', 'theta', 'iota'])
          vocabItem(
            id: 'other-$w',
            word: w,
            meaning: '$w 的意思',
            status: VocabStatus.queried,
          ),
      ]);
      await current.select('a1');
      await vm.bootstrap();
      final n = await vm.start();
      expect(n, greaterThan(0));
      expect(vm.question!.word.startsWith('other-'), isFalse);
      expect(vm.question!.word, anyOf('alpha', 'beta', 'gamma', 'delta'));
    });

    test('没绑文章：退回全库，首页点进来就能考', () async {
      await seed(_words());
      await vm.bootstrap();
      expect(await vm.start(), greaterThan(0));
      expect(vm.error, isNull);
    });

    test('错题包围战：只考错题本里点过名的词', () async {
      await seed(_words());
      final data = emptyLearning();
      data.mistakes = upsertMistake(
        data.mistakes,
        vocabMistake('v-beta', 'beta · 拼写', '2026-11-01T00:00:00.000Z'),
      );
      await learningRepo.writeSection(data, LearningSection.mistakes);
      await vm.bootstrap();
      final n = await vm.start(kind: QuizDrillKind.siege);
      expect(n, 1);
      expect(vm.question!.itemId, 'v-beta');
    });

    test('错题本为空：包围战给专门提示', () async {
      await seed(_words());
      await vm.bootstrap();
      expect(await vm.start(kind: QuizDrillKind.siege), 0);
      expect(vm.error, contains('错题本'));
    });
  });

  group('答题', () {
    test('答对：立刻出结果，正确数 +1', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start();
      final q = vm.question!;
      await vm.submit(q.answer);
      expect(vm.result, isNotNull);
      expect(vm.result!.correct, isTrue);
      expect(vm.correctCount, 1);
      expect(vm.error, isNull);
    });

    test('答错：给标准答案、记进错题本', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start();
      final q = vm.question!;
      await vm.submit('zzzz-not-a-word');
      expect(vm.result!.correct, isFalse);
      expect(vm.result!.answer, q.answer);

      await vm.flushWrites();
      final data = await learningRepo.load();
      final hit = data.mistakes.where((m) => m.kind == MistakeKind.vocab && m.itemId == q.itemId);
      expect(hit, hasLength(1));
    });

    test('空输入不算作答', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start();
      await vm.submit('   ');
      expect(vm.result, isNull);
      expect(vm.error, contains('先写点什么'));
      expect(vm.correctCount, 0);
    });

    test('同一题重复交卷被忽略', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start();
      await vm.submit(vm.question!.answer);
      final before = vm.results.length;
      await vm.submit(vm.question!.answer);
      expect(vm.results.length, before);
    });

    test('答题事件带题号、题型与来源', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start();
      final q = vm.question!;
      await vm.submit(q.answer);
      final data = await learningRepo.load();
      expect(data.answerEvents, hasLength(1));
      final e = data.answerEvents.first;
      expect(e.source, PracticeKind.quiz);
      expect(e.kind, q.kind.name);
      expect(e.questionId, q.id);
      expect(e.correct, isTrue);
    });

    test('答对写 SRS good，答错写 again', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start();
      final q = vm.question!;
      await vm.submit(q.answer);
      await vm.flushWrites();
      final lib = await vocabRepo.load();
      final item = lib!.items.firstWhere((it) => it.id == q.itemId);
      expect(item.reviewState.repetitions, greaterThan(0));
      expect(item.reviewState.lapses, 0);
    });
  });

  group('翻页与结算', () {
    test('next 推进题号；最后一题后算结束', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start(limit: 2);
      await vm.submit(vm.question!.answer);
      vm.next();
      expect(vm.index, 1);
      expect(vm.result, isNull);
      expect(vm.finished, isFalse);
      await vm.submit(vm.question!.answer);
      vm.next();
      expect(vm.index, 2);
      expect(vm.finished, isTrue);
      expect(vm.hasNext, isFalse);
    });

    test('没交卷不能翻页', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start(limit: 2);
      vm.next();
      expect(vm.index, 0);
    });

    test('错题重做：把错的题再排一遍', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start(limit: 2);
      await vm.submit('zzzz-wrong');
      vm.next();
      await vm.submit('zzzz-wrong');
      vm.next();
      expect(vm.wrongQuestions, hasLength(2));
      expect(vm.retryWrong(), 2);
      expect(vm.index, 0);
      expect(vm.results, isEmpty);
      expect(vm.finished, isFalse);
    });

    test('全对时错题重做返回 0', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start(limit: 1);
      await vm.submit(vm.question!.answer);
      expect(vm.retryWrong(), 0);
    });

    test('reset 清空这一轮', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start(limit: 2);
      await vm.submit('zzzz');
      vm.reset();
      expect(vm.hasQueue, isFalse);
      expect(vm.results, isEmpty);
      expect(vm.result, isNull);
      expect(vm.error, isNull);
    });

    test('再开一轮会清掉上一轮的结果', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start(limit: 2);
      await vm.submit('zzzz');
      await vm.start(limit: 1);
      expect(vm.results, isEmpty);
      expect(vm.index, 0);
      expect(vm.total, 1);
    });
  });

  group('错题/词库联动', () {
    test('错题本里同一条不会重复累加', () async {
      await seed(_words());
      await vm.bootstrap();
      await vm.start(limit: 1);
      final q = vm.question!;
      await vm.submit('zzzz');
      await vm.start(limit: 3);
      // 换一轮再错同一个词。
      for (var i = 0; i < 3; i++) {
        final cur = vm.question;
        if (cur == null) break;
        await vm.submit('zzzz');
        vm.next();
      }
      final data = await learningRepo.load();
      final hit = data.mistakes.where((m) => m.itemId == q.itemId);
      expect(hit.length, 1);
      expect(hit.first.count, greaterThan(1));
    });

    test('答错让 SRS 记一次 lapse', () async {
      // 先用一次 good 打底，让这一批词有复习历史。
      var lib = VocabLibrary(items: _words());
      for (final it in _words()) {
        lib = reviewItem(lib, it.id, ReviewGrade.good);
      }
      await vocabRepo.save(lib);
      await vm.bootstrap();
      await vm.start();
      final q = vm.question!;
      await vm.submit('zzzz');
      await vm.flushWrites();
      final after = await vocabRepo.load();
      final item = after!.items.firstWhere((it) => it.id == q.itemId);
      expect(item.reviewState.lapses, greaterThan(0));
    });
  });
}
