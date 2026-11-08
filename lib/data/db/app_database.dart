/// 真机 / 桌面上的数据库入口：打开 `dlaoshi.db` 并跑完 13 版迁移。
///
/// 测试与别的地方要用内存库时，直接 `sqflite_common_ffi` 开库再调
/// `ensureSchema` 即可 —— 这里只负责「应用主库在哪、怎么开」。
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// 应用主库文件名。
const String appDatabaseName = 'dlaoshi.db';

/// 打开应用主库（不存在则建）并保证 schema 已迁到当前版本。
///
/// [path] 只给测试用；真机一律走 `getDatabasesPath()`。
Future<Database> openAppDatabase({String? path}) async {
  final dbPath = path ?? p.join(await getDatabasesPath(), appDatabaseName);
  final db = await openDatabase(
    dbPath,
    onConfigure: (db) async {
      // 词库整体是一个大 JSON 列，WAL 下读写不互相堵。
      await db.execute('PRAGMA journal_mode=WAL');
      await db.execute('PRAGMA synchronous=FULL');
      await db.execute('PRAGMA busy_timeout=3000');
    },
  );
  await ensureSchema(db);
  return db;
}
