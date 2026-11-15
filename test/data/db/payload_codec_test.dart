import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/db/payload_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return db;
}

/// 造一段「压不扁」的明文：随机 ASCII 字母数字，gzip 之后体积几乎不缩
/// （用它才能造出真机那种「一行超过 2MB」的 payload）。
/// 注意别用「重复几个字」或线性同余的高位当噪声 —— 那样 gzip 能压到几十分之一，
/// 造出来的行其实只有几十 KB（2026-11-15 踩过）。
String _bigJson(int items, {int noiseLen = 160}) {
  final rnd = Random(20261115);
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  String noise(int len) {
    final b = StringBuffer();
    for (var i = 0; i < len; i++) {
      b.write(alphabet[rnd.nextInt(alphabet.length)]);
    }
    return b.toString();
  }

  final rows = <String>[
    for (var i = 0; i < items; i++)
      '{"id":"v$i","word":"w$i","meaning":"释义 $i",'
          '"sentenceText":"${noise(noiseLen)}"}',
  ];
  return '{"items":[${rows.join(',')}]}';
}

/// 一直加量，直到 gzip 后的体积真的超过 CursorWindow（2MB）。
String _bigJsonAboveWindow() {
  var items = 2000;
  while (true) {
    final json = _bigJson(items, noiseLen: 600);
    if (packPayloadJson(json).length > 2 * 1024 * 1024 + 65536) return json;
    items *= 2;
  }
}

void main() {
  late Database db;

  setUp(() async {
    db = await _openMem();
  });

  tearDown(() async {
    await db.close();
  });

  group('payload_codec 打包 / 解包', () {
    test('packPayloadJson 压出来是 BLOB，走 payloadJsonText 能还原', () {
      const json = '{"items":[{"id":"v1","word":"alpha"}]}';
      final packed = packPayloadJson(json);
      expect(packed, isA<Uint8List>());
      expect(packed.length, lessThan(utf8.encode(json).length + 32));
      expect(payloadJsonText(packed), json);
    });

    test('老数据是明文 TEXT 时原样返回', () {
      expect(payloadJsonText('{"a":1}'), '{"a":1}');
    });

    test('List<int> 也认（某些驱动把 BLOB 交成普通列表）', () {
      final packed = packPayloadJson('{"a":1}');
      expect(payloadJsonText(packed.toList()), '{"a":1}');
    });

    test('null 给 null，怪值退回 toString', () {
      expect(payloadJsonText(null), isNull);
      expect(payloadJsonText(42), '42');
    });
  });

  group('readBigPayload 分块读', () {
    test('没有这一行返回 null', () async {
      expect(
        await readBigPayload(db, table: 'vocab', keyColumn: 'id', key: 1),
        isNull,
      );
    });

    test('BLOB 超过一块时能拼回原样（少量数据也走同一条路）', () async {
      final json = _bigJson(40);
      final packed = packPayloadJson(json);
      await db.rawInsert(
        'INSERT INTO vocab (id, payload, item_count, updated_at) '
        'VALUES (1, ?, 40, ?)',
        [packed, '2026-01-01T00:00:00.000Z'],
      );

      final raw = await readBigPayload(
        db,
        table: 'vocab',
        keyColumn: 'id',
        key: 1,
      );
      expect(raw, isA<Uint8List>());
      expect(payloadJsonText(raw), json);
    });

    test('单行远超 2MB 也能读回来（真机 CursorWindow 的场景）', () async {
      final json = _bigJsonAboveWindow();
      final packed = packPayloadJson(json);
      // 这条用例的意义就在这个断言上：一行比窗口大，真机上一次 SELECT 会抛
      // Row too big to fit into CursorWindow。
      expect(packed.length, greaterThan(2 * 1024 * 1024));

      await db.rawInsert(
        'INSERT INTO vocab (id, payload, item_count, updated_at) '
        'VALUES (1, ?, 0, ?)',
        [packed, '2026-01-01T00:00:00.000Z'],
      );

      final raw = await readBigPayload(
        db,
        table: 'vocab',
        keyColumn: 'id',
        key: 1,
      );
      final text = payloadJsonText(raw)!;
      expect(text.length, json.length);
      expect(text, json);
      expect(jsonDecode(text), jsonDecode(json));
    });

    test('老数据是明文 TEXT 时按字符分块，读回来一字不差', () async {
      final json = _bigJson(200);
      await db.rawInsert(
        'INSERT INTO vocab (id, payload, item_count, updated_at) '
        'VALUES (1, ?, 200, ?)',
        [json, '2026-01-01T00:00:00.000Z'],
      );

      final raw = await readBigPayload(
        db,
        table: 'vocab',
        keyColumn: 'id',
        key: 1,
      );
      expect(raw, isA<String>());
      expect(raw, json);
    });

    test('快照表用 at 当键，同样能分块读', () async {
      final json = _bigJson(30);
      final packed = packPayloadJson(json);
      await db.rawInsert(
        'INSERT INTO vocab_snapshots (at, payload, item_count) VALUES (?, ?, 30)',
        ['snap-1', packed],
      );

      final raw = await readBigPayload(
        db,
        table: 'vocab_snapshots',
        keyColumn: 'at',
        key: 'snap-1',
      );
      expect(payloadJsonText(raw), json);
      expect(
        await readBigPayload(
          db,
          table: 'vocab_snapshots',
          keyColumn: 'at',
          key: 'nope',
        ),
        isNull,
      );
    });

    test('空 payload 当没有处理（不返回空串把库读成空）', () async {
      await db.rawInsert(
        'INSERT INTO vocab (id, payload, item_count, updated_at) '
        "VALUES (1, '', 0, ?)",
        ['2026-01-01T00:00:00.000Z'],
      );
      expect(
        await readBigPayload(db, table: 'vocab', keyColumn: 'id', key: 1),
        isNull,
      );
    });
  });
}
