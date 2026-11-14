// 整卷考试：组卷、判分、交卷只记一次、重练错题不重复记、文章题口径。
import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/quiz.dart';
import 'package:dlaoshi_app/core/quiz_pool.dart';
import 'package:dlaoshi_app/data/db/migrations.dart' show ensureSchema;
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
}
