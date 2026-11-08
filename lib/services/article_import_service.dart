/// 文章导入编排：粘贴原文 → 落库。
///
/// 对应 Web 版 `src/reader/hooks/useArticleImport.ts` 的**服务层部分**，但只保留
/// 粘贴这一条路：本 App 不做 PDF / EPUB / 文件的自动抽取，正文一律用户自己贴进来。
///
/// 为什么不放在 core：它会写库（[ArticleRepository]），core 不许碰 data。
library;

import '../core/article_build.dart';
import '../data/repositories/article_repository.dart';
import '../models/document.dart';

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
      id: await _freeId(now ?? DateTime.now()),
      now: now,
    );
    await _articles.save(article);
    return article;
  }

  /// 同一毫秒连粘两次也不撞 id。
  ///
  /// 默认 id 是 `saved:<毫秒>`；`INSERT OR REPLACE` 遇到重复 id 会**直接覆盖**上一篇，
  /// 用户会觉得「刚建的那篇不见了」。撞了就往后加序号。
  Future<String> _freeId(DateTime at) async {
    final base = 'saved:${at.millisecondsSinceEpoch}';
    if (await _articles.meta(base) == null) return base;
    for (var i = 1;; i++) {
      final candidate = '$base:$i';
      if (await _articles.meta(candidate) == null) return candidate;
    }
  }
}
