// 选词加词落库：单词不标类型、词组标 phrase、词组也要进本篇。
import 'package:dlaoshi_app/core/article_vocab.dart' show articleEntryViews;
import 'package:dlaoshi_app/core/word_pick.dart' show PickEntry;
import 'package:dlaoshi_app/data/db/migrations.dart' show ensureSchema;
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart' show VocabItemKind;
import 'package:dlaoshi_app/services/vocab_mark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PickEntry _word(String word, {String sentenceId = 's1', int count = 1}) =>
    PickEntry(sentenceId: sentenceId, word: word, count: count);

PickEntry _phrase(String phrase, {String sentenceId = 's1', int count = 2}) =>
    PickEntry(
      sentenceId: sentenceId,
      word: phrase,
      count: count,
      kind: VocabItemKind.phrase,
    );

void main() {
  late Database db;
  late VocabRepository repo;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    repo = VocabRepository(db);
  });

  tearDown(() async => db.close());

  test('加一个词：新建词条，不标类型，并收进本篇', () async {
    final added = await addWordsToArticle(
      repo: repo,
      articleId: 'a1',
      entries: [_word('Run')],
    );
    expect(added, 1);

    final library = await repo.load();
    final item = library!.items.single;
    expect(item.word, 'Run');
    expect(item.lemma, 'run');
    expect(item.kind, isNull);
    expect(
      library.articleEntries.any((e) => e.articleId == 'a1' && e.lemma == 'run'),
      isTrue,
    );
  });

  test('加一个词组：标 phrase，也进本篇，但不占正文编号', () async {
    final added = await addWordsToArticle(
      repo: repo,
      articleId: 'a1',
      entries: [_phrase('keep up with', count: 3)],
    );
    expect(added, 1);

    final library = await repo.load();
    final item = library!.items.single;
    expect(item.word, 'keep up with');
    expect(item.kind, VocabItemKind.phrase);
    expect(item.status.name, 'queried');
    expect(
      library.articleEntries
          .any((e) => e.articleId == 'a1' && e.lemma == 'keep up with'),
      isTrue,
    );
    // 正文编号只算普通单词：词组不该出现。
    expect(articleEntryViews(library, 'a1'), isEmpty);
    // 语言点视图（includeLang）能看到它。
    expect(
      articleEntryViews(library, 'a1', includeLang: true).single.entry.lemma,
      'keep up with',
    );
  });

  test('重复点同一个词不会建第二条，返回 0', () async {
    await addWordsToArticle(repo: repo, articleId: 'a1', entries: [_word('run')]);
    final again = await addWordsToArticle(
      repo: repo,
      articleId: 'a1',
      entries: [_word('run')],
    );
    expect(again, 0);
    final library = await repo.load();
    expect(library!.items, hasLength(1));
  });

  test('同一次传了重复词，只算一条', () async {
    final added = await addWordsToArticle(
      repo: repo,
      articleId: 'a1',
      entries: [_word('run'), _word('run')],
    );
    expect(added, 1);
  });

  test('空列表直接返回 0，不写库', () async {
    expect(
      await addWordsToArticle(repo: repo, articleId: 'a1', entries: const []),
      0,
    );
    expect(await repo.load(), isNull);
  });

  test('一条单词 + 一条词组：两条都进库，返回新建 2 条', () async {
    final added = await addWordsToArticle(
      repo: repo,
      articleId: 'a1',
      entries: [_word('run'), _phrase('keep up')],
    );
    expect(added, 2);
    final library = await repo.load();
    expect(library!.items, hasLength(2));
    expect(library.articleEntries, hasLength(2));
  });

  test('词组的 sentenceId 会记进按篇条目', () async {
    await addWordsToArticle(
      repo: repo,
      articleId: 'a1',
      entries: [_phrase('keep up', sentenceId: 's9')],
    );
    final library = await repo.load();
    final entry =
        library!.articleEntries.firstWhere((e) => e.lemma == 'keep up');
    expect(entry.sentenceId, 's9');
  });
}
