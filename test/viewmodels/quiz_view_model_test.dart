// 整卷考试：组卷、判分、交卷只记一次、重练错题不重复记、文章题口径。
import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/quiz.dart';
import 'package:dlaoshi_app/core/quiz_pool.dart';
import 'package:dlaoshi_app/data/db/migrations.dart' show ensureSchema;
import 'package:dlaoshi_app/data/prefs_store.dart' show PrefsStore, quizSettingsKey;
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/viewmodels/quiz_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/vocab_fixture.dart';

final _at = DateTime.parse('2026-11-14T10:00:00.000Z');

SavedArticle _article() => SavedArticle(
      id: 'a1',
      title: '考试文章',
      updatedAt: _at.toIso8601String(),
      paragraphs: const [Paragraph(id: 'p1', sentenceIds: ['s1', 's2', 's3', 's4'])],
      sentences: const [
        Sentence(id: 's1', paraId: 'p1', text: 'The cat sat on the mat.', translation: '猫坐在垫子上。'),
        Sentence(id: 's2', paraId: 'p1', text: 'She reads a book every night.', translation: '她每晚读一本书。'),
        Sentence(id: 's3', paraId: 'p1', text: 'We walked home in the rain.', translation: '我们在雨中走回家。'),
        Sentence(id: 's4', paraId: 'p1', text: 'They built a house last year.', translation: '他们去年建了一所房子。'),
      ],
    );

void main() {
  late Database db;
  late VocabRepository vocab;
  late LearningRepository learning;
  late ArticleRepository articles;
  late QuizViewModel vm;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    vocab = VocabRepository(db);
    learning = LearningRepository(db);
    articles = ArticleRepository(db);
    await vocab.save(
      VocabLibrary(
        items: [
          vocabItem(word: 'mitigate', meaning: '减轻', examples: [
            const VocabExample(text: 'The drug can mitigate the pain.', translation: '这种药能减轻疼痛。'),
          ]),
          vocabItem(id: 'v2', word: 'harbor', lemma: 'harbor', meaning: '港口'),
        ],
      ),
    );
    await articles.save(_article());
    vm = QuizViewModel(
      vocab: vocab,
      learning: learning,
      articles: articles,
      now: () => _at,
    );
    await vm.bootstrap();
  });

  tearDown(() async {
    await vm.flushWrites();
    vm.dispose();
    await db.close();
  });

  /// 把当前卷答完；[wrongFirst] 让第一题故意答错。
  Future<void> finishAll({bool wrongFirst = false}) async {
    var first = true;
    while (!vm.finished) {
      final q = vm.question!;
      vm.setInput(first && wrongFirst ? 'zzz-wrong' : q.answer);
      await vm.submit();
      first = false;
      await vm.next();
    }
  }

  test('bootstrap：读词库 / 文章；没当前篇时词级卷退回全库', () async {
    expect(vm.articles.map((a) => a.id), contains('a1'));
    expect(vm.scope, QuizScope.all);
    expect(vm.mode, QuizMode.vocab);
    expect(vm.kinds, defaultQuizVocabKinds.toSet());
    expect(vm.limit, defaultQuizLimit);
    expect(vm.availableKinds, vocabKinds);
  });

  test('词级卷：组卷 → 作答 → 交卷写一条 practice', () async {
    vm.setScope(QuizScope.all);
    vm.setLimit(10);
    final n = await vm.start();
    expect(n, greaterThan(0));

    await finishAll();
    expect(vm.finished, isTrue);
    expect(vm.recorded, isTrue);
    expect(vm.correctCount, vm.results.length);

    final data = await learning.load();
    expect(data.practice, hasLength(1));
    expect(data.practice.single.total, n);
    expect(data.practice.single.correct, n);
    expect(data.practice.single.kind.name, 'quiz');
  });

  test('重练错题：只排错题，且同一轮不再记第二次成绩', () async {
    vm.setScope(QuizScope.all);
    vm.setLimit(10);
    await vm.start();
    await finishAll(wrongFirst: true);

    final afterFirst = (await learning.load()).practice.length;
    expect(afterFirst, 1);
    expect(vm.wrongQuestions, isNotEmpty);

    final retry = vm.retryWrong();
    expect(retry, greaterThan(0));
    expect(vm.total, retry);
    await finishAll();

    expect((await learning.load()).practice, hasLength(1), reason: '重练不记第二轮成绩');
  });

  test('再考一轮：清空后重新组卷，成绩记第二条', () async {
    vm.setScope(QuizScope.all);
    vm.setLimit(10);
    await vm.start();
    await finishAll();

    final n = await vm.restart();
    expect(n, greaterThan(0));
    expect(vm.recorded, isFalse);
    await finishAll();

    expect((await learning.load()).practice, hasLength(2));
  });

  test('文章卷：显式题型出题；答错不进错题本、活动算「读」、按题型累计', () async {
    vm.setMode(QuizMode.article);
    vm.setArticleId('a1');
    expect(vm.availableKinds, articleKinds);
    expect(vm.kinds, defaultQuizArticleKinds.toSet());
    // 只留英译中：其它题型在这篇也可能出，钉死一种好算统计。
    for (final k in vm.kinds.toList()) {
      if (k != QuizKind.translate) vm.toggleKind(k);
    }
    expect(vm.kinds, {QuizKind.translate});

    final n = await vm.start();
    expect(n, greaterThan(0));
    expect(vm.question!.kind.isArticle, isTrue);

    await finishAll(wrongFirst: true);
    expect(vm.recorded, isTrue);

    final data = await learning.load();
    expect(data.practice, hasLength(1));
    expect(data.practice.single.articleId, 'a1');
    expect(data.mistakes, isEmpty, reason: '文章题不写错题本');
    expect(data.answerEvents.every((e) => e.cat == ActivityCat.read), isTrue);
    final stat = data.kindStats['a1']?[QuizKind.translate.name];
    expect(stat, isNotNull);
    expect(stat!.total, n);
    expect(stat.correct, n - 1);
  });

  test('文章卷没选篇：出不了卷，给出提示', () async {
    vm.setMode(QuizMode.article);
    vm.setArticleId(null);
    final n = await vm.start();
    expect(n, 0);
    expect(vm.error, contains('译文'));
  });

  test('切模式：题型与范围跟着换，至少留一个题型', () {
    vm.setMode(QuizMode.article);
    expect(vm.kinds, defaultQuizArticleKinds.toSet());
    expect(vm.scope, QuizScope.article);
    expect(vm.needsArticle, isTrue);

    // 全部取消到只剩一个时，再取消无效。
    for (final k in vm.availableKinds.toList()) {
      vm.toggleKind(k);
    }
    expect(vm.kinds.length, greaterThanOrEqualTo(1));
  });

  group('设置持久化', () {
    test('改过的设置存进 prefs，下次开 App 还是那套', () async {
      final store = PrefsStore.memory();
      final a = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        prefsStore: store,
        now: () => _at,
      );
      a.setMode(QuizMode.article);
      a.setLimit(30);
      a.setAuto(true);
      a.setSpeakAfter(false);
      a.setLoopWrong(true);
      a.setUnique(false);
      a.toggleKind(QuizKind.grammar);
      a.dispose();

      // 等落盘（_save 是 unawaited 的，内存实现是同步的，这里只是稳妥）。
      await Future<void>.delayed(Duration.zero);

      final b = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        prefsStore: store,
        now: () => _at,
      );
      expect(b.mode, QuizMode.article);
      expect(b.limit, 30);
      expect(b.auto, isTrue);
      expect(b.speakAfter, isFalse);
      expect(b.loopWrong, isTrue);
      expect(b.unique, isFalse);
      expect(b.kinds, contains(QuizKind.grammar));
      b.dispose();
    });

    test('没存过就是默认值；坏 JSON 也不炸', () async {
      final fresh = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        prefsStore: PrefsStore.memory(),
        now: () => _at,
      );
      expect(fresh.mode, QuizMode.vocab);
      expect(fresh.limit, defaultQuizLimit);
      expect(fresh.auto, isFalse);
      fresh.dispose();

      final broken = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        prefsStore: PrefsStore.memory({quizSettingsKey: '{不是 json'}),
        now: () => _at,
      );
      expect(broken.mode, QuizMode.vocab);
      expect(broken.limit, defaultQuizLimit);
      broken.dispose();
    });
  });

  group('自动下一题', () {
    test('开着：答完题隔一会儿自己翻到下一题', () async {
      vm.setScope(QuizScope.all);
      vm.setAuto(true);
      await vm.start();
      expect(vm.total, greaterThan(1), reason: '要至少两题才看得出翻页');

      final first = vm.question!;
      await vm.submit(first.answer);
      expect(vm.result, isNotNull);
      expect(vm.index, 0, reason: '刚判完还停在本题');

      // 等自动切题的定时器（答对 650ms）。
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(vm.index, 1);
      expect(vm.result, isNull);
    });

    test('关着：判完一直停在本题', () async {
      vm.setScope(QuizScope.all);
      vm.setAuto(false);
      await vm.start();
      final first = vm.question!;
      await vm.submit(first.answer);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(vm.index, 0);
      expect(vm.result, isNotNull);
    });

    test('拼写错：不自动切（要先确认）', () async {
      vm.setScope(QuizScope.all);
      vm.setAuto(true);
      // 只考拼写，保证第一题一定是拼写题。
      for (final k in vm.kinds.toList()) {
        if (k != QuizKind.spell) vm.toggleKind(k);
      }
      await vm.start();
      expect(vm.question!.kind, QuizKind.spell);

      vm.setInput('zzz-wrong');
      await vm.submit();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(vm.index, 0, reason: '拼错要停在本题让用户确认');
      expect(vm.result!.correct, isFalse);
    });
  });

  group('反复鞭打', () {
    test('开着：交卷后自动重练错题，轮次 +1', () async {
      vm.setScope(QuizScope.all);
      vm.setLoopWrong(true);
      await vm.start();
      await finishAll(wrongFirst: true);
      expect(vm.recorded, isTrue);
      expect(vm.drillRound, 2, reason: '已经进到第二轮');
      expect(vm.loopWrong, isTrue);

      // 鞭打的定时器 1500ms 后重练错题。
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      expect(vm.wrongQuestions, isEmpty, reason: '重练清空了上一轮结果');
      expect(vm.index, 0);
      expect(vm.total, greaterThan(0));
    });

    test('关着：交卷就停在报告页', () async {
      vm.setScope(QuizScope.all);
      vm.setLoopWrong(false);
      await vm.start();
      await finishAll(wrongFirst: true);
      expect(vm.drillRound, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      expect(vm.index, vm.total, reason: '还在报告页');
    });
  });

  group('每个词只考一次', () {
    test('关掉 unique：同一个词可以出多种题型', () async {
      // 一个词 + 两种题型：unique 关掉才出得来两题。
      await vocab.save(
        VocabLibrary(
          items: [
            vocabItem(
              id: 'solo',
              word: 'solo',
              lemma: 'solo',
              meaning: '独自的',
              examples: const [VocabExample(text: 'He went solo.')],
            ),
          ],
        ),
      );
      vm.setScope(QuizScope.all);
      vm.setLimit(10);
      for (final k in vm.kinds.toList()) {
        if (k != QuizKind.spell && k != QuizKind.cloze) vm.toggleKind(k);
      }

      vm.setUnique(true);
      await vm.start();
      final uniqueTotal = vm.total;
      vm.reset();

      vm.setUnique(false);
      await vm.start();
      expect(vm.total, greaterThanOrEqualTo(uniqueTotal));
    });
  });

  group('考试历史', () {
    test('交卷写一条历史：摘要 + 逐题明细，新的在前', () async {
      vm.setScope(QuizScope.all);
      vm.setLimit(10);
      await vm.start();
      await finishAll(wrongFirst: true);

      expect(vm.archive.history, hasLength(1));
      final row = vm.archive.history.single;
      expect(row.total, vm.results.length);
      expect(row.correct, vm.results.where((r) => r.correct).length);
      expect(row.mode, QuizMode.vocab);
      expect(row.entries, hasLength(row.total));
      expect(row.entries.where((e) => !e.correct), hasLength(1));

      // 再考一轮 → 新的排在前面。
      await vm.restart();
      await finishAll();
      expect(vm.archive.history, hasLength(2));
      expect(vm.archive.history.first.correct, vm.archive.history.first.total);
    });

    test('重练错题不写第二条历史（同一轮只记一次）', () async {
      vm.setScope(QuizScope.all);
      await vm.start();
      await finishAll(wrongFirst: true);
      expect(vm.archive.history, hasLength(1));

      vm.retryWrong();
      await finishAll();
      expect(vm.archive.history, hasLength(1), reason: '重练不记第二轮历史');
    });

    test('历史存进 prefs，下次开 App 还在', () async {
      final store = PrefsStore.memory();
      final a = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        prefsStore: store,
        now: () => _at,
      );
      await a.bootstrap();
      a.setScope(QuizScope.all);
      await a.start();
      while (!a.finished) {
        final q = a.question!;
        a.setInput(q.answer);
        await a.submit();
        await a.next();
      }
      expect(a.archive.history, hasLength(1));
      a.dispose();
      await Future<void>.delayed(Duration.zero);

      final b = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        prefsStore: store,
        now: () => _at,
      );
      expect(b.archive.history, hasLength(1));
      expect(b.archive.history.single.total, greaterThan(0));
      b.dispose();
    });

    test('文章卷的历史带篇名', () async {
      vm.setMode(QuizMode.article);
      vm.setArticleId('a1');
      for (final k in vm.kinds.toList()) {
        if (k != QuizKind.translate) vm.toggleKind(k);
      }
      await vm.start();
      await finishAll();
      expect(vm.archive.history.single.articleId, 'a1');
      expect(vm.archive.history.single.articleTitle, '考试文章');
    });
  });

  group('会话恢复', () {
    test('答到一半的卷会存下来，重新开 App 能接着考', () async {
      final store = PrefsStore.memory();
      final a = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        prefsStore: store,
        now: () => _at,
      );
      await a.bootstrap();
      a.setScope(QuizScope.all);
      expect(await a.start(), greaterThan(1));

      // 只答第一题，停在第二题。
      final first = a.question!;
      a.setInput(first.answer);
      await a.submit();
      await a.next();
      final stoppedAt = a.index;
      final total = a.total;
      expect(stoppedAt, 1);
      expect(a.archive.hasSaved, isTrue);
      a.dispose();
      await Future<void>.delayed(Duration.zero);

      final b = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        prefsStore: store,
        now: () => _at,
      );
      await b.bootstrap();
      expect(b.archive.hasSaved, isTrue);
      expect(b.archive.saved!.index, stoppedAt);
      expect(b.archive.saved!.questions, hasLength(total));

      final left = b.resumeSession();
      expect(left, total - stoppedAt);
      expect(b.index, stoppedAt);
      expect(b.results, hasLength(1));
      expect(b.question!.id, isNot(first.id));
      b.dispose();
    });

    test('交卷后快照就清掉，不再提示继续', () async {
      vm.setScope(QuizScope.all);
      await vm.start();
      await finishAll();
      expect(vm.archive.hasSaved, isFalse);
      expect(vm.archive.saved, isNull);
    });

    test('点「不继续了」清掉快照', () async {
      vm.setScope(QuizScope.all);
      await vm.start();
      final q = vm.question!;
      vm.setInput(q.answer);
      await vm.submit();
      await vm.next();
      expect(vm.archive.hasSaved, isTrue);
      vm.discardSaved();
      expect(vm.archive.hasSaved, isFalse);
    });

    test('改设置会丢掉上一场的快照（口径对不上了）', () async {
      vm.setScope(QuizScope.all);
      await vm.start();
      final q = vm.question!;
      vm.setInput(q.answer);
      await vm.submit();
      await vm.next();
      expect(vm.archive.hasSaved, isTrue);
      vm.setLimit(10);
      expect(vm.archive.hasSaved, isFalse);
    });

    test('重开一轮也会清掉快照', () async {
      vm.setScope(QuizScope.all);
      await vm.start();
      final q = vm.question!;
      vm.setInput(q.answer);
      await vm.submit();
      await vm.next();
      expect(vm.archive.hasSaved, isTrue);
      await vm.restart();
      expect(vm.archive.hasSaved, isFalse);
    });

    test('没有可恢复的卷时 resumeSession 返回 0', () {
      expect(vm.archive.hasSaved, isFalse);
      expect(vm.resumeSession(), 0);
    });
  });

  group('听写 / 混合卷', () {
    test('听写：按正文句序挖词库里的词，一句一题', () async {
      vm.setMode(QuizMode.dictation);
      vm.setArticleId('a1');
      final n = await vm.start();
      // 文章里只有 mitigate / harbor 在词库中，但它俩都不在正文里 → 一题都出不来。
      expect(n, 0, reason: '正文里没有词库中的词，听写出不来');
      expect(vm.error, contains('听写'));
    });

    test('听写：正文里有的词能出成听音填空', () async {
      // 把正文里的词收进词库，再跑听写。
      final cat = vocabItem(id: 'v-cat', word: 'cat', lemma: 'cat', meaning: '猫');
      await vocab.save(
        VocabLibrary(items: [...(await vocab.load())!.items, cat]),
      );
      final local = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        now: () => _at,
      );
      await local.bootstrap();
      local.setMode(QuizMode.dictation);
      local.setArticleId('a1');
      final n = await local.start();
      expect(n, greaterThan(0));
      final q = local.question!;
      expect(q.kind, QuizKind.listen);
      expect(q.audioText, isNotNull);
      expect(q.audioText!.toLowerCase(), contains('cat'));
      local.dispose();
    });

    test('听写：没选篇就出不了卷（要先选一篇）', () {
      vm.setMode(QuizMode.dictation);
      expect(vm.needsArticle, isTrue);
    });

    test('混合卷：词级 + 文章级都在一张卷里', () async {
      // 正文里的 cat 收进词库，词级那边才有东西出。
      await vocab.save(
        VocabLibrary(items: [
          ...(await vocab.load())!.items,
          vocabItem(id: 'v-cat', word: 'cat', lemma: 'cat', meaning: '猫'),
        ]),
      );
      final local = QuizViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        now: () => _at,
      );
      await local.bootstrap();
      local.setMode(QuizMode.mixed);
      local.setArticleId('a1');
      local.setLimit(10);
      expect(await local.start(), greaterThan(0));
      while (!local.finished) {
        final q = local.question!;
        local.setInput(q.answer);
        await local.submit();
        await local.next();
      }
      final kinds = <QuizKind>[
        for (final e in local.archive.history.single.entries) e.kind,
      ];
      expect(
        kinds.any((k) => !k.isArticle),
        isTrue,
        reason: '混合卷要有词级题',
      );
      expect(
        kinds.any((k) => k.isArticle),
        isTrue,
        reason: '混合卷要有文章级题',
      );
      local.dispose();
    });

    test('混合卷：题型固定，不能逐项改', () {
      vm.setMode(QuizMode.mixed);
      final before = vm.kinds;
      vm.toggleKind(QuizKind.spell);
      expect(vm.kinds, before, reason: '混合卷题型是固定组合');
    });
  });
}
