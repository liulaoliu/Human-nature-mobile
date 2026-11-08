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
        origin: ArticleOrigin.file,
      );
      expect(article, isNotNull);
      expect(article!.title, '未命名');
      expect(article.origin, ArticleOrigin.file);
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
  });

  group('importTexts', () {
    test('一个文件一篇，标题用文件名，id 带序号不互相覆盖', () async {
      final out = await service.importTexts([
        (name: 'Alpha', text: 'Alpha text.'),
        (name: 'Beta', text: 'Beta text.'),
      ]);
      expect(out.articles.length, 2);
      expect(out.skipped, 0);
      expect(out.articles.map((a) => a.title).toList(), ['Alpha', 'Beta']);
      expect(out.articles.first.id, isNot(out.articles.last.id));
      expect(out.articles.first.origin, ArticleOrigin.file);
      expect(await repo.count(), 2);
    });

    test('空文件跳过并计入 skipped', () async {
      final out = await service.importTexts([
        (name: 'Good', text: 'Good text.'),
        (name: 'Empty', text: '   '),
      ]);
      expect(out.articles.length, 1);
      expect(out.skipped, 1);
      expect(await repo.count(), 1);
    });

    test('空列表什么都不做', () async {
      final out = await service.importTexts(const []);
      expect(out.articles, isEmpty);
      expect(out.skipped, 0);
    });

    test('文件名空时用「第 N 篇」', () async {
      final out = await service.importTexts([(name: '  ', text: 'Body text.')]);
      expect(out.articles.single.title, '第 1 篇');
    });

    test('同一本书的批量导入带上书名', () async {
      final out = await service.importTexts(
        [(name: 'Ch1', text: 'One.'), (name: 'Ch2', text: 'Two.')],
        book: 'My Book',
      );
      expect(out.articles.every((a) => a.book == 'My Book'), isTrue);
    });
  });

  group('importChapters', () {
    test('一章一篇，标题「书名 · 章节」，来源 epub', () async {
      final out = await service.importChapters(
        [
          (title: 'Chapter One', text: 'First chapter.'),
          (title: 'Chapter Two', text: 'Second chapter.'),
        ],
        book: 'A Book',
      );
      expect(out.articles.length, 2);
      expect(out.articles.first.title, 'A Book · Chapter One');
      expect(out.articles.first.book, 'A Book');
      expect(out.articles.first.origin, ArticleOrigin.epub);
      expect(await repo.count(), 2);
    });

    test('章节标题空时用「第 N 章」', () async {
      final out = await service.importChapters(
        [
          (title: '', text: 'Untitled chapter.'),
        ],
        book: 'B',
      );
      expect(out.articles.single.title, 'B · 第 1 章');
    });

    test('书名空时标题只用章节名', () async {
      final out = await service.importChapters(
        [
          (title: 'Only', text: 'Body.'),
        ],
        book: '   ',
      );
      expect(out.articles.single.title, 'Only');
      expect(out.articles.single.book, isNull);
    });

    test('空章节跳过', () async {
      final out = await service.importChapters(
        [
          (title: 'A', text: '   '),
          (title: 'B', text: 'Real text.'),
        ],
        book: 'B',
      );
      expect(out.articles.length, 1);
      expect(out.skipped, 1);
    });

    test('空列表什么都不做', () async {
      final out = await service.importChapters(const [], book: 'X');
      expect(out.articles, isEmpty);
      expect(await repo.count(), 0);
    });
  });

  group('importCatalogArticle', () {
    test('首次导入建文章并写上 sourceKey', () async {
      final out = await service.importCatalogArticle(
        sourceKey: '005 Leaders',
        title: 'Post-truth politics',
        text: 'Body text here.',
        book: 'The Economist',
      );
      expect(out.created, isTrue);
      expect(out.article.sourceKey, '005 Leaders');
      expect(out.article.origin, ArticleOrigin.library);
      expect(await repo.count(), 1);
    });

    test('同 sourceKey 再导入不重复建，返回原文', () async {
      final first = await service.importCatalogArticle(
        sourceKey: 'k1',
        title: 'First title',
        text: 'Body text.',
      );
      final second = await service.importCatalogArticle(
        sourceKey: 'k1',
        title: 'Changed title',
        text: 'Different body.',
      );
      expect(second.created, isFalse);
      expect(second.article.id, first.article.id);
      expect(second.article.title, 'First title');
      expect(await repo.count(), 1);
    });

    test('不同 sourceKey 建两篇', () async {
      await service.importCatalogArticle(
        sourceKey: 'k1',
        title: 'A',
        text: 'Body A.',
      );
      await service.importCatalogArticle(
        sourceKey: 'k2',
        title: 'B',
        text: 'Body B.',
      );
      expect(await repo.count(), 2);
    });
  });
}
