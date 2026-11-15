/// payload 列的打包 / 解包 / **分块读**。
///
/// 为什么需要分块读：Android 的 sqflite 把查询结果放进 `CursorWindow`，
/// 而窗口有 **2MB 单行上限** —— 一行超过就抛
/// `DatabaseException(Row too big to fit into CursorWindow requiredPos=0,
/// totalRows=1)`，行里的 BLOB 和 TEXT 一样计入（不是「文本太大」，是「一行太大」）。
///
/// 词库整库 gzip 之后正好跨在这条线上：真机数据 16.4MB 的 JSON，`GZipCodec`
/// level 1 压完是 **2.14MB** —— 一次 `SELECT payload` 直接把窗口撑爆，
/// 于是奶牛工棚 / 精读 / 背单词 / 词库 / 拷打 / 考试全在报同一句错。
///
/// 解法：先 `length()` 问出字节数（只回一个数字，安全），再用
/// `substr(列, 起, 长)` 一小块一小块取回来自己拼。SQLite 的 `substr` 对 BLOB
/// 按**字节**切、对 TEXT 按字符切，所以两条老数据（明文 TEXT / gzip BLOB）都认。
library;

import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

/// 每次取多少字节。远小于 2MB 窗口（还要留给同一行里的别的列），
/// 2.14MB 的库分成 9 次取完，实测比一次超窗失败快得多。
const int payloadChunkBytes = 256 * 1024;

final GZipCodec _gzip = GZipCodec();

/// 明文 JSON → 落库字节（gzip）。
///
/// [level] 默认 1（最快档）：词库每次都整份重压，压得慢比压得小更值钱。
Uint8List packPayloadJson(String json, {int level = 1}) =>
    Uint8List.fromList(GZipCodec(level: level).encode(utf8.encode(json)));

/// 库里的那一列 → 明文 JSON。
///
/// 老数据是明文 TEXT，新写入是 gzip BLOB，两条都要认；认不出的类型退回
/// `toString()`（宁可让 `jsonDecode` 失败得到 null，也不静默换成空库）。
String? payloadJsonText(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Uint8List) return utf8.decode(_gzip.decode(value));
  if (value is List<int>) return utf8.decode(_gzip.decode(value));
  return value.toString();
}

/// 分块读一行的 payload 列，返回**库里的原始值**（TEXT 给 `String`，
/// BLOB 给 `Uint8List`），交给 [payloadJsonText] 还原。
///
/// 返回 null 表示「没有这一行」或「这一行是空的」，调用方按「没有 payload」处理。
///
/// [table] / [keyColumn] 只接受代码里的字面量（不接受外部输入拼 SQL）。
Future<Object?> readBigPayload(
  DatabaseExecutor db, {
  required String table,
  required String keyColumn,
  required Object key,
  String column = 'payload',
}) async {
  final where = '$keyColumn = ?';
  final head = await db.rawQuery(
    'SELECT typeof($column) AS kind, length($column) AS size FROM $table '
    'WHERE $where',
    <Object?>[key],
  );
  if (head.isEmpty) return null;
  final row = head.first;
  final size = row['size'];
  if (size == null) return null;
  final total = size is int ? size : int.tryParse('$size') ?? 0;
  if (total <= 0) return null;

  final isText = row['kind'] == 'text';
  if (isText) {
    final out = StringBuffer();
    for (var offset = 0; offset < total; offset += payloadChunkBytes) {
      final take = _take(total, offset);
      final rows = await db.rawQuery(
        'SELECT substr($column, ?, ?) AS chunk FROM $table WHERE $where',
        <Object?>[offset + 1, take, key],
      );
      if (rows.isEmpty) break;
      out.write(rows.first['chunk'] as String? ?? '');
    }
    return out.toString();
  }

  final out = Uint8List(total);
  var filled = 0;
  for (var offset = 0; offset < total; offset += payloadChunkBytes) {
    final take = _take(total, offset);
    final rows = await db.rawQuery(
      'SELECT substr($column, ?, ?) AS chunk FROM $table WHERE $where',
      <Object?>[offset + 1, take, key],
    );
    if (rows.isEmpty) break;
    final chunk = rows.first['chunk'];
    final bytes = switch (chunk) {
      Uint8List b => b,
      List<int> b => Uint8List.fromList(b),
      String s => Uint8List.fromList(s.codeUnits),
      _ => Uint8List(0),
    };
    out.setRange(filled, filled + bytes.length, bytes);
    filled += bytes.length;
  }
  return filled == total ? out : Uint8List.sublistView(out, 0, filled);
}

int _take(int total, int offset) {
  final left = total - offset;
  return left < payloadChunkBytes ? left : payloadChunkBytes;
}
