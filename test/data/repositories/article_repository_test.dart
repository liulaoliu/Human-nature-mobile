import 'dart:typed_data';

import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

Sentence _sentence({
  String id = 's1',
  String paraId = 'p1',
  String text = 'Global growth is slowing.',
  List<String> vocab = const [],
  List<String> tags = const [],
  String? translation,
  List<SentenceLanguage>? languages,
  ReviewState reviewState = defaultReviewState,
}) =>
    Sentence(
      id: id,
      paraId: paraId,
      text: text,
      vocab: vocab,
      tags: tags,
      translation: translation,
      languages: languages,
      reviewState: reviewState,
    );

SavedArticle _article({
  String id = 'saved:1',
  String title = 'The Economist',
  String? book,
  String? sourceKey,
  ArticleOrigin? origin,
  String? createdAt,
  String updatedAt = '2026-11-01T00:00:00.000Z',
  List<Sentence>? sentences,
  List<Paragraph>? paragraphs,
}) =>
    SavedArticle(
      id: id,
      title: title,
      text: 'Global growth is slowing.',
      book: book,
      sourceKey: sourceKey,
      origin: origin,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sentences: sentences ?? <Sentence>[_sentence()],
      paragraphs: paragraphs ??
          const [Paragraph(id: 'p1', sentenceIds: <String>['s1'])],
    );

Future<int> _count(Database db, String table, [String? where, List<Object?>? args]) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}',
    args,
  );
  return (rows.first['n'] as int?) ?? 0;
}

void main() {
  late Database db;
  late ArticleRepository repo;

  setUp(() async {
    db = await _openMem();
    repo = ArticleRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ArticleRepository 读写', () {
    test('空库里读不到', () async {
      expect(await repo.load('nope'), isNull);
      expect(await repo.meta('nope'), isNull);
      expect(await repo.list(), isEmpty);
      expect(await repo.count(), 0);
      expect(await repo.loadAll(), isEmpty);
    });

    test('save 之后能按 id 读回整篇', () async {
      await repo.save(_article());
      final loaded = await repo.load('saved:1');
      expect(loaded, isNotNull);
      expect(loaded!.title, 'The Economist');
      expect(loaded.sentences.single.text, 'Global growth is slowing.');
      expect(loaded.paragraphs.single.sentenceIds, ['s1']);
      expect(await repo.count(), 1);
    });

    test('payload 是 gzip BLOB', () async {
      await repo.save(_article());
      final rows = await db.rawQuery('SELECT payload FROM articles');
      expect(rows.first['payload'], isA<Uint8List>());
    });

    test('列表只读列，不读 payload', () async {
      await repo.save(_article(id: 'a', title: '甲', book: 'B1', sourceKey: 'k1'));
      await repo.save(_article(id: 'b', title: '乙', updatedAt: '2026-11-02T00:00:00.000Z'));
      final rows = await repo.list();
      expect(rows.map((r) => r.id), ['b', 'a']); // updated_at DESC
      expect(rows.last.book, 'B1');
      expect(rows.last.sourceKey, 'k1');
      expect(rows.first.sentenceCount, 1);
    });

    test('meta 只给元信息', () async {
      await repo.save(_article());
      final meta = await repo.meta('saved:1');
      expect(meta!.title, 'The Economist');
      expect(meta.sentenceCount, 1);
      expect(meta.updatedAt, '2026-11-01T00:00:00.000Z');
    });

    test('findBySourceKey 能找到，也能找不到', () async {
      await repo.save(_article(id: 'a', sourceKey: 'eco-1'));
      expect((await repo.findBySourceKey('eco-1'))!.id, 'a');
      expect(await repo.findBySourceKey('eco-2'), isNull);
    });

    test('loadAll 按更新时间升序（导出顺序稳定）', () async {
      await repo.save(_article(id: 'b', updatedAt: '2026-11-02T00:00:00.000Z'));
      await repo.save(_article(id: 'a', updatedAt: '2026-11-01T00:00:00.000Z'));
      expect((await repo.loadAll()).map((a) => a.id), ['a', 'b']);
    });
  });

  group('ArticleRepository 列与回退', () {
    test('id 为空直接抛，不写脏行', () async {
      expect(
        () => repo.save(_article(id: '   ')),
        throwsA(isA<ArgumentError>()),
      );
      expect(await repo.count(), 0);
    });

    test('createdAt 第一次落盘就定下来，之后再存不会被刷新', () async {
      await repo.save(_article(createdAt: '2026-01-01T00:00:00.000Z'));
      expect((await repo.meta('saved:1'))!.createdAt,
          '2026-01-01T00:00:00.000Z');

      // 第二次保存没带 createdAt（编辑场景），列上还是原来的。
      await repo.save(_article(updatedAt: '2026-11-02T00:00:00.000Z'));
      expect((await repo.meta('saved:1'))!.createdAt,
          '2026-01-01T00:00:00.000Z');
      // 读出来的篇对象也带上这个值。
      expect((await repo.load('saved:1'))!.createdAt,
          '2026-01-01T00:00:00.000Z');
    });

    test('第一次就没有 createdAt 时退回 updatedAt', () async {
      await repo.save(_article(updatedAt: '2026-11-01T00:00:00.000Z'));
      expect((await repo.meta('saved:1'))!.createdAt,
          '2026-11-01T00:00:00.000Z');
    });

    test('sentence_count 与 word_count 按内容算', () async {
      await repo.save(_article(
        sentences: [
          _sentence(vocab: const ['global', 'growth']),
          _sentence(id: 's2', vocab: const ['growth', 'policymakers']),
          _sentence(id: 's3', vocab: const ['global']),
        ],
        paragraphs: const [
          Paragraph(id: 'p1', sentenceIds: <String>['s1', 's2', 's3']),
        ],
      ));
      final meta = await repo.meta('saved:1');
      expect(meta!.sentenceCount, 3);
      expect(meta.wordCount, 3); // 去重后 global / growth / policymakers
    });

    test('再保存一次计数不会累加', () async {
      for (var i = 0; i < 3; i++) {
        await repo.save(_article());
      }
      final meta = await repo.meta('saved:1');
      expect(meta!.sentenceCount, 1);
      expect(await repo.count(), 1);
    });
  });

  group('ArticleRepository 派生表', () {
    test('保存时摊出段落 / 句子 / 词组 / 语言点', () async {
      await repo.save(_article(
        sentences: [
          _sentence(
            vocab: const ['global', 'growth'],
            tags: const ['economy'],
            translation: '全球增长正在放缓。',
          ),
          _sentence(
            id: 's2',
            text: 'Policymakers are worried.',
            languages: const [
              SentenceLanguage(
                structure: '主系表',
                grammar: '现在进行时',
                idioms: <String>['be worried about'],
                source: LanguageSource.manual,
              ),
            ],
          ),
        ],
        paragraphs: const [
          Paragraph(id: 'p1', sentenceIds: <String>['s1', 's2']),
        ],
      ));

      expect(await _count(db, 'article_paragraphs'), 1);
      expect(await _count(db, 'article_paragraph_sentences'), 2);
      expect(await _count(db, 'article_sentences'), 2);
      expect(await _count(db, 'article_sentence_vocab'), 2);
      expect(await _count(db, 'article_sentence_tags'), 1);
      expect(await _count(db, 'lang_points'), 1);
      expect(await _count(db, 'lang_point_terms'), 1);

      final terms = await db.rawQuery(
        'SELECT kind, text FROM lang_point_terms',
      );
      expect(terms.single['kind'], 'idiom');
      expect(terms.single['text'], 'be worried about');
    });

    test('重写同一篇不重复累加派生行', () async {
      for (var i = 0; i < 3; i++) {
        await repo.save(_article());
      }
      expect(await _count(db, 'article_paragraphs'), 1);
      expect(await _count(db, 'article_sentences'), 1);
    });

    test('内容少了派生行也跟着少', () async {
      await repo.save(_article(
        sentences: [
          _sentence(vocab: const ['global']),
          _sentence(id: 's2', vocab: const ['growth']),
        ],
        paragraphs: const [
          Paragraph(id: 'p1', sentenceIds: <String>['s1', 's2']),
        ],
      ));
      expect(await _count(db, 'article_sentence_vocab'), 2);

      await repo.save(_article(sentences: [_sentence(vocab: const ['global'])]));
      expect(await _count(db, 'article_sentence_vocab'), 1);
      expect(await _count(db, 'article_sentences'), 1);
    });

    test('remove 删干净：主表与派生表都不留', () async {
      await repo.save(_article());
      await repo.remove('saved:1');

      expect(await repo.load('saved:1'), isNull);
      expect(await repo.count(), 0);
      expect(await _count(db, 'article_sentences'), 0);
      expect(await _count(db, 'article_paragraphs'), 0);
      expect(await _count(db, 'article_paragraph_sentences'), 0);
    });

    test('删一篇不影响另一篇', () async {
      await repo.save(_article(id: 'a'));
      await repo.save(_article(id: 'b'));
      await repo.remove('a');
      expect(await repo.count(), 1);
      expect((await repo.load('b'))!.id, 'b');
      expect(await _count(db, 'article_sentences'), 1);
    });

    test('remove 不存在的 id 不抛', () async {
      await repo.remove('nope');
      expect(await repo.count(), 0);
    });
  });

  group('ArticleRepository 抗坏数据', () {
    test('库里的 payload 坏了返回 null，不抛', () async {
      await db.rawInsert(
        'INSERT INTO articles (id, payload, title, updated_at) VALUES (?, ?, ?, ?)',
        ['bad', 'not json', '坏', '2026-11-01T00:00:00.000Z'],
      );
      expect(await repo.load('bad'), isNull);
      expect(await repo.loadAll(), isEmpty);
      // 列表照旧能列出（列表不读 payload）。
      expect((await repo.list()).single.id, 'bad');
    });

    test('payload 是形状不对的 JSON 也返回 null', () async {
      await db.rawInsert(
        'INSERT INTO articles (id, payload, title, updated_at) VALUES (?, ?, ?, ?)',
        ['bad', '{"id":"bad"}', '坏', '2026-11-01T00:00:00.000Z'],
      );
      expect(await repo.load('bad'), isNull);
    });

    test('老库里的明文 payload 也能读（迁移前写下的）', () async {
      const json = '{"id":"old","title":"老文章","text":"","paragraphs":[],'
          '"sentences":[],"updatedAt":"2026-01-01T00:00:00.000Z"}';
      await db.rawInsert(
        'INSERT INTO articles (id, payload, title, updated_at) VALUES (?, ?, ?, ?)',
        ['old', json, '老文章', '2026-01-01T00:00:00.000Z'],
      );
      final loaded = await repo.load('old');
      expect(loaded!.title, '老文章');
      expect(loaded.sentences, isEmpty);
    });
  });
}
