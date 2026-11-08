/// 文章导入编排：粘贴 / 文本文件 / EPUB / PDF 抽出的文本 → 落库。
///
/// 对应 Web 版 `src/reader/hooks/useArticleImport.ts` 的**服务层部分**。
/// Web 版把这个逻辑混在 React hook 里（还夹着 `FileReader` / `navigator.clipboard`）；
/// 这里只保留「拿到字符串之后做什么」，读文件和解压分别交给
/// `data/importers/epub_importer.dart` 与页面层的 file_picker。
///
/// 为什么不放在 core：它会写库（[ArticleRepository]），core 不许碰 data。
library;

import '../core/article_build.dart';
import '../models/document.dart';
import '../data/repositories/article_repository.dart';

/// 一个待导入的纯文本文件（文件名已去掉扩展名，当标题用）。
typedef ImportText = ({String name, String text});

/// 导入结果：存下来的文章 + 有没有因为来源键重复而跳过。
typedef ImportOutcome = ({List<SavedArticle> articles, int skipped});

/// 文章导入服务。
class ArticleImportService {
  ArticleImportService(this._articles);

  final ArticleRepository _articles;

  /// 粘贴 / 手输创建一篇。
  ///
  /// 与 Web 版一致：正文空白直接不建（返回 null），标题空则「未命名」。
  Future<SavedArticle?> createFromText({
    required String raw,
    String title = '',
    String? book,
    ArticleOrigin origin = ArticleOrigin.paste,
    DateTime? now,
  }) async {
    if (raw.trim().isEmpty) return null;
    final article = buildArticle(
      raw: raw,
      title: title,
      book: book,
      origin: origin,
      now: now,
    );
    await _articles.save(article);
    return article;
  }

  /// 批量导入文本文件：一个文件一篇，标题用文件名。
  ///
  /// id 用 `saved:<毫秒>:<序号>`：同一批里毫秒相同，不加序号会互相覆盖
  /// （Web 版踩过的坑，这里照抄它的解法）。
  Future<ImportOutcome> importTexts(
    List<ImportText> files, {
    String? book,
    DateTime? now,
  }) async {
    if (files.isEmpty) return (articles: const <SavedArticle>[], skipped: 0);
    final at = now ?? DateTime.now();
    final stamp = at.millisecondsSinceEpoch;
    final saved = <SavedArticle>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (file.text.trim().isEmpty) continue;
      final article = buildArticle(
        raw: file.text,
        title: file.name.trim().isEmpty ? '第 ${i + 1} 篇' : file.name,
        book: book,
        origin: ArticleOrigin.file,
        id: 'saved:$stamp:$i',
        now: at,
      );
      await _articles.save(article);
      saved.add(article);
    }
    return (articles: saved, skipped: files.length - saved.length);
  }

  /// 导入 EPUB 章节：一章一篇，标题形如「书名 · 章节」。
  ///
  /// 章节标题为空时退回「第 N 章」——与 Web 版一致，不留空标题。
  Future<ImportOutcome> importChapters(
    List<({String title, String text})> chapters, {
    required String book,
    DateTime? now,
  }) async {
    final bookName = book.trim();
    if (chapters.isEmpty) {
      return (articles: const <SavedArticle>[], skipped: 0);
    }
    final at = now ?? DateTime.now();
    final stamp = at.millisecondsSinceEpoch;
    final saved = <SavedArticle>[];
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      if (chapter.text.trim().isEmpty) continue;
      final chapterName =
          chapter.title.trim().isEmpty ? '第 ${i + 1} 章' : chapter.title.trim();
      final article = buildArticle(
        raw: chapter.text,
        title: bookName.isEmpty ? chapterName : '$bookName · $chapterName',
        book: bookName.isEmpty ? null : bookName,
        origin: ArticleOrigin.epub,
        id: 'saved:$stamp:$i',
        now: at,
      );
      await _articles.save(article);
      saved.add(article);
    }
    return (articles: saved, skipped: chapters.length - saved.length);
  }

  /// 从原文库导入一篇（按 `sourceKey` 去重）。
  ///
  /// 已有同 `sourceKey` 的文章直接返回那一篇的 id，不重复建 ——
  /// 原文库更新后重新导入，不会在「已保存」里堆一串同名文章。
  Future<({SavedArticle article, bool created})> importCatalogArticle({
    required String sourceKey,
    required String title,
    required String text,
    String? book,
    DateTime? now,
  }) async {
    final existing = await _articles.findBySourceKey(sourceKey);
    if (existing != null) {
      final loaded = await _articles.load(existing.id);
      if (loaded != null) return (article: loaded, created: false);
    }
    final article = buildArticle(
      raw: text,
      title: title,
      book: book,
      origin: ArticleOrigin.library,
      now: now,
    ).copyWith(sourceKey: () => sourceKey);
    await _articles.save(article);
    return (article: article, created: true);
  }
}
