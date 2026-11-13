/// AI 跑批的任务打包：从词库挑出「还缺释义 / 音标」的词，切成一块块查词任务。
///
/// 这一层只做筛选、分块、拼提示词和生成**稳定 id**，不碰网络、不碰数据库 ——
/// 对应 Web 版 `src/core/aiTodos.ts` + `src/core/aiPackage.ts` 的查词部分。
/// 稳定 id 的意义：同一批词重建后 id 不变，「跑过 / 失败过」的记录才不会随刷新乱跳。
library;

import '../models/vocab.dart' show VocabField, VocabFieldSource, VocabItem, VocabItemKind, VocabLibrary, VocabStatus;
import 'analyzer_prompt.dart' show buildBatchLookupPrompt;
import 'article_vocab.dart' show articleLemmas;
import 'entry_kind.dart' show VocabKind, isWordEntry;

/// 一次查词任务最多带多少个词（Web 版 `LOOKUP_CHUNK`，提示词太长会被截断）。
const int aiLookupChunk = 30;

/// 一条跑批任务。
class AiJob {
  const AiJob({
    required this.id,
    required this.label,
    required this.prompt,
    required this.words,
  });

  /// 稳定 id：`lookup-<内容指纹>`。
  final String id;

  /// 界面上显示的名字（「查词 1/3：run、keep up…」）。
  final String label;

  /// 直接发给模型的提示词。
  final String prompt;

  /// 这一块包含的词（用于「跑完回填」时对照，失败留待办也按它重建）。
  final List<String> words;
}

/// 稳定短哈希（FNV-1a → base36），与 Web `aiPackIO.ts` 逐位一致。
///
/// Dart int 是 64 位，必须每步 `& 0xFFFFFFFF` 截断，否则指纹和网页版对不上。
String aiFingerprint(String text) {
  var h = 2166136261;
  for (var i = 0; i < text.length; i++) {
    h = ((h ^ text.codeUnitAt(i)) * 16777619) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

/// 模型里的 `VocabItemKind` → 判定层的 `VocabKind`（null = 普通单词）。
VocabKind _kindOf(VocabItemKind? kind) => switch (kind) {
      null || VocabItemKind.word => VocabKind.word,
      VocabItemKind.phrase => VocabKind.phrase,
      VocabItemKind.idiom => VocabKind.idiom,
      VocabItemKind.usage => VocabKind.usage,
    };

/// 本次任务要考虑的词条：词组 / 习语 / 用法笔记不参与词级查词。
List<VocabItem> aiTodoBase(VocabLibrary library) => library.items
    .where((it) => isWordEntry(kind: _kindOf(it.kind), word: it.word))
    .toList(growable: false);

/// 某一篇收录的词条（词组 / 习语 / 用法照旧排除，交给 [aiNeedInfo] 之外的同一条口径）。
///
/// 与 [aiTodoBase] 的差别只在「先按篇过滤」：本篇没有收过的词不进跑批。
/// 走 `articleLemmas`（含已掌握 / 语言点）再用 lemma 命中，和侧栏「本篇词表」
/// 用的是同一个事实来源，避免两处口径分叉。
List<VocabItem> aiArticleBase(VocabLibrary library, String articleId) {
  final aid = articleId.trim();
  if (aid.isEmpty) return const <VocabItem>[];
  final lemmas = articleLemmas(library, aid);
  if (lemmas.isEmpty) return const <VocabItem>[];
  return aiTodoBase(library)
      .where((it) => lemmas.contains(it.lemma))
      .toList(growable: false);
}

/// 生词本缺音标 / 释义 → 值得再查一次。
///
/// 与 Web `pickNeedInfo` 逐条对齐：
/// - 手填过的释义不动（`fieldSources.meaning == manual`）；
/// - **没有释义一律排**（不管查没查过，模型漏给的词不能永久停在空卡）；
/// - 已有释义、只差音标时，只补「从没查过」的，免得「模型不给音标」被无限重试。
List<VocabItem> aiNeedInfo(List<VocabItem> base) => base.where((it) {
      if (it.fieldSources?[VocabField.meaning] == VocabFieldSource.manual) {
        return false;
      }
      final meaning = it.meaning ?? '';
      if (meaning.trim().isEmpty) return true;
      return it.status == VocabStatus.unqueried &&
          (it.phonetic ?? '').trim().isEmpty;
    }).toList(growable: false);

/// 把数组切成每块最多 `size` 个（size <= 0 表示不切）。
List<List<T>> aiChunk<T>(List<T> items, int size) {
  if (items.isEmpty) return <List<T>>[];
  if (size <= 0) return <List<T>>[List<T>.of(items)];
  final out = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    out.add(items.sublist(i, i + size > items.length ? items.length : i + size));
  }
  return out;
}

/// 一条词的上下文：取它第一条 `contexts` 的原文，没有就空。
String _contextOf(VocabItem item) {
  final contexts = item.contexts;
  if (contexts == null || contexts.isEmpty) return '';
  for (final c in contexts) {
    if (c.sentenceText.trim().isNotEmpty) return c.sentenceText.trim();
  }
  return '';
}

/// 把词库打包成一批查词任务（纯函数，可离线测）。
///
/// **只跑一篇**：传进来的 [articleId] 就是全局「当前文章」，本篇没收录的词不进待办。
/// 没有「全库」这个范围 —— 全库跑一次就是几百块，额度烧得莫名其妙，用户明确要求
/// 只按篇跑（要补别的篇就去那一篇里点）。
///
/// 返回值可能为空（这一篇没有待查词，或那篇一个词都没收）—— 界面据此显示
/// 「本篇没有待查的词」。
///
/// **跑过的不会重跑**：待办口径是 [aiNeedInfo]，词一旦有释义就不再进来；
/// 落库后重新算自然少一块，不需要另存「已跑过」的账本。
List<AiJob> buildAiLookupJobs(
  VocabLibrary library, {
  int chunkSize = aiLookupChunk,
  String? articleId,
}) {
  final base = aiArticleBase(library, articleId ?? '');
  final chunks = aiChunk(aiNeedInfo(base), chunkSize);
  final jobs = <AiJob>[];
  for (var i = 0; i < chunks.length; i++) {
    final group = chunks[i];
    final words = group.map((it) => it.word.trim()).where((w) => w.isNotEmpty).toList();
    final entries = <({String word, String? context})>[
      for (final it in group)
        (word: it.word.trim(), context: _contextOf(it)),
    ];
    final key = words.join('\n');
    jobs.add(AiJob(
      id: 'lookup-${aiFingerprint(key)}',
      label: '查词 ${i + 1}/${chunks.length}：${words.take(3).join('、')}${words.length > 3 ? '…' : ''}',
      prompt: buildBatchLookupPrompt(entries),
      words: words,
    ));
  }
  return jobs;
}
