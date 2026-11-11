import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/vocab_fixture.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

VocabLibrary _lib(List<VocabItem> items) => VocabLibrary(items: items);

void main() {
  late Database db;
  late VocabRepository repo;

  setUp(() async {
    db = await _openMem();
    repo = VocabRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('VocabRepository 基本读写', () {
    test('空库 load 返回 null（不是空库）', () async {
      expect(await repo.load(), isNull);
      expect(await repo.loadJson(), isNull);
      expect(await repo.meta(), isNull);
    });

    test('save 之后能读回来，条数与版本号都对', () async {
      final saved = await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha')]));
      expect(saved.changed, isTrue);
      expect(saved.count, 1);
      expect(saved.updatedAt, isNotEmpty);

      final loaded = await repo.load();
      expect(loaded!.items.map((e) => e.id), ['v1']);

      final meta = await repo.meta();
      expect(meta!.count, 1);
      expect(meta.at, saved.updatedAt);
    });

    test('payload 是 gzip BLOB，不是明文', () async {
      await repo.save(_lib([vocabItem(id: 'v1')]));
      final rows = await db.rawQuery('SELECT payload FROM vocab WHERE id = 1');
      expect(rows.first['payload'], isA<Uint8List>());
    });

    test('内容没变时第二次 save 不写，changed = false', () async {
      final first = await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha')]));
      final second = await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha')]));
      expect(second.changed, isFalse);
      expect(second.updatedAt, first.updatedAt);
      // 快照只有第一次写的那张。
      expect((await repo.listSnapshots()).length, 1);
    });

    test('内容变了才会换版本号', () async {
      final first = await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha')]));
      final second = await repo.save(
        _lib([vocabItem(id: 'v1', word: 'alpha'), vocabItem(id: 'v2', word: 'beta')]),
      );
      expect(second.changed, isTrue);
      expect(second.updatedAt.compareTo(first.updatedAt), greaterThan(0));
      expect(second.count, 2);
    });

    test('连续两次保存版本号严格递增（哪怕同一毫秒）', () async {
      await repo.save(_lib([vocabItem(id: 'v1')]));
      final a = (await repo.meta())!.at;
      await repo.save(_lib([vocabItem(id: 'v1'), vocabItem(id: 'v2')]));
      final b = (await repo.meta())!.at;
      await repo.save(_lib([vocabItem(id: 'v1')]));
      final c = (await repo.meta())!.at;
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(c), lessThan(0));
    });
  });

  group('VocabRepository 乐观锁', () {
    test('baseUpdatedAt 对得上就写成功', () async {
      final first = await repo.save(_lib([vocabItem(id: 'v1')]));
      final second = await repo.save(
        _lib([vocabItem(id: 'v1', word: 'beta')]),
        baseUpdatedAt: first.updatedAt,
      );
      expect(second.changed, isTrue);
    });

    test('baseUpdatedAt 过旧就抛 VocabConflict，并带上当前版本', () async {
      final first = await repo.save(_lib([vocabItem(id: 'v1')]));
      await repo.save(_lib([vocabItem(id: 'v1', word: 'beta')]));

      Object? caught;
      try {
        await repo.save(
          _lib([vocabItem(id: 'v1', word: 'gamma')]),
          baseUpdatedAt: first.updatedAt,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<VocabConflict>());
      final conflict = caught! as VocabConflict;
      expect(conflict.count, 1);
      // 冲突之后库里的内容没被改。
      expect((await repo.load())!.items.first.word, 'beta');
    });
  });

  group('VocabRepository 快照', () {
    test('快照最多留 12 张，新的在前', () async {
      for (var i = 0; i < 15; i++) {
        await repo.save(_lib([vocabItem(id: 'v1', word: 'w$i')]));
      }
      final snaps = await repo.listSnapshots();
      expect(snaps.length, vocabSnapshotKeep);
      for (var i = 1; i < snaps.length; i++) {
        expect(snaps[i - 1].at.compareTo(snaps[i].at), greaterThan(0));
      }
    });

    test('能按时间读回某一版快照', () async {
      await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha')]));
      await repo.save(_lib([vocabItem(id: 'v1', word: 'beta')]));

      final snaps = await repo.listSnapshots();
      expect(snaps.length, 2);
      final oldest = await repo.loadSnapshot(snaps.last.at);
      expect(oldest!.items.first.word, 'alpha');
      final newest = await repo.loadSnapshot(snaps.first.at);
      expect(newest!.items.first.word, 'beta');
    });

    test('快照时间不存在返回 null', () async {
      await repo.save(_lib([vocabItem(id: 'v1')]));
      expect(await repo.loadSnapshot('1999-01-01T00:00:00.000Z'), isNull);
    });
  });

  group('VocabRepository 其他', () {
    test('migrate 只在空库时写', () async {
      final first = await repo.migrate(_lib([vocabItem(id: 'v1', word: 'alpha')]));
      expect(first.migrated, isTrue);
      expect(first.value.items.length, 1);

      final second = await repo.migrate(_lib([vocabItem(id: 'v9', word: 'omega')]));
      expect(second.migrated, isFalse);
      // 返回值是库里已有的那份，不是传进去的那份。
      expect(second.value.items.first.id, 'v1');
      expect((await repo.load())!.items.first.id, 'v1');
    });

    test('clear 清掉词库与派生表', () async {
      await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha')]));
      expect((await db.rawQuery('SELECT COUNT(*) AS n FROM words'))
          .first['n'], 1);

      await repo.clear();
      expect(await repo.load(), isNull);
      expect((await db.rawQuery('SELECT COUNT(*) AS n FROM words'))
          .first['n'], 0);
      expect((await db.rawQuery('SELECT COUNT(*) AS n FROM word_contexts'))
          .first['n'], 0);
    });

    test('老库里的明文 payload 也能读（迁移前写下的）', () async {
      final json = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'items': <Object?>[
          <String, Object?>{'id': 'old', 'word': 'legacy', 'lemma': 'legacy'},
        ],
      });
      await db.rawInsert(
        'INSERT INTO vocab (id, payload, item_count, updated_at) VALUES (1, ?, ?, ?)',
        [json, 1, '2026-01-01T00:00:00.000Z'],
      );
      final loaded = await repo.load();
      expect(loaded!.items.single.word, 'legacy');
      expect((await repo.loadJson())!.json, json);
    });

    test('save 落盘前把句子原文收进共享表', () async {
      final lib = VocabLibrary(
        items: [
          vocabItem(
            id: 'v1',
            word: 'alpha',
            source: const VocabSource(
              articleId: 'A',
              fileName: '',
              sentenceId: 's1',
              sentenceText: 'Alpha is the first letter.',
            ),
          ),
          vocabItem(
            id: 'v2',
            word: 'beta',
            source: const VocabSource(
              articleId: 'A',
              fileName: '',
              sentenceId: 's1',
              sentenceText: 'Alpha is the first letter.',
            ),
          ),
        ],
      );
      await repo.save(lib);
      final decoded = jsonDecode((await repo.loadJson())!.json) as Map;
      // 同一句原文只存一份。
      final texts = decoded['sentenceTexts'] as Map;
      expect(texts.length, 1);
      final items = decoded['items'] as List;
      // 各引用里的原文被清空（键还在，值为空串），读回来才补。
      expect((items.first as Map)['source'],
          containsPair('sentenceText', ''));
      // 读回来字段又被补上了。
      final loaded = await repo.load();
      expect(loaded!.items.first.source!.sentenceText,
          'Alpha is the first letter.');
    });

    test('落盘的 JSON 是紧凑的（没有换行缩进）', () async {
      await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha')]));
      final json = (await repo.loadJson())!.json;
      expect(json, isNot(contains('\n')));
      expect(json, contains('"items"'));
    });

    test('gzip 压缩后确实比明文小', () async {
      final many = [
        for (var i = 0; i < 200; i++)
          vocabItem(id: 'v$i', word: 'word$i', meaning: '释义 $i'),
      ];
      await repo.save(_lib(many));
      final rows = await db.rawQuery('SELECT payload, length(payload) AS n FROM vocab');
      final packed = rows.first['payload'] as Uint8List;
      final plain = (await repo.loadJson())!.json;
      expect(packed.length, lessThan(plain.length));
      expect(GZipCodec().decode(packed), utf8.encode(plain));
    });
  });

  group('VocabRepository 读缓存', () {
    test('第二次 load 命中缓存：payload 被弄坏了也照样读得出来', () async {
      await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha', meaning: '甲')]));
      final first = await repo.load();
      expect(first!.items.single.meaning, '甲');

      // 版本号不动、只把 payload 弄成读不出来的东西 —— 真去解压就会炸。
      await db.rawUpdate("UPDATE vocab SET payload = ? WHERE id = 1", ['不是 JSON']);
      final second = await repo.load();
      expect(second!.items.single.meaning, '甲');
      expect(identical(second, first), isTrue, reason: '命中的应该是同一份对象');
    });

    test('外部把 updated_at 改了，缓存就失效，重新解压', () async {
      await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha', meaning: '甲')]));
      await repo.load(); // 先热一份缓存

      // 模拟「另一个进程/页面写了库」：换 payload + 换版本号。
      final next = jsonEncode({
        'schemaVersion': 1,
        'items': [
          {
            'id': 'v1',
            'word': 'alpha',
            'lemma': 'alpha',
            'meaning': '乙',
            'createdAt': '2026-11-11T00:00:00.000Z',
            'updatedAt': '2026-11-11T00:00:00.000Z',
          },
        ],
        'articleEntries': <Object>[],
        'tombstones': <Object>[],
        'sentenceTexts': <Object>[],
      });
      await db.rawUpdate(
        'UPDATE vocab SET payload = ?, updated_at = ? WHERE id = 1',
        [
          Uint8List.fromList(GZipCodec().encode(utf8.encode(next))),
          '2099-01-01T00:00:00.000Z',
        ],
      );

      final reloaded = await repo.load();
      expect(reloaded!.items.single.meaning, '乙');
    });

    test('save 之后缓存跟着换，不用重读盘', () async {
      await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha', meaning: '甲')]));
      await repo.load();

      await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha', meaning: '丙')]));
      await db.rawUpdate("UPDATE vocab SET payload = ? WHERE id = 1", ['坏了']);

      final after = await repo.load();
      expect(after!.items.single.meaning, '丙');
    });

    test('另一个 repository 实例没有缓存，仍走完整解析', () async {
      await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha', meaning: '甲')]));
      await repo.load();

      final other = VocabRepository(db);
      await db.rawUpdate("UPDATE vocab SET payload = ? WHERE id = 1", ['坏了']);
      expect(await other.load(), isNull, reason: '新实例没缓存，坏 payload 解不出来');
    });

    test('clear 之后缓存也清掉，再 load 回 null', () async {
      await repo.save(_lib([vocabItem(id: 'v1', word: 'alpha')]));
      await repo.load();
      await repo.clear();
      expect(await repo.load(), isNull);
    });
  });
}
