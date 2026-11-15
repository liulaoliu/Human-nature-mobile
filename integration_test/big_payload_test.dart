// 真机 / 模拟器上验证「单行 >2MB 也能读回来」。
//
// 背景（2026-11-15，用户 m01901）：词库整库压成 gzip 后约 2.14MB，超过 Android
// CursorWindow 的 2MB 单行上限，读 `SELECT payload FROM vocab WHERE id = 1` 时抛
// `DatabaseException(Row too big to fit into CursorWindow requiredPos=0, totalRows=1)`。
//
// `test/data/db/payload_codec_test.dart` 在桌面上验的是逻辑；这里在真实 Android
// 设备上验的是「sqflite + CursorWindow」这一层，两者不能互相替代 —— 桌面用的是
// sqlite3 ffi，没有 CursorWindow 限制。
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:dlaoshi_app/data/db/payload_codec.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('单行 4MB 的 payload 能分块读回来，不抛 CursorWindow', (tester) async {
    await tester.runAsync(() async {
      final dir = await getDatabasesPath();
      final path = '$dir/big_payload_probe.db';
      await deleteDatabase(path);
      final db = await openDatabase(path);

      Object? error;
      var same = false;
      var size = 0;
      final watch = Stopwatch()..start();
      try {
        await db.execute(
          'CREATE TABLE vocab (id INTEGER PRIMARY KEY, payload BLOB NOT NULL)',
        );
        // 4MB 随机字节：随机内容不可压缩，也不会被 SQLite 截断。
        final random = Random(20261115);
        final bytes = Uint8List(4 * 1024 * 1024);
        for (var i = 0; i < bytes.length; i++) {
          bytes[i] = random.nextInt(256);
        }
        await db.insert('vocab', <String, Object?>{'id': 1, 'payload': bytes});
        size = bytes.length;

        final read = await readBigPayload(
          db,
          table: 'vocab',
          keyColumn: 'id',
          key: 1,
        );
        final back = switch (read) {
          Uint8List b => b,
          List<int> b => Uint8List.fromList(b),
          _ => Uint8List(0),
        };
        same = back.length == bytes.length;
        if (same) {
          for (var i = 0; i < bytes.length; i++) {
            if (back[i] != bytes[i]) {
              same = false;
              break;
            }
          }
        }
      } catch (e) {
        error = e;
      } finally {
        watch.stop();
        await db.close();
        await deleteDatabase(path);
      }

      // ignore: avoid_print
      print('[big] 写入 $size 字节，读回一致=$same，'
          '耗时 ${watch.elapsedMilliseconds}ms，error=$error');
      expect(error, isNull, reason: '真机上读大行不该再抛 CursorWindow');
      expect(same, isTrue, reason: '分块读回来的字节必须与写入完全一致');
    });
  });

  testWidgets('两列都在同一行时也不超窗（词库表真实形状）', (tester) async {
    await tester.runAsync(() async {
      final dir = await getDatabasesPath();
      final path = '$dir/big_payload_probe2.db';
      await deleteDatabase(path);
      final db = await openDatabase(path);

      Object? error;
      var ok = false;
      final watch = Stopwatch()..start();
      try {
        await db.execute(
          'CREATE TABLE vocab (id INTEGER PRIMARY KEY CHECK (id = 1), '
          'payload BLOB NOT NULL, item_count INTEGER NOT NULL, '
          'updated_at TEXT NOT NULL)',
        );
        const count = 12000;
        final items = <Map<String, Object?>>[
          for (var i = 0; i < count; i++)
            <String, Object?>{
              'id': 'w$i',
              'word': 'word$i',
              'meaning': '释义 $i 一个比较长的中文解释，用来把 JSON 撑大',
              'sourceTitle': 'The Economist 2026-11-10',
            },
        ];
        final json = '{"items":$items}';
        final packed = packPayloadJson(json);
        await db.insert('vocab', <String, Object?>{
          'id': 1,
          'payload': packed,
          'item_count': count,
          'updated_at': '2026-11-15T00:00:00.000Z',
        });

        final read = await readBigPayload(
          db,
          table: 'vocab',
          keyColumn: 'id',
          key: 1,
        );
        ok = payloadJsonText(read) == json;
        // ignore: avoid_print
        print('[big2] JSON ${json.length} 字符 → gzip ${packed.length} 字节，'
            '读回一致=$ok，耗时 ${watch.elapsedMilliseconds}ms');
      } catch (e) {
        error = e;
      } finally {
        watch.stop();
        await db.close();
        await deleteDatabase(path);
      }

      expect(error, isNull, reason: '词库表真实形状也不该超窗');
      expect(ok, isTrue, reason: 'gzip 往返必须一致');
    });
  });
}
