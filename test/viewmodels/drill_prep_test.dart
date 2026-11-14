// 判分落盘口径：文章题不写 SRS / 错题本，活动分类按题型走。
import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/quiz.dart';
import 'package:dlaoshi_app/data/db/migrations.dart' show ensureSchema;
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/viewmodels/drill_prep.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/vocab_fixture.dart';

final _at = DateTime.parse('2026-11-14T10:00:00.000Z');

QuizQuestion _q({
  required String id,
  required String itemId,
  required QuizKind kind,
  String? source,
  String word = 'alpha',
}) =>
    QuizQuestion(
      id: id,
      itemId: itemId,
      lemma: '',
      kind: kind,
      source: source,
      word: word,
      prompt: 'prompt',
      answer: 'answer',
      accept: const <String>[],
    );

void main() {
  late Database db;
  late VocabRepository vocab;
  late LearningRepository learning;
  late List<String> errors;
  late DrillPrep prep;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    vocab = VocabRepository(db);
    learning = LearningRepository(db);
    errors = <String>[];
    // 故意让词条 id 和「文章题 itemId」相同 —— 旧代码会因此把它当词条写 SRS / 错题本。
    await vocab.save(
      VocabLibrary(
        items: [vocabItem(id: 's1', word: 'alpha', meaning: '甲')],
      ),
    );
    prep = DrillPrep(
      vocab: vocab,
      learning: learning,
      articles: null,
      articleIdOf: () => 'global-article',
      onError: errors.add,
    );
    await prep.bootstrap();
  });

  tearDown(() async {
    await prep.flushWrites();
    await db.close();
  });

  test('文章题答错：不进错题本、不推 SRS、活动算「读」、articleId 用考试篇',
      () async {
    final before = prep.library.items.single.reviewState;

    await prep.record(
      _q(
        id: 'article:translate:s1',
        itemId: 's1',
        kind: QuizKind.translate,
        source: 'article',
      ),
      false,
      _at,
      articleId: 'exam-article',
    );

    expect(errors, isEmpty);
    expect(
      prep.library.items.single.reviewState,
      before,
      reason: '文章题不能推进复习排期',
    );
    final data = await learning.load();
    expect(data.mistakes, isEmpty, reason: '句子 id 不能写成错题');
    expect(data.answerEvents, hasLength(1));
    final event = data.answerEvents.single;
    expect(event.cat, ActivityCat.read);
    expect(event.articleId, 'exam-article');
    expect(event.questionId, 'article:translate:s1');
  });

  test('source 缺失但 kind 是文章级，同样按文章题处理', () async {
    await prep.record(
      _q(id: 'article:ordering:p1', itemId: 's1', kind: QuizKind.ordering),
      false,
      _at,
    );
    final data = await learning.load();
    expect(data.mistakes, isEmpty);
    expect(data.answerEvents.single.cat, ActivityCat.read);
  });

  test('词级题答错：进错题本、活动算「词」、articleId 回全局当前篇', () async {
    await prep.record(
      _q(id: 's1:spell', itemId: 's1', kind: QuizKind.spell),
      false,
      _at,
    );
    final data = await learning.load();
    expect(data.mistakes, hasLength(1));
    expect(data.mistakes.single.itemId, 's1');
    expect(data.answerEvents.single.cat, ActivityCat.vocab);
    expect(data.answerEvents.single.articleId, 'global-article');
  });

  test('听音题答错：活动算「听」，仍进错题本', () async {
    await prep.record(
      _q(id: 's1:listen', itemId: 's1', kind: QuizKind.listen),
      false,
      _at,
    );
    final data = await learning.load();
    expect(data.mistakes, hasLength(1));
    expect(data.answerEvents.single.cat, ActivityCat.listen);
  });
}
