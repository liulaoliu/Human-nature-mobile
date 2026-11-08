/// 新建文章：原始文本 → 清洗 → 切句 → `SavedArticle`。
///
/// 对应 Web 版 `src/reader/hooks/useArticleImport.ts` 里 `createArticle` 的**纯逻辑部分**
/// （那边混着 `navigator.clipboard`、`FileReader`、`JSZip` 等浏览器能力，不适合照搬）。
///
/// 这里只做确定性的三件事：洗文本、切句、拼 id 与时间戳。
/// 正文一律由用户粘贴进来 —— 本 App 不做 PDF / EPUB / 文件的自动抽取，
/// 所以这里只拿到一个字符串，能在 `flutter test` 里秒级验证，不用起模拟器。
library;

import '../models/document.dart';
import 'cleaner.dart';
import 'segmenter.dart';

/// 新建一篇文章。
///
/// - [raw] 是原始文本（从网页 / PDF 复制来的，或手工敲的）；
/// - [title] 空则用「未命名」（与 Web 版一致，不留空标题）；
/// - 清洗后的规范文本同时写进 `text`（列表排序、去重、指纹都用它）；
/// - 切句后 `paragraphs` / `sentences` 一起给出，id 由 [segment] 定（p01/s001）。
///
/// [now] 只用于测试注入；默认取当前时间。
SavedArticle buildArticle({
  required String raw,
  String title = '',
  String? book,
  ArticleOrigin origin = ArticleOrigin.paste,
  String? id,
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc().toIso8601String();
  final cleaned = cleanText(raw);
  final seg = segment(cleaned);
  return SavedArticle(
    id: id ?? 'saved:${(now ?? DateTime.now()).millisecondsSinceEpoch}',
    title: title.trim().isEmpty ? '未命名' : title.trim(),
    // 书名空串当没有：Web 版也是 `newBook.trim() || undefined`。
    book: (book ?? '').trim().isEmpty ? null : book!.trim(),
    origin: origin,
    text: cleaned,
    paragraphs: seg.paragraphs,
    sentences: seg.sentences,
    createdAt: at,
    updatedAt: at,
  );
}

/// 编辑正文后重新切句，保留已有分析结果。
///
/// 编辑走的是「先洗、再切、再搬分析」三步：不搬的话粘回来的翻译 / 语法 / 语言点
/// 会整批丢掉（[carryAnalysis] 负责按句文搬）。
SavedArticle rebuildArticleText(SavedArticle article, String raw, {DateTime? now}) {
  final cleaned = cleanText(raw);
  final seg = segment(cleaned);
  return article.copyWith(
    text: cleaned,
    paragraphs: seg.paragraphs,
    sentences: carryAnalysis(article.sentences, seg.sentences),
    updatedAt: (now ?? DateTime.now()).toUtc().toIso8601String(),
  );
}
