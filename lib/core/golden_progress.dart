/// 「D老师小课堂」金句课的**学习进度**（对应 Web `src/core/goldenProgress.ts`）。
///
/// 一份进度 = 某一句 + 它的内容指纹（[GoldenDrillRecord.drillKey]）。改了正文或
/// 目标，指纹就变，旧进度自然失配，不会把「已掌握」错挂到另一句上。
/// 纯 Dart：不碰 Flutter / 存储 / 时间源，`todayKey` 由调用方给。
library;

import '../models/document.dart' show Paragraph;
import 'activity/activity.dart' show dayKeyLocal;
import 'golden.dart';

/// 一句要记的四步；`summary` 只记「看过」，不参与首次对错。
enum GoldenStep { fill, assemble, recall, summary }

/// 每句的学习进度；按 [id] 去重，存 `LearningData.goldenDrills`。
class GoldenDrillRecord {
  const GoldenDrillRecord({
    required this.id,
    required this.articleId,
    this.articleTitle,
    required this.sentenceId,
    required this.drillKey,
    required this.at,
    this.fillFirst,
    this.assembleFirst,
    this.recallFirst,
    this.fillTries = 0,
    this.assembleTries = 0,
    this.recallTries = 0,
    this.summarySeen,
    this.mastered = false,
    this.completedAt,
  });

  /// `${articleId}|${sentenceId}|${drillKey}`。
  final String id;
  final String articleId;
  final String? articleTitle;
  final String sentenceId;

  /// 句子文本 + 目标的内容指纹。
  final String drillKey;

  /// 最近一次练习时间（ISO 串）。
  final String at;

  /// 首次作答是否答对；首次答错后重试**不会**改回 true。
  final bool? fillFirst;
  final bool? assembleFirst;
  final bool? recallFirst;

  final int fillTries;
  final int assembleTries;
  final int recallTries;
  final bool? summarySeen;

  /// 终身标记：一旦掌握，之后重练也不降级。
  final bool mastered;
  final String? completedAt;

  GoldenDrillRecord copyWith({
    String? id,
    String? articleId,
    String? Function()? articleTitle,
    String? sentenceId,
    String? drillKey,
    String? at,
    bool? Function()? fillFirst,
    bool? Function()? assembleFirst,
    bool? Function()? recallFirst,
    int? fillTries,
    int? assembleTries,
    int? recallTries,
    bool? Function()? summarySeen,
    bool? mastered,
    String? Function()? completedAt,
  }) =>
      GoldenDrillRecord(
        id: id ?? this.id,
        articleId: articleId ?? this.articleId,
        articleTitle: articleTitle != null ? articleTitle() : this.articleTitle,
        sentenceId: sentenceId ?? this.sentenceId,
        drillKey: drillKey ?? this.drillKey,
        at: at ?? this.at,
        fillFirst: fillFirst != null ? fillFirst() : this.fillFirst,
        assembleFirst:
            assembleFirst != null ? assembleFirst() : this.assembleFirst,
        recallFirst: recallFirst != null ? recallFirst() : this.recallFirst,
        fillTries: fillTries ?? this.fillTries,
        assembleTries: assembleTries ?? this.assembleTries,
        recallTries: recallTries ?? this.recallTries,
        summarySeen: summarySeen != null ? summarySeen() : this.summarySeen,
        mastered: mastered ?? this.mastered,
        completedAt: completedAt != null ? completedAt() : this.completedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'articleId': articleId,
        if (articleTitle != null) 'articleTitle': articleTitle,
        'sentenceId': sentenceId,
        'drillKey': drillKey,
        'at': at,
        if (fillFirst == true) 'fillFirst': true,
        if (assembleFirst == true) 'assembleFirst': true,
        if (recallFirst == true) 'recallFirst': true,
        'fillTries': fillTries,
        'assembleTries': assembleTries,
        'recallTries': recallTries,
        if (summarySeen == true) 'summarySeen': true,
        'mastered': mastered,
        if (completedAt != null) 'completedAt': completedAt,
      };
}

GoldenDrillRecord emptyGoldenRecord(
  String articleId,
  String? articleTitle,
  String sentenceId,
  String drillKey,
  String at,
) =>
    GoldenDrillRecord(
      id: goldenRecordId(articleId, sentenceId, drillKey),
      articleId: articleId,
      articleTitle: articleTitle,
      sentenceId: sentenceId,
      drillKey: drillKey,
      at: at,
      mastered: false,
    );

/// 掌握口径：三步**首次**全对 + 看过小结。重试全对也不算掌握。
bool goldenMastered(GoldenDrillRecord r) =>
    r.fillFirst == true &&
    r.assembleFirst == true &&
    r.recallFirst == true &&
    r.summarySeen == true;

/// 完成口径：三步都练过 + 看过小结（不要求首次全对）。
bool goldenCompleted(GoldenDrillRecord r) =>
    r.fillTries > 0 &&
    r.assembleTries > 0 &&
    r.recallTries > 0 &&
    r.summarySeen == true;

/// 「再练一次」：清空本轮首次记录，给用户重新拿掌握的机会。
/// 已掌握 / 完成时间不降级；这是重练唯一的口径。
GoldenDrillRecord resetGoldenRecord(GoldenDrillRecord record, String at) =>
    GoldenDrillRecord(
      id: record.id,
      articleId: record.articleId,
      articleTitle: record.articleTitle,
      sentenceId: record.sentenceId,
      drillKey: record.drillKey,
      at: at,
      fillTries: 0,
      assembleTries: 0,
      recallTries: 0,
      summarySeen: false,
      mastered: record.mastered,
      completedAt: record.completedAt,
    );

/// 记一步。纯函数，调用方只负责把它写进唯一的 goldenDrills。
GoldenDrillRecord recordGoldenStep(
  GoldenDrillRecord record,
  GoldenStep step,
  bool correct,
  String at,
) {
  var fillTries = record.fillTries;
  var assembleTries = record.assembleTries;
  var recallTries = record.recallTries;
  bool? fillFirst = record.fillFirst;
  bool? assembleFirst = record.assembleFirst;
  bool? recallFirst = record.recallFirst;
  bool? summarySeen = record.summarySeen;

  if (step == GoldenStep.summary) {
    summarySeen = true;
  } else {
    switch (step) {
      case GoldenStep.fill:
        fillTries = record.fillTries + 1;
        if (fillTries == 1) fillFirst = correct;
        break;
      case GoldenStep.assemble:
        assembleTries = record.assembleTries + 1;
        if (assembleTries == 1) assembleFirst = correct;
        break;
      case GoldenStep.recall:
        recallTries = record.recallTries + 1;
        if (recallTries == 1) recallFirst = correct;
        break;
      case GoldenStep.summary:
        break;
    }
  }

  final mastered = record.mastered ||
      (fillFirst == true &&
          assembleFirst == true &&
          recallFirst == true &&
          summarySeen == true);
  return GoldenDrillRecord(
    id: record.id,
    articleId: record.articleId,
    articleTitle: record.articleTitle,
    sentenceId: record.sentenceId,
    drillKey: record.drillKey,
    at: at,
    fillFirst: fillFirst,
    assembleFirst: assembleFirst,
    recallFirst: recallFirst,
    fillTries: fillTries,
    assembleTries: assembleTries,
    recallTries: recallTries,
    summarySeen: summarySeen,
    mastered: mastered,
    completedAt: mastered && record.completedAt == null
        ? at
        : record.completedAt,
  );
}

GoldenDrillRecord? findGoldenRecord(
  List<GoldenDrillRecord> records,
  String articleId,
  String sentenceId,
  String drillKey,
) {
  final id = goldenRecordId(articleId, sentenceId, drillKey);
  for (final r in records) {
    if (r.id == id) return r;
  }
  return null;
}

/// 待回顾口径：已掌握 + 今天还没回顾。
///
/// 日期键由调用方传 `dayKeyLocal()`，不要在视图里再写第二套比较。
bool goldenReviewDue(GoldenDrillRecord? record, String todayKey) {
  if (record == null || !record.mastered || record.at.isEmpty) return false;
  final at = DateTime.tryParse(record.at);
  if (at == null) return false;
  return dayKeyLocal(at.toLocal()) != todayKey;
}

/// 待回顾队列：只保留当前课里、已掌握且今天没回顾的句子，按课文顺序。
List<String> goldenReviewSentenceIds(
  List<GoldenDrillRecord> records,
  String articleId,
  List<String> sentenceIds,
  String todayKey,
) {
  final due = <String>{
    for (final r in records)
      if (r.articleId == articleId && goldenReviewDue(r, todayKey))
        r.sentenceId,
  };
  return sentenceIds.where(due.contains).toList(growable: false);
}

int _numberOrZero(Object? v) {
  final num? n = v is num ? v : (v is String ? num.tryParse(v) : null);
  return n != null && n.isFinite && n > 0 ? n.floor() : 0;
}

/// 外部输入（localStorage / 备份 / SQLite）→ 好记录；坏条目直接丢。
List<GoldenDrillRecord> normalizeGoldenDrills(Object? raw) {
  if (raw is! List) return const <GoldenDrillRecord>[];
  final byId = <String, GoldenDrillRecord>{};
  for (final item in raw) {
    if (!isGoldenObject(item)) continue;
    final m = item as Map;
    final articleId = goldenStr(m['articleId']);
    final sentenceId = goldenStr(m['sentenceId']);
    final drillKey = goldenStr(m['drillKey']);
    final at = goldenStr(m['at']);
    if (articleId.isEmpty ||
        sentenceId.isEmpty ||
        drillKey.isEmpty ||
        at.isEmpty ||
        DateTime.tryParse(at) == null) {
      continue;
    }
    final id = goldenStr(m['id']).isEmpty
        ? goldenRecordId(articleId, sentenceId, drillKey)
        : goldenStr(m['id']);
    final title = goldenStr(m['articleTitle']);
    final completedAt = goldenStr(m['completedAt']);
    final rec = GoldenDrillRecord(
      id: id,
      articleId: articleId,
      articleTitle: title.isEmpty ? null : title,
      sentenceId: sentenceId,
      drillKey: drillKey,
      at: at,
      fillTries: _numberOrZero(m['fillTries']),
      assembleTries: _numberOrZero(m['assembleTries']),
      recallTries: _numberOrZero(m['recallTries']),
      fillFirst: m['fillFirst'] == true ? true : null,
      assembleFirst: m['assembleFirst'] == true ? true : null,
      recallFirst: m['recallFirst'] == true ? true : null,
      summarySeen: m['summarySeen'] == true ? true : null,
      mastered: m['mastered'] == true,
      completedAt: completedAt.isEmpty ? null : completedAt,
    );
    //  mastered 以实际步骤为准，不信存档里那个可能被写坏的布尔。
    byId[id] = rec.copyWith(mastered: goldenMastered(rec));
  }
  final out = byId.values.toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  return List<GoldenDrillRecord>.unmodifiable(out);
}

/// 合并两份进度：同 id 保留更晚的一条；同一时刻合并首次对错。
List<GoldenDrillRecord> mergeGoldenDrills(
  List<GoldenDrillRecord> current,
  List<GoldenDrillRecord> incoming,
) {
  final byId = <String, GoldenDrillRecord>{
    for (final r in current) r.id: r,
  };
  for (final rec in incoming) {
    final prev = byId[rec.id];
    if (prev == null) {
      byId[rec.id] = rec;
      continue;
    }
    final base = rec.at.compareTo(prev.at) >= 0 ? rec : prev;
    final merged = GoldenDrillRecord(
      id: base.id,
      articleId: base.articleId,
      articleTitle: base.articleTitle,
      sentenceId: base.sentenceId,
      drillKey: base.drillKey,
      at: base.at,
      fillTries: prev.fillTries > rec.fillTries ? prev.fillTries : rec.fillTries,
      assembleTries: prev.assembleTries > rec.assembleTries
          ? prev.assembleTries
          : rec.assembleTries,
      recallTries:
          prev.recallTries > rec.recallTries ? prev.recallTries : rec.recallTries,
      fillFirst: (prev.fillFirst == true || rec.fillFirst == true) ? true : null,
      assembleFirst:
          (prev.assembleFirst == true || rec.assembleFirst == true) ? true : null,
      recallFirst:
          (prev.recallFirst == true || rec.recallFirst == true) ? true : null,
      summarySeen:
          (prev.summarySeen == true || rec.summarySeen == true) ? true : null,
      completedAt: base.completedAt,
    );
    final mastered = goldenMastered(merged);
    final completedAt = mastered
        ? (prev.completedAt ?? rec.completedAt ?? merged.at)
        : merged.completedAt;
    byId[rec.id] =
        merged.copyWith(mastered: mastered, completedAt: () => completedAt);
  }
  final out = byId.values.toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  return List<GoldenDrillRecord>.unmodifiable(out);
}

/// 按目标类型统计掌握情况。
class GoldenKindCount {
  const GoldenKindCount({
    required this.kind,
    required this.total,
    required this.mastered,
  });

  final GoldenTargetKind kind;
  final int total;
  final int mastered;
}

/// 按文章脉络段落统计掌握情况。
class GoldenSectionCount {
  const GoldenSectionCount({
    required this.paraId,
    required this.role,
    required this.total,
    required this.mastered,
  });

  final String paraId;
  final GoldenSectionRole role;
  final int total;
  final int mastered;
}

/// 学习句子 / 学习点 / 掌握的展示口径。
class GoldenMasterySummary {
  const GoldenMasterySummary({
    required this.selectedSentences,
    required this.masteredSentences,
    required this.totalTargets,
    required this.masteredTargets,
    required this.byKind,
    required this.bySection,
  });

  final int selectedSentences;
  final int masteredSentences;
  final int totalTargets;
  final int masteredTargets;
  final List<GoldenKindCount> byKind;
  final List<GoldenSectionCount> bySection;
}

/// 默认按句独立（同一目标在多句各算一次）；`options.dedupe` 打开才跨句去重。
GoldenMasterySummary summarizeGolden(
  GoldenLesson lesson,
  List<GoldenTextMeta> sentences,
  List<GoldenDrillRecord> records,
  String articleId, [
  List<Paragraph>? paragraphs,
]) {
  final textOf = <String, String>{
    for (final s in sentences) s.id: s.text,
  };
  final paraOf = <String, String>{};
  for (final p in paragraphs ?? const <Paragraph>[]) {
    for (final id in p.sentenceIds) {
      paraOf[id] = p.id;
    }
  }
  final dedupe = lesson.options.dedupe;
  final selected = lesson.selected.isNotEmpty
      ? lesson.selected
      : lesson.sentences.map((s) => s.id).toList();
  final content = <String, GoldenSentence>{
    for (final s in lesson.sentences) s.id: s,
  };
  final progress = <String, GoldenDrillRecord>{
    for (final r in records)
      if (r.articleId == articleId) '${r.sentenceId}|${r.drillKey}': r,
  };
  final seen = <String>{};
  final byKind = <GoldenTargetKind, GoldenKindCount>{};
  final bySection = <String, GoldenSectionCount>{};
  var totalTargets = 0;
  var masteredTargets = 0;
  var masteredSentences = 0;
  var selectedSentences = 0;

  for (final id in selected) {
    final s = content[id];
    if (s == null) continue;
    final text = textOf[s.id] ?? '';
    final rec = progress['${s.id}|${goldenDrillKey(text, s.targets)}'];
    final mastered = rec?.mastered == true;
    selectedSentences += 1;
    if (mastered) masteredSentences += 1;
    var total = 0;
    for (final t in s.targets) {
      final key = goldenTargetKey(t);
      if (dedupe && !seen.add(key)) continue;
      seen.add(key);
      total += 1;
      final cur = byKind[t.kind];
      byKind[t.kind] = GoldenKindCount(
        kind: t.kind,
        total: (cur?.total ?? 0) + 1,
        mastered: (cur?.mastered ?? 0) + (mastered ? 1 : 0),
      );
    }
    totalTargets += total;
    if (mastered) masteredTargets += total;
    final paraId = paraOf[s.id];
    GoldenSection? sec;
    if (paraId != null) {
      for (final x in lesson.outline) {
        if (x.paraId == paraId) {
          sec = x;
          break;
        }
      }
    }
    if (sec != null) {
      final cur = bySection[sec.paraId];
      bySection[sec.paraId] = GoldenSectionCount(
        paraId: sec.paraId,
        role: sec.role,
        total: (cur?.total ?? 0) + total,
        mastered: (cur?.mastered ?? 0) + (mastered ? total : 0),
      );
    }
  }
  return GoldenMasterySummary(
    selectedSentences: selectedSentences,
    masteredSentences: masteredSentences,
    totalTargets: totalTargets,
    masteredTargets: masteredTargets,
    byKind: byKind.values.toList(growable: false),
    bySection: bySection.values.toList(growable: false),
  );
}
