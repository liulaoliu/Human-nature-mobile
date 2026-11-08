import 'dart:convert';
import 'dart:typed_data';

import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/db/projections.dart';
import 'package:dlaoshi_app/data/db/schema.dart';
import 'package:dlaoshi_app/data/db/sql_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 起一个内存库；`version` 用来伪造老库（先建表再写 user_version）。
Future<Database> _openMem() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
}

Future<void> _setVersion(Database db, int v) =>
    db.execute('PRAGMA user_version = $v');

Future<int> _version(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.first['user_version'] as int?) ?? 0;
}

Future<Set<String>> _tables(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((r) => r['name'] as String).toSet();
}

Map<String, Object?> _articleJson({
  String id = 'saved:1',
  String title = 'The Economist',
  String? sourceKey,
  String? createdAt,
  String updatedAt = '2026-11-01T00:00:00.000Z',
  List<Map<String, Object?>>? sentences,
}) =>
    <String, Object?>{
      'id': id,
      'title': title,
      'sourceKey': sourceKey,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'paragraphs': <Object?>[
        <String, Object?>{
          'id': 'p1',
          'sentenceIds': <Object?>['s1', 's2'],
        },
      ],
      'sentences': sentences ??
          <Object?>[
            <String, Object?>{
              'id': 's1',
              'paraId': 'p1',
              'text': 'Global growth is slowing.',
              'vocab': <Object?>['global', 'growth'],
              'collocations': <Object?>['global growth'],
              'tags': <Object?>['economy'],
              'reviewState': <String, Object?>{'ease': 2.7, 'interval': 3, 'due': '2026-11-05'},
            },
            <String, Object?>{
              'id': 's2',
              'paraId': 'p1',
              'text': 'Policymakers are worried.',
              'vocab': <Object?>['policymakers'],
              'languages': <Object?>[
                <String, Object?>{
                  'source': 'manual',
                  'structure': '主系表',
                  'grammar': '现在进行时',
                  'idioms': <Object?>['be worried about'],
                  'phrases': <Object?>['worry about'],
                  'usage': <Object?>['worry sb'],
                },
              ],
            },
          ],
    };

Map<String, Object?> _libraryJson(List<Map<String, Object?>> items) =>
    <String, Object?>{'schemaVersion': 1, 'items': items};

void main() {
  group('schema 常量', () {
    test('当前版本是 13，退役版本的 DDL 是空串', () {
      expect(schemaVersion, 13);
      expect(schemaV5, '');
      expect(schemaV6, '');
      expect(schemaV10, '');
    });
  });

  group('ensureSchema', () {
    test('空库从 0 一路迁到 13，核心表齐全', () async {
      final db = await _openMem();
      addTearDown(db.close);

      expect(await _version(db), 0);
      expect(await ensureSchema(db), 13);
      expect(await _version(db), 13);

      final tables = await _tables(db);
      for (final t in <String>[
        'vocab',
        'vocab_snapshots',
        'articles',
        'words',
        'word_examples',
        'word_contexts',
        'article_sentences',
        'article_paragraphs',
        'lang_points',
        'practice_records',
        'mistake_records',
        'reading_progress',
        'writing_records',
        'retell_records',
        'activity_days',
        'study_days',
        'answer_events',
        'learning_derived_baseline',
        'back_translation_records',
        'golden_drill_records',
        'writing_error_progress',
        'learning_snapshots',
        'production_progress',
      ]) {
        expect(tables.contains(t), isTrue, reason: '缺表 $t');
      }
    });

    test('重复调用幂等，版本不回退', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await ensureSchema(db);
      expect(await ensureSchema(db), 13);
      expect(await _version(db), 13);
    });

    test('版本比程序高时抛错，不凑合打开', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await _setVersion(db, 99);
      await expectLater(ensureSchema(db), throwsA(isA<StateError>()));
    });

    test('v1 老库迁移后 articles 补列并回填查询列', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await db.execute(schemaV1);
      await _setVersion(db, 1);
      // 老库没有 book / source_key / created_at / sentence_count / word_count。
      await db.insert('articles', <String, Object?>{
        'id': 'saved:1',
        'payload': jsonEncode(_articleJson(sourceKey: 'economist')),
        'title': '',
        'updated_at': '2026-11-01T00:00:00.000Z',
      });

      await ensureSchema(db);

      final cols = <String>{
        for (final r in await db.rawQuery('PRAGMA table_info(articles)')) asText(r['name']) ?? '',
      };
      for (final c in <String>[
        'book',
        'source_key',
        'created_at',
        'sentence_count',
        'word_count',
      ]) {
        expect(cols.contains(c), isTrue, reason: '缺列 $c');
      }

      final row = (await db.rawQuery('SELECT * FROM articles WHERE id = ?', <Object?>['saved:1'])).first;
      expect(row['title'], 'The Economist');
      expect(row['source_key'], 'economist');
      // 老文章没有 createdAt，回填要退到 updatedAt。
      expect(row['created_at'], '2026-11-01T00:00:00.000Z');
      expect(row['sentence_count'], 2);
      // vocab 里 global / growth / policymakers 去重后 3 个。
      expect(row['word_count'], 3);
    });

    test('v1 老库迁移后词库派生出 words 与挂靠表', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await db.execute(schemaV1);
      await _setVersion(db, 1);
      await db.insert('vocab', <String, Object?>{
        'id': 1,
        'item_count': 1,
        'updated_at': '2026-11-01T00:00:00.000Z',
        'payload': jsonEncode(_libraryJson(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'w1',
            'word': 'growth',
            'lemma': 'growth',
            'kind': 'word',
            'status': 'known',
            'note': '增长',
            'reviewState': <String, Object?>{'ease': 2.6, 'interval': 4, 'repetitions': 2},
            'usage': <Object?>['名词'],
            'phrases': <Object?>['economic growth'],
            'examples': <Object?>[
              <String, Object?>{'text': 'Growth is slowing.', 'articleId': 'saved:1'},
              'not-a-record',
            ],
            'contexts': <Object?>[
              <String, Object?>{
                'articleId': 'saved:1',
                'sentenceText': 'Global growth is slowing.',
                'at': '2026-11-01T00:00:00.000Z',
              },
            ],
            'confusables': <Object?>[
              <String, Object?>{'word': 'grow', 'meaning': '动词'},
            ],
          },
        ])),
      });

      await ensureSchema(db);

      final words = await db.rawQuery('SELECT * FROM words');
      expect(words.length, 1);
      expect(words.first['word'], 'growth');
      expect(words.first['status'], 'known');
      expect((words.first['review_ease'] as num).toDouble(), 2.6);

      expect((await db.rawQuery('SELECT * FROM word_usage')).length, 1);
      expect((await db.rawQuery('SELECT * FROM word_phrases')).length, 1);
      // 数组里的非对象条目（含 null）不进派生表。
      expect((await db.rawQuery('SELECT * FROM word_examples')).length, 1);
      expect((await db.rawQuery('SELECT * FROM word_contexts')).length, 1);
      expect((await db.rawQuery('SELECT * FROM word_confusables')).length, 1);
    });

    test('v1 老库迁移后文章派生出句子 / 段落 / 语言点 / 词表', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await db.execute(schemaV1);
      await _setVersion(db, 1);
      await db.insert('articles', <String, Object?>{
        'id': 'saved:1',
        'payload': jsonEncode(_articleJson()),
        'title': '',
        'updated_at': '2026-11-01T00:00:00.000Z',
      });

      await ensureSchema(db);

      final sentences = await db.rawQuery('SELECT * FROM article_sentences ORDER BY ordinal');
      expect(sentences.length, 2);
      expect(sentences.first['text'], 'Global growth is slowing.');
      expect((sentences.first['review_ease'] as num).toDouble(), 2.7);
      expect(sentences.first['review_due'], '2026-11-05');

      expect((await db.rawQuery('SELECT * FROM article_paragraphs')).length, 1);
      expect((await db.rawQuery('SELECT * FROM article_paragraph_sentences')).length, 2);
      // 句子 1 有 1 个搭配 + 2 个词，句子 2 有 1 个词。
      expect((await db.rawQuery('SELECT * FROM article_collocations')).length, 1);
      expect((await db.rawQuery('SELECT * FROM article_sentence_vocab')).length, 3);
      expect((await db.rawQuery('SELECT * FROM article_sentence_tags')).length, 1);

      final langs = await db.rawQuery('SELECT * FROM lang_points');
      expect(langs.length, 1);
      expect(langs.first['id'], 'saved:1:s2:lang:0');
      expect(langs.first['source'], 'manual');
      final terms = await db.rawQuery('SELECT * FROM lang_point_terms ORDER BY kind, ordinal');
      expect(terms.length, 3);
      expect(terms.map((t) => t['kind']).toSet(), <String>{'idiom', 'phrase', 'usage'});
    });

    test('v4：早期 source.articleId 存标题时换成真文章 id', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await db.execute(schemaV1);
      await _setVersion(db, 1);
      await db.insert('articles', <String, Object?>{
        'id': 'saved:1',
        'payload': jsonEncode(_articleJson(title: 'Global Growth')),
        'title': 'Global Growth',
        'updated_at': '2026-11-01T00:00:00.000Z',
      });
      await db.insert('vocab', <String, Object?>{
        'id': 1,
        'item_count': 1,
        'updated_at': '2026-11-01T00:00:00.000Z',
        'payload': jsonEncode(_libraryJson(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'w1',
            'word': 'growth',
            'lemma': 'growth',
            // 老数据：这里是文章标题，不是 saved: 开头的 id。
            'source': <String, Object?>{'articleId': 'Global Growth'},
            'examples': <Object?>[
              <String, Object?>{'text': 'x', 'articleId': 'Global Growth'},
            ],
            'contexts': <Object?>[
              <String, Object?>{'articleId': 'Global Growth', 'sentenceText': 'y', 'at': 'now'},
            ],
          },
        ])),
      });

      await ensureSchema(db);

      final rows = await db.rawQuery('SELECT payload FROM vocab WHERE id = 1');
      final lib = jsonDecode(rows.first['payload'] as String) as Map<String, Object?>;
      final item = (lib['items'] as List).first as Map<String, Object?>;
      expect((item['source'] as Map)['articleId'], 'saved:1');
      expect(((item['examples'] as List).first as Map)['articleId'], 'saved:1');
      expect(((item['contexts'] as List).first as Map)['articleId'], 'saved:1');
    });

    test('v4：同名文章不猜，保持原样', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await db.execute(schemaV1);
      await _setVersion(db, 1);
      for (final id in <String>['saved:1', 'saved:2']) {
        await db.insert('articles', <String, Object?>{
          'id': id,
          'payload': jsonEncode(_articleJson(id: id, title: 'Same Title')),
          'title': 'Same Title',
          'updated_at': '2026-11-01T00:00:00.000Z',
        });
      }
      await db.insert('vocab', <String, Object?>{
        'id': 1,
        'item_count': 1,
        'updated_at': '2026-11-01T00:00:00.000Z',
        'payload': jsonEncode(_libraryJson(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'w1',
            'word': 'growth',
            'lemma': 'growth',
            'source': <String, Object?>{'articleId': 'Same Title'},
          },
        ])),
      });

      await ensureSchema(db);

      final rows = await db.rawQuery('SELECT payload FROM vocab WHERE id = 1');
      final lib = jsonDecode(rows.first['payload'] as String) as Map<String, Object?>;
      final item = (lib['items'] as List).first as Map<String, Object?>;
      expect((item['source'] as Map)['articleId'], 'Same Title');
    });

    test('v7：历史聚合存成 baseline', () async {
      final db = await _openMem();
      addTearDown(db.close);

      // 造一个 v6 的老库：v1+v2+v3 的表都已存在，且有历史聚合。
      await db.execute(schemaV1);
      await db.execute(schemaV2);
      await db.execute(schemaV3);
      await _setVersion(db, 6);
      await db.insert('activity_days', <String, Object?>{'day': '2026-10-01', 'cat': 'read', 'count': 3});
      await db.insert('activity_days', <String, Object?>{'day': '2026-10-01', 'cat': 'study', 'count': 5});
      await db.insert('kind_stats', <String, Object?>{
        'article_id': 'saved:1',
        'kind': 'spell',
        'total': 10,
        'correct': 7,
      });

      await ensureSchema(db);

      final rows = await db.rawQuery('SELECT payload, at FROM learning_derived_baseline WHERE id = 1');
      expect(rows.length, 1);
      final payload = jsonDecode(rows.first['payload'] as String) as Map<String, Object?>;
      final activity = payload['activity']! as List;
      expect(activity.length, 1);
      expect(((activity.first as Map)['counts'] as Map)['read'], 3);
      expect(((activity.first as Map)['counts'] as Map)['study'], 5);
      final kindStats = payload['kindStats']! as Map;
      expect((((kindStats['saved:1'] as Map)['spell'] as Map)['total']), 10);
      expect((((kindStats['saved:1'] as Map)['spell'] as Map)['correct']), 7);
      expect(rows.first['at'], isNotNull);
    });

    test('v12：老 learning_snapshots（无 bytes 列）改名归档，新表可写', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await db.execute(schemaV1);
      await db.execute(schemaV2);
      await db.execute(schemaV3);
      // v5 时代的老表结构。
      await db.execute(
        'CREATE TABLE learning_snapshots ('
        'id TEXT PRIMARY KEY, at TEXT NOT NULL, reason TEXT, payload TEXT NOT NULL, record_count INTEGER)',
      );
      await db.insert('learning_snapshots', <String, Object?>{
        'id': 'snap1',
        'at': '2026-10-01T00:00:00.000Z',
        'reason': 'manual',
        'payload': '{}',
        'record_count': 0,
      });
      await _setVersion(db, 11);

      await ensureSchema(db);

      final tables = await _tables(db);
      expect(tables.contains('learning_snapshots'), isTrue);
      expect(tables.contains('learning_snapshots_v5'), isTrue);
      // 老数据留在归档表里，不丢。
      expect((await db.rawQuery('SELECT * FROM learning_snapshots_v5')).length, 1);
      final cols = <String>{
        for (final r in await db.rawQuery('PRAGMA table_info(learning_snapshots)')) asText(r['name']) ?? '',
      };
      expect(cols.contains('bytes'), isTrue);
      expect(cols.contains('payload'), isTrue);
      // 新表能按新结构写入。
      await db.insert('learning_snapshots', <String, Object?>{
        'at': '2026-11-08T00:00:00.000Z',
        'reason': 'manual',
        'payload': Uint8List.fromList(<int>[1, 2, 3]),
        'bytes': 3,
      });
      expect((await db.rawQuery('SELECT * FROM learning_snapshots')).length, 1);
    });
  });

  group('投影重建', () {
    test('增量重建：内容没变的词条不动，改了的重写、删掉的清掉', () async {
      final db = await _openMem();
      addTearDown(db.close);
      await ensureSchema(db);

      final lib1 = _libraryJson(<Map<String, Object?>>[
        <String, Object?>{'id': 'w1', 'word': 'alpha', 'lemma': 'alpha'},
        <String, Object?>{'id': 'w2', 'word': 'beta', 'lemma': 'beta'},
      ]);
      await rebuildVocabProjection(db, lib1);
      final first = await db.rawQuery('SELECT rowid, id FROM words ORDER BY id');
      expect(first.length, 2);
      final w1RowId = first.firstWhere((r) => r['id'] == 'w1')['rowid'];

      final lib2 = _libraryJson(<Map<String, Object?>>[
        <String, Object?>{'id': 'w1', 'word': 'alpha', 'lemma': 'alpha'},
        <String, Object?>{'id': 'w2', 'word': 'beta', 'lemma': 'beta', 'note': '改了'},
        <String, Object?>{'id': 'w3', 'word': 'gamma', 'lemma': 'gamma'},
      ]);
      await rebuildVocabProjection(db, lib2, prevLib: lib1);

      final after = await db.rawQuery('SELECT rowid, id, note FROM words ORDER BY id');
      expect(after.map((r) => r['id']), <Object?>['w1', 'w2', 'w3']);
      // 没变的 w1 保留原 rowid（不是全量 delete + insert）。
      expect(after.first['rowid'], w1RowId);
      expect(after[1]['note'], '改了');

      // 删除的词条连派生行一起清掉。
      final lib3 = _libraryJson(<Map<String, Object?>>[
        <String, Object?>{'id': 'w1', 'word': 'alpha', 'lemma': 'alpha'},
      ]);
      await rebuildVocabProjection(db, lib3, prevLib: lib2);
      expect((await db.rawQuery('SELECT id FROM words ORDER BY id')).map((r) => r['id']), <Object?>['w1']);
    });

    test('全量重建会清空旧派生行', () async {
      final db = await _openMem();
      addTearDown(db.close);
      await ensureSchema(db);

      await rebuildVocabProjection(db, _libraryJson(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'w1',
          'word': 'alpha',
          'lemma': 'alpha',
          'phrases': <Object?>['alpha one'],
        },
      ]));
      expect((await db.rawQuery('SELECT * FROM word_phrases')).length, 1);

      await rebuildVocabProjection(db, _libraryJson(<Map<String, Object?>>[
        <String, Object?>{'id': 'w9', 'word': 'omega', 'lemma': 'omega'},
      ]));
      expect((await db.rawQuery('SELECT * FROM word_phrases')).length, 0);
      expect((await db.rawQuery('SELECT id FROM words')).map((r) => r['id']), <Object?>['w9']);
    });

    test('空词库不建任何派生行，也不抛错', () async {
      final db = await _openMem();
      addTearDown(db.close);
      await ensureSchema(db);

      await rebuildVocabProjection(db, null);
      expect((await db.rawQuery('SELECT * FROM words')).length, 0);
    });

    test('文章重写会先删旧投影（同一篇不会重复累加）', () async {
      final db = await _openMem();
      addTearDown(db.close);
      await ensureSchema(db);

      await rebuildArticleProjection(db, _articleJson());
      await rebuildArticleProjection(db, _articleJson());
      expect((await db.rawQuery('SELECT * FROM article_sentences')).length, 2);
      expect((await db.rawQuery('SELECT * FROM article_sentence_vocab')).length, 3);
    });

    test('payload 坏 JSON 时 parsePayload 返回 null 而不是抛错', () {
      expect(parsePayload('{oops'), isNull);
      expect(parsePayload(null), isNull);
      expect(parsePayload('{"a":1}'), <String, Object?>{'a': 1});
      expect(parsePayload(<int>[1, 2]), <Object?>[1, 2]);
    });
  });

  group('sql_util', () {
    test('asText：null 存 NULL，string 原样，别的 ToString', () {
      expect(asText(null), isNull);
      expect(asText('abc'), 'abc');
      expect(asText(12), '12');
      expect(asText(true), 'true');
    });

    test('asNum：不是有限数就走兜底', () {
      expect(asNum(3), 3);
      expect(asNum('3.5'), 3.5);
      expect(asNum('abc', 7), 7);
      expect(asNum(null, 2.5), 2.5);
      expect(asNum(double.nan, 1), 1);
      expect(asNum(double.infinity, 1), 1);
    });

    test('asList / asRecord：坏形状给空，不变成 null', () {
      expect(asList<Object?>(null), isEmpty);
      expect(asList<Object?>(<Object?>[1, 'a']), <Object?>[1, 'a']);
      expect(asRecord(<String, Object?>{'a': 1}), <String, Object?>{'a': 1});
      expect(asRecord(<Object?>[1]), isNull);
      expect(asRecord('x'), isNull);
      expect(isRecord(<String, Object?>{}), isTrue);
      expect(isRecord(<Object?>[]), isFalse);
    });

    test('nowIso 是 UTC ISO 串', () {
      final s = nowIso();
      expect(s.endsWith('Z'), isTrue);
      expect(DateTime.tryParse(s), isNotNull);
    });
  });
}
