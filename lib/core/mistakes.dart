/// 统一「错题本」：把考试错词、听力错题、听写漏词都收进来，随时重练。
///
/// 纯函数、零 IO。同一实体（同词 / 同题 / 同段）只留一条，重复错则累加 count、
/// 刷新时间。对应 Web 版 `src/core/mistakes.ts`（80 行）。
library;

import '../models/listening.dart';

/// 错题类型。
enum MistakeKind { vocab, listen, dict }

const List<MistakeKind> mistakeKinds = [MistakeKind.vocab, MistakeKind.listen, MistakeKind.dict];

const Map<MistakeKind, String> mistakeLabel = {
  MistakeKind.vocab: '考试错词',
  MistakeKind.listen: '听力错题',
  MistakeKind.dict: '听写漏词',
};

MistakeKind? parseMistakeKind(Object? raw) {
  for (final k in mistakeKinds) {
    if (k.name == raw) return k;
  }
  return null;
}

class MistakeEntry {
  const MistakeEntry({
    required this.id,
    required this.kind,
    required this.at,
    required this.count,
    required this.label,
    this.itemId,
    this.question,
    this.articleId,
    this.text,
  });

  /// 唯一键（`kind:实体`）。
  final String id;
  final MistakeKind kind;

  /// 最近一次错的时间（ISO）。
  final String at;

  /// 累计错次。
  final int count;

  /// 显示用标签。
  final String label;

  /// 考试错词：词条 id。
  final String? itemId;

  /// 听力错题：题目（含答案/解析）。
  final ListeningQuestion? question;

  /// 听力错题：来源文章。
  final String? articleId;

  /// 听写漏词：原文片段。
  final String? text;

  MistakeEntry copyWith({String? at, int? count}) => MistakeEntry(
        id: id,
        kind: kind,
        at: at ?? this.at,
        count: count ?? this.count,
        label: label,
        itemId: itemId,
        question: question,
        articleId: articleId,
        text: text,
      );

  @override
  String toString() => 'MistakeEntry($id, x$count)';
}

/// 归一化文本：trim + 小写 + 压空白（做 id 用）。
String normMistakeText(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

MistakeEntry vocabMistake(String itemId, String label, String at) => MistakeEntry(
      id: 'vocab:$itemId',
      kind: MistakeKind.vocab,
      at: at,
      count: 1,
      label: label,
      itemId: itemId,
    );

/// id 用「题号 + 题干」，不带文章：错题本重练时文章可能不同，也能对上。
MistakeEntry listenMistake(String articleId, ListeningQuestion q, String at) => MistakeEntry(
      id: 'listen:${q.id}:${normMistakeText(q.stem)}',
      kind: MistakeKind.listen,
      at: at,
      count: 1,
      label: q.stem,
      question: q,
      articleId: articleId,
    );

MistakeEntry dictMistake(String text, String at) => MistakeEntry(
      id: 'dict:${normMistakeText(text)}',
      kind: MistakeKind.dict,
      at: at,
      count: 1,
      label: text,
      text: text,
    );

/// 加入 / 累加一条错题（同 id 合并，新的在前，按上限截断）。纯函数。
List<MistakeEntry> upsertMistake(List<MistakeEntry> list, MistakeEntry entry, {int cap = 300}) {
  final i = list.indexWhere((m) => m.id == entry.id);
  if (i < 0) {
    final next = [entry, ...list];
    final keep = cap < 0 ? 0 : cap;
    return next.length <= keep ? next : next.sublist(0, keep);
  }
  final next = [...list];
  next[i] = entry.copyWith(count: list[i].count + 1);
  return next;
}

/// 移除一条（答对后清掉）。
List<MistakeEntry> removeMistake(List<MistakeEntry> list, String id) =>
    [for (final m in list) if (m.id != id) m];

/// 各类数量（三种类型都出现）。
Map<MistakeKind, int> mistakeCounts(List<MistakeEntry> list) {
  final out = {for (final k in mistakeKinds) k: 0};
  for (final m in list) {
    out[m.kind] = out[m.kind]! + 1;
  }
  return out;
}
