// 行级事实表（v15）的验收：写读往返**逐字节相同**、增量只动变了的行、
// 回填只加不改（`vocab.payload` 一个字节不动）。
//
// 「逐字节相同」是这一层的硬口径：`doc` 存的是词条 JSON 原文，拼回去必须能被
// `vocabPayloadRoundTrips` 认成同一份，否则「内容没变就不写库」的快路径会失效。
import 'dart:convert';

import 'package:dlaoshi_app/core/vocab/vocab_rows.dart';
import 'package:dlaoshi_app/data/db/schema.dart';
import 'package:dlaoshi_app/data/db/sql_util.dart';
import 'package:dlaoshi_app/data/db/vocab_rows_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 起内存库并建好 v1 + v15 的表（只测行存储，不用跑完整迁移链）。
Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(schemaV1);
  await db.execute(schemaV15);
  return db;
}

VocabRows _rows(
  List<Map<String, Object?>> items, {
  Map<String, Object?>? extras,
  int schemaVersion = 1,
}) =>
    splitVocabPayload(<String, Object?>{
      'schemaVersion': schemaVersion,
      'items': items,
      ...?extras,
    });

void main() {
  group('行键', () {
    test('有 id 用 id，没 id 用 @序号', () {
      final rows = _rows(<Map<String, Object?>>[
        <String, Object?>{'id': 'w1', 'word': 'alpha'},
        <String, Object?>{'word': 'noId'},
      ]);
      expect(rows.itemKeys, <String>['w1', '@1']);
    });

    test('重复 id 追加 @序号，键互不相同且顺序稳定', () {
      final rows = _rows(<Map<String, Object?>>[
        <String, Object?>{'id': 'dup'},
        <String, Object?>{'id': 'dup'},
        <String, Object?>{'id': 'ok'},
      ]);
      expect(rows.itemKeys, <String>['dup', 'dup@1', 'ok']);
      expect(rows.itemKeys.toSet().length, 3);
    });
  });

  group('整表重写与读回', () {
    test('写进去再读回来，逐字节相同且顺序不变', () async {
      final db = await _openMem();
      addTearDown(db.close);

      final rows = _rows(
        <Map<String, Object?>>[
          <String, Object?>{
            'id': 'b',
            'word': 'bravo',
            'reviewState': <String, Object?>{'relearn': true},
          },
          <String, Object?>{'id': 'a', 'word': 'alpha'},
        ],
        extras: <String, Object?>{
          'tombstones': <Object?>[
            <String, Object?>{'word': 'gone'},
          ],
          'articleEntries': <Object?>[
            <String, Object?>{'articleId': 'saved:1', 'word': 'alpha'},
          ],
        },
      );
      await replaceVocabRows(db, rows);

      final back = await readVocabRows(db);
      expect(back, isNotNull);
      expect(back!.schemaVersion, 1);
      expect(back.itemDocs, rows.itemDocs);
      expect(
        jsonEncode(assembleVocabPayload(back)),
        jsonEncode(assembleVocabPayload(rows)),
      );
      expect(
        back.extras.keys.toList(),
        <String>['tombstones', 'articleEntries'],
      );
    });

    test('空词库也写标记行，读回来是空行而不是 null', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await replaceVocabRows(db, _rows(const <Map<String, Object?>>[]));
      final back = await readVocabRows(db);
      expect(back, isNotNull);
      expect(back!.isEmpty, isTrue);
    });

    test('从没写过时读回来是 null（让调用方回退读 payload）', () async {
      final db = await _openMem();
      addTearDown(db.close);
      expect(await readVocabRows(db), isNull);
    });

    test('坏 doc 不影响其它行', () async {
      final db = await _openMem();
      addTearDown(db.close);
      await replaceVocabRows(
        db,
        _rows(<Map<String, Object?>>[
          <String, Object?>{'id': 'a', 'word': 'alpha'},
        ]),
      );
      await db.insert('vocab_extras', <String, Object?>{
        'key': 'weird',
        'ordinal': 5,
        'doc': '不是 JSON',
      });
      final back = await readVocabRows(db);
      expect(back, isNotNull);
      expect(back!.itemDocs.length, 1);
      expect(back.extras.containsKey('weird'), isFalse);
    });
  });

  group('syncVocabRows（增量写）', () {
    test('只改变了的行，其它行的 rowid 不动', () async {
      final db = await _openMem();
      addTearDown(db.close);

      final before = _rows(<Map<String, Object?>>[
        <String, Object?>{'id': 'w1', 'word': 'alpha'},
        <String, Object?>{'id': 'w2', 'word': 'bravo'},
        <String, Object?>{'id': 'w3', 'word': 'charlie'},
      ]);
      await replaceVocabRows(db, before);
      final rowidBefore = <String, Object?>{
        for (final r in await db.rawQuery('SELECT id, rowid FROM vocab_items'))
          asText(r['id'])!: r['rowid'],
      };

      final after = _rows(<Map<String, Object?>>[
        <String, Object?>{'id': 'w1', 'word': 'alpha'},
        <String, Object?>{
          'id': 'w2',
          'word': 'bravo',
          'reviewState': <String, Object?>{'repetitions': 3},
        },
        <String, Object?>{'id': 'w3', 'word': 'charlie'},
      ]);
      await syncVocabRows(db, after, prev: before);

      final rowidAfter = <String, Object?>{
        for (final r in await db.rawQuery('SELECT id, rowid FROM vocab_items'))
          asText(r['id'])!: r['rowid'],
      };
      expect(rowidAfter['w1'], rowidBefore['w1'], reason: '没变的行不该重写');
      expect(rowidAfter['w3'], rowidBefore['w3']);
      // 改过的那行是 UPDATE（rowid 不变），不是 delete + insert。
      expect(rowidAfter['w2'], rowidBefore['w2']);

      final back = await readVocabRows(db);
      expect(back!.itemDocs, after.itemDocs);
    });

    test('不知道上一份（prev = null）时整表重写，结果仍然正确', () async {
      final db = await _openMem();
      addTearDown(db.close);

      await replaceVocabRows(
        db,
        _rows(<Map<String, Object?>>[
          <String, Object?>{'id': 'old', 'word': 'gone'},
        ]),
      );
      final next = _rows(<Map<String, Object?>>[
        <String, Object?>{'id': 'new', 'word': 'fresh'},
      ]);
      await syncVocabRows(db, next);

      final back = await readVocabRows(db);
      expect(back!.itemDocs, next.itemDocs);
      expect(back.itemKeys, <String>['new']);
    });

    test('词条增减（键列表变了）走整表重写，不留孤儿行', () async {
      final db = await _openMem();
      addTearDown(db.close);

      final before = _rows(<Map<String, Object?>>[
        <String, Object?>{'id': 'w1'},
        <String, Object?>{'id': 'w2'},
      ]);
      await replaceVocabRows(db, before);
      final after = _rows(<Map<String, Object?>>[
        <String, Object?>{'id': 'w1'},
      ]);
      await syncVocabRows(db, after, prev: before);

      final ids = <String>[
        for (final r in await db.rawQuery('SELECT id FROM vocab_items'))
          asText(r['id']) ?? '',
      ];
      expect(ids, <String>['w1']);
    });

    test('只改库级零碎也同步（tombstones 变了要写进去）', () async {
      final db = await _openMem();
      addTearDown(db.close);

      final before = _rows(
        <Map<String, Object?>>[
          <String, Object?>{'id': 'w1'},
        ],
        extras: <String, Object?>{
          'tombstones': <Object?>[
            <String, Object?>{'id': 'x'},
          ],
        },
      );
      await replaceVocabRows(db, before);
      final after = _rows(
        <Map<String, Object?>>[
          <String, Object?>{'id': 'w1'},
        ],
        extras: <String, Object?>{
          'tombstones': <Object?>[
            <String, Object?>{'id': 'x'},
            <String, Object?>{'id': 'y'},
          ],
        },
      );
      await syncVocabRows(db, after, prev: before);

      final back = await readVocabRows(db);
      expect(back!.extras['tombstones'], hasLength(2));
      expect(back.itemDocs, after.itemDocs);
    });

    test('库级零碎整段消失时不留旧键', () async {
      final db = await _openMem();
      addTearDown(db.close);

      final before = _rows(
        <Map<String, Object?>>[
          <String, Object?>{'id': 'w1'},
        ],
        extras: <String, Object?>{
          'tombstones': <Object?>[
            <String, Object?>{'id': 'x'},
          ],
        },
      );
      await replaceVocabRows(db, before);
      final after = _rows(<Map<String, Object?>>[
        <String, Object?>{'id': 'w1'},
      ]);
      await syncVocabRows(db, after, prev: before);

      final back = await readVocabRows(db);
      expect(back!.extras.containsKey('tombstones'), isFalse);
    });

    test('schemaVersion 变了要写进去（否则拼回去版本号回退）', () async {
      final db = await _openMem();
      addTearDown(db.close);

      final before = _rows(
        <Map<String, Object?>>[
          <String, Object?>{'id': 'w1'},
        ],
        schemaVersion: 1,
      );
      await replaceVocabRows(db, before);
      final after = _rows(
        <Map<String, Object?>>[
          <String, Object?>{'id': 'w1'},
        ],
        schemaVersion: 3,
      );
      await syncVocabRows(db, after, prev: before);

      final back = await readVocabRows(db);
      expect(back!.schemaVersion, 3);
    });
  });

  group('库级大字段（真机 CursorWindow 上限）', () {
    test('单段超过 2MB 的 sentenceTexts 能写进去又读回来', () async {
      final db = await _openMem();
      addTearDown(db.close);

      // 真机上 `sentenceTexts` 是**一整段 13MB**，一次 `SELECT doc` 会撑爆
      // Android 的 CursorWindow（单行 2MB），桌面 ffi 没有这个上限所以测不出来
      // —— 2026-11-21 就是这么在真机上炸的。这里塞一段超过 2MB 的，
      // 至少保证「大字段走的是分块读那条路」不会在重构里被悄悄改回整行读。
      final big = <String, Object?>{
        for (var i = 0; i < 6000; i++)
          'article$i\u0000sentence$i': 'line $i ' * 40,
      };
      final rows = _rows(
        <Map<String, Object?>>[
          <String, Object?>{'id': 'w1', 'word': 'alpha'},
        ],
        extras: <String, Object?>{'sentenceTexts': big},
      );
      expect(utf8.encode(jsonEncode(big)).length, greaterThan(2 * 1024 * 1024));

      await replaceVocabRows(db, rows);
      final back = await readVocabRows(db);
      expect(back, isNotNull);
      expect(back!.extras['sentenceTexts'], big);
      expect(back.itemDocs.length, 1);
    });
  });

  group('backfillVocabRows', () {
    test('把 vocab.payload 拆进行表，payload 一个字节不动', () async {
      final db = await _openMem();
      addTearDown(db.close);

      final payloadJson = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'items': <Object?>[
          <String, Object?>{
            'id': 'w1',
            'word': 'alpha',
            'reviewState': <String, Object?>{'meaningPasses': 3},
          },
        ],
        'tombstones': <Object?>[
          <String, Object?>{'word': 'gone'},
        ],
      });
      await db.insert('vocab', <String, Object?>{
        'id': 1,
        'payload': payloadJson,
        'item_count': 1,
        'updated_at': '2026-01-01T00:00:00.000Z',
      });

      expect(await backfillVocabRows(db), 1);

      final back = await readVocabRows(db);
      expect(back, isNotNull);
      expect(back!.itemDocs.length, 1);
      expect(back.extras['tombstones'], isNotNull);

      final row = (await db.rawQuery(
        'SELECT payload FROM vocab WHERE id = 1',
      )).first;
      expect(asText(row['payload']), payloadJson, reason: 'payload 必须原样保留');
    });

    test('库里没有词库时返回 0，不建标记行', () async {
      final db = await _openMem();
      addTearDown(db.close);
      expect(await backfillVocabRows(db), 0);
      expect(await readVocabRows(db), isNull);
    });

    test('重复跑幂等（不重复插入、不丢词条）', () async {
      final db = await _openMem();
      addTearDown(db.close);
      await db.insert('vocab', <String, Object?>{
        'id': 1,
        'payload': jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'items': <Object?>[
            <String, Object?>{'id': 'w1'},
            <String, Object?>{'id': 'w2'},
          ],
        }),
        'item_count': 2,
        'updated_at': '2026-01-01T00:00:00.000Z',
      });

      expect(await backfillVocabRows(db), 2);
      expect(await backfillVocabRows(db), 2);
      final back = await readVocabRows(db);
      expect(back!.itemDocs.length, 2);
      final counted = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM vocab_items',
      );
      expect(asNum(counted.first['n']).toInt(), 2);
    });
  });
}