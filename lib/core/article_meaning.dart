/// 「这个词在这一篇 / 这一句里是什么意思」的解析顺序（纯函数）。
///
/// 对应 Web 版 `src/core/articleMeaning.ts`。目标：悬浮释义优先用本篇语境，
/// 不拿别的文章的主释义硬套。顺序固定为：
///
///   1. 本篇条目上手改 / 收录时带的释义（最高，不被 AI 覆盖）
///   2. 同一句的语境释义（`contexts[].meaning`，AI 按上下文给的）
///   3. 同一篇其他句子的语境释义
///   4. 全库主释义（最后兜底）
///
/// 不在这里调词典 / AI：那些是显式动作，结果写回 `contexts` / 条目后再走这里。
library;

import '../models/vocab.dart';

/// 一次解析结果：释义文本 + 它是从哪一层来的。
class ResolvedMeaning {
  const ResolvedMeaning({required this.text, required this.source});

  final String text;
  final VocabMeaningSource source;

  @override
  bool operator ==(Object other) =>
      other is ResolvedMeaning && other.text == text && other.source == source;

  @override
  int get hashCode => Object.hash(text, source);

  @override
  String toString() => 'ResolvedMeaning($text, ${source.name})';
}

/// 释义来源的显示文案（本篇条目 / 悬浮解释共用）。
const Map<VocabMeaningSource, String> meaningSourceLabelMap =
    <VocabMeaningSource, String>{
  VocabMeaningSource.manual: '手动',
  VocabMeaningSource.context: '语境',
  VocabMeaningSource.library: '词库',
  VocabMeaningSource.dict: '词典',
  VocabMeaningSource.ai: 'AI',
};

/// 释义来源的中文名；没有来源返回 null（旧数据不硬猜成「手动」）。
String? meaningSourceLabel(VocabMeaningSource? source) =>
    source == null ? null : meaningSourceLabelMap[source];

bool _contextMatches(VocabContext c, String articleId) =>
    c.fileName == articleId || c.articleId == articleId;

/// 同一篇（优先同一句）的语境释义；找不到返回 null。
VocabContext? _contextMeaning(
  List<VocabContext>? list,
  String articleId,
  String? sentenceId,
) {
  if (list == null || list.isEmpty || articleId.isEmpty) return null;
  // 倒序：后写的覆盖先写的（AI 重跑一次就更新）。
  for (var i = list.length - 1; i >= 0; i--) {
    final c = list[i];
    if ((c.meaning ?? '').trim().isEmpty) continue;
    if (!_contextMatches(c, articleId)) continue;
    if (sentenceId != null && sentenceId.isNotEmpty && c.sentenceId == sentenceId) {
      return c;
    }
  }
  for (var i = list.length - 1; i >= 0; i--) {
    final c = list[i];
    if ((c.meaning ?? '').trim().isNotEmpty && _contextMatches(c, articleId)) {
      return c;
    }
  }
  return null;
}

/// 按固定顺序解析「本篇 / 本句」的释义；一层都取不到返回 null。
ResolvedMeaning? resolveArticleMeaning(
  VocabItem item,
  ArticleVocabEntry? entry,
  String articleId, {
  String? sentenceId,
}) {
  final own = (entry?.meaning ?? '').trim();
  if (own.isNotEmpty) {
    return ResolvedMeaning(
      text: own,
      source: entry?.meaningSource ?? VocabMeaningSource.manual,
    );
  }

  final ctx = _contextMeaning(item.contexts, articleId, sentenceId);
  final ctxText = (ctx?.meaning ?? '').trim();
  if (ctxText.isNotEmpty) {
    return ResolvedMeaning(text: ctxText, source: VocabMeaningSource.context);
  }

  final main = (item.meaning ?? '').trim();
  if (main.isNotEmpty) {
    return ResolvedMeaning(text: main, source: VocabMeaningSource.library);
  }
  return null;
}
