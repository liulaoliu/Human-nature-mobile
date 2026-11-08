/// 已保存文章的读写。
///
/// 与词库仓储同一套结构：`articles.payload` 是事实来源，旁边几列
/// （title / book / source_key / created_at / sentence_count / word_count）
/// 只服务于列表排序与筛选，写完主表就顺手重建派生表（`projections.dart`）。
///
/// 落盘形状见 `lib/core/article_json.dart`；读回来一律过
/// `lib/core/backup_parse.dart:parseSavedArticle` 的守卫 —— **不许**
/// `jsonDecode(...) as ...` 直接进业务，库里旧版本写下的字段可能不全。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../core/article_json.dart';
import '../../core/backup_parse.dart';
import '../../models/document.dart';
import '../db/migrations.dart';
import '../db/projections.dart';
import '../db/sql_util.dart';

/// 列表页要的一行（不解 payload 全文，省内存）。
class ArticleRow {
  const ArticleRow({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.book,
    this.sourceKey,
    this.createdAt,
    this.sentenceCount = 0,
    this.wordCount = 0,
  });

  final String id;
  final String title;
  final String? book;
  final String? sourceKey;
  final String updatedAt;
  final String? createdAt;
  final int sentenceCount;
  final int wordCount;
}

/// 文章读写。
class ArticleRepository {
  ArticleRepository(this._db);

  /// 打开仓储：先确保 schema 迁到当前版本。
  static Future<ArticleRepository> open(DatabaseExecutor db) async {
    await ensureSchema(db);
    return ArticleRepository(db);
  }

  final DatabaseExecutor _db;

  final GZipCodec _gzip = GZipCodec(level: 6);

  Future<T> _tx<T>(Future<T> Function(DatabaseExecutor t) fn) async {
    final db = _db;
    if (db is Database) return db.transaction<T>((t) => fn(t));
    return fn(db);
  }

  Uint8List _pack(String json) =>
      Uint8List.fromList(_gzip.encode(utf8.encode(json)));

  String _unpack(Object? value) {
    if (value is String) return value;
    if (value is Uint8List) return utf8.decode(_gzip.decode(value));
    if (value is List<int>) return utf8.decode(_gzip.decode(value));
    return value?.toString() ?? '';
  }

  /// 列表（新的在前）。
  ///
  /// 只读列不读 payload：几万篇的库里，列表页把每篇正文都解一遍会卡住首帧。
  Future<List<ArticleRow>> list() async {
    final rows = await _db.rawQuery(
      'SELECT id, title, book, source_key, created_at, updated_at, '
      'sentence_count, word_count FROM articles ORDER BY updated_at DESC',
    );
    return [for (final row in rows) _rowOf(row)];
  }

  /// 按来源键找一篇（原文库导入去重用）。
  Future<ArticleRow?> findBySourceKey(String sourceKey) async {
    final rows = await _db.rawQuery(
      'SELECT id, title, book, source_key, created_at, updated_at, '
      'sentence_count, word_count FROM articles WHERE source_key = ? LIMIT 1',
      [sourceKey],
    );
    if (rows.isEmpty) return null;
    return _rowOf(rows.first);
  }

  /// 某一篇的元信息（不含正文）。
  Future<ArticleRow?> meta(String id) async {
    final rows = await _db.rawQuery(
      'SELECT id, title, book, source_key, created_at, updated_at, '
      'sentence_count, word_count FROM articles WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    return _rowOf(rows.first);
  }

  /// 读整篇；没有或形状坏掉返回 null。
  Future<SavedArticle?> load(String id) async {
    final rows = await _db.rawQuery(
      'SELECT payload, created_at FROM articles WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    return _decode(rows.first);
  }

  /// 全部文章（导出 / 备份用；按更新时间升序，回放顺序稳定）。
  Future<List<SavedArticle>> loadAll() async {
    final rows = await _db.rawQuery(
      'SELECT payload, created_at FROM articles ORDER BY updated_at ASC',
    );
    final out = <SavedArticle>[];
    for (final row in rows) {
      final article = _decode(row);
      if (article == null) continue;
      out.add(article);
    }
    return out;
  }

  /// payload → 篇对象；`createdAt` 用列补。
  ///
  /// 为什么要补：payload 里的 `createdAt` 是老字段，早期文章没有；库旁边那列
  /// `created_at` 才是「这篇什么时候建的」的事实（每次保存都会守住它）。
  /// 不补的话，编辑过一次的文件再从库里读出来就变成「没有创建时间」。
  SavedArticle? _decode(Map<String, Object?> row) {
    final decoded = parsePayload(_unpack(row['payload']));
    if (decoded == null) return null;
    final article = parseSavedArticle(decoded);
    if (article == null) return null;
    if (article.createdAt != null && article.createdAt!.isNotEmpty) {
      return article;
    }
    final column = asText(row['created_at']);
    if (column == null || column.isEmpty) return article;
    return article.copyWith(createdAt: () => column);
  }

  /// 保存一篇，返回库里记下的 updatedAt。
  ///
  /// [SavedArticle.id] 必须非空：空 id 会写成一行永远读不回来的垃圾
  /// （`articles.id` 是主键，空串也占位），所以这里直接抛。
  ///
  /// createdAt 的回退顺序是 `article.createdAt → 库里原有的 → updatedAt`：
  /// 编辑一次就把创建时间刷成现在，等于把「这篇文章多久了」永久丢掉。
  Future<String> save(SavedArticle article) async {
    if (article.id.trim().isEmpty) {
      throw ArgumentError.value(article.id, 'article.id', '文章 id 不能为空');
    }
    final updatedAt = article.updatedAt;
    final payload = jsonEncode(articleToJson(article));
    final packed = _pack(payload);
    final sentenceCount = article.sentences.length;
    final wordCount = articleWordCount(article);

    return _tx((t) async {
      final prevRows = await t.rawQuery(
        'SELECT created_at FROM articles WHERE id = ?',
        [article.id],
      );
      final prevCreatedAt =
          prevRows.isEmpty ? null : asText(prevRows.first['created_at']);
      final createdAt = (article.createdAt?.isNotEmpty ?? false)
          ? article.createdAt!
          : (prevCreatedAt != null && prevCreatedAt.isNotEmpty)
              ? prevCreatedAt
              : updatedAt;

      await t.rawInsert(
        'INSERT OR REPLACE INTO articles '
        '(id, payload, title, book, source_key, created_at, updated_at, '
        'sentence_count, word_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          article.id,
          packed,
          article.title,
          article.book,
          article.sourceKey,
          createdAt,
          updatedAt,
          sentenceCount,
          wordCount,
        ],
      );
      // 派生表吃的是刚落盘的 JSON，不是内存对象：两边形状必须一致，
      // 否则「保存后再保存」会被判成内容变了。
      await rebuildArticleProjection(t, articleToJson(article));
      return updatedAt;
    });
  }

  /// 删一篇（派生表一起删，不留孤儿句）。
  Future<void> remove(String id) async {
    await _tx((t) async {
      await deleteArticleProjection(t, id);
      await t.rawDelete('DELETE FROM articles WHERE id = ?', [id]);
    });
  }

  /// 篇数（列表页顶部统计 / 导出前校验）。
  Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM articles');
    return rows.isEmpty ? 0 : asNum(rows.first['n']).toInt();
  }

  /// 把 WAL 并回主库（关库前调用）。
  Future<void> checkpoint() async {
    try {
      await _db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // 还有别的连接在读：不影响已提交的数据。
    }
  }

  ArticleRow _rowOf(Map<String, Object?> row) => ArticleRow(
        id: asText(row['id']) ?? '',
        title: asText(row['title']) ?? '',
        book: asText(row['book']),
        sourceKey: asText(row['source_key']),
        createdAt: asText(row['created_at']),
        updatedAt: asText(row['updated_at']) ?? '',
        sentenceCount: asNum(row['sentence_count']).toInt(),
        wordCount: asNum(row['word_count']).toInt(),
      );
}
