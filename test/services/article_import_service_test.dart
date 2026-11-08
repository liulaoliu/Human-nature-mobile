import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<({Database db, ArticleRepository repo})> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return (db: db, repo: ArticleRepository(db));
}

void main() {
  late Database db;
  late ArticleRepository repo;
  late ArticleImportService service;

  setUp(() async {
    final opened = await _openMem();
    db = opened.db;
    repo = opened.repo;
    service = ArticleImportService(repo);
  });

  // 必须关：sqflite_common_ffi 对同一个 `:memory:` 路径会复用同一个连接，
  // 不关的话上一个用例的数据会漏到下一个（现象是 count 一直往上涨）。
  tearDown(() async {
    await db.close();
  });

  group('createFromText', () {
    test('空正文不建文章', () async {
      expect(await service.createFromText(raw: '   \n  '), isNull);
      expect(await repo.count(), 0);
    });

    test('建文章：清洗切句、标题兜底、来源标记', () async {
      final article = await service.createFromText(
        raw: 'First line.\n\nSecond line.',
        title: '  ',
      );
      expect(article, isNotNull);
      expect(article!.title, '未命名');
      expect(article.origin, ArticleOrigin.paste);
      expect(article.sentences.length, 2);
      expect(await repo.count(), 1);

      final back = await repo.load(article.id);
      expect(back!.text, article.text);
      expect(back.sentences.length, 2);
      expect(back.createdAt, isNotNull);
    });

    test('书名空白当没有', () async {
      final article = await service.createFromText(
        raw: 'Some text.',
        title: 'T',
        book: '   ',
      );
      expect(article!.book, isNull);
    });

    test('同一毫秒连建两篇也不撞 id', () async {
      final at = DateTime.utc(2026, 11, 8, 12);
      final a = await service.createFromText(raw: 'One.', now: at);
      final b = await service.createFromText(raw: 'Two.', now: at);
      expect(a!.id, isNot(b!.id));
      expect(await repo.count(), 2);
    });

    test('带书名的粘贴把书名写进 book 列', () async {
      final article = await service.createFromText(
        raw: 'Body.',
        title: 'T',
        book: 'The Economist',
      );
      expect(article!.book, 'The Economist');
      final back = await repo.load(article.id);
      expect(back!.book, 'The Economist');
    });
  });
}
