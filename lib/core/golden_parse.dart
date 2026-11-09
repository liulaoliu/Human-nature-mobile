/// 金句课的外部输入守卫（对应 Web `src/core/goldenParse.ts`）。
///
/// AI / 备份 / SQLite / IndexedDB 里的整课内容一律先过 [normalizeGoldenLesson]：
/// 句子 id 必须在当前文章里、目标必须逐字出现、坏条目丢弃而不是拖垮整课。
/// 改正文后过 [pruneGoldenLesson] 淘汰对不上的旧内容。
library;

import 'golden.dart';
import 'golden_exam.dart';

export 'golden_exam.dart'
    show
        normalizeGoldenExam,
        parseGoldenExam,
        pruneGoldenExam,
        examToImitation,
        buildGoldenExamFeedbackPrompt,
        isGoldenExamRecord;

String _extraKey(String sentenceId, String en) =>
    '$sentenceId\u0000${en.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase()}';

GoldenExtraPointKind _extraKindOf(Object? v) {
  final s = goldenStr(v);
  for (final k in GoldenExtraPointKind.values) {
    if (k.name == s) return k;
  }
  return GoldenExtraPointKind.chunk;
}

GoldenExtraPointSource _extraSourceOf(Object? v) =>
    goldenStr(v) == 'ai' ? GoldenExtraPointSource.ai : GoldenExtraPointSource.user;

/// 「加入本课」的语言点：句子必须还在；同句同英文去重；最多 50 条。
List<GoldenExtraPoint> normalizeGoldenExtraPoints(
  Object? raw,
  Set<String> sentenceIds,
) {
  if (raw is! List) return const <GoldenExtraPoint>[];
  final seen = <String>{};
  final out = <GoldenExtraPoint>[];
  for (final item in raw) {
    if (!isGoldenObject(item)) continue;
    final m = item as Map;
    final sentenceId = goldenStr(m['sentenceId']);
    final en = goldenStr(m['en']).replaceAll(RegExp(r'\s+'), ' ');
    if (sentenceId.isEmpty || en.isEmpty || !sentenceIds.contains(sentenceId)) {
      continue;
    }
    final key = _extraKey(sentenceId, en);
    if (!seen.add(key)) continue;
    final zh = goldenStr(m['zh']);
    final issueKey = goldenStr(m['issueKey']);
    final at = goldenStr(m['at']);
    out.add(GoldenExtraPoint(
      sentenceId: sentenceId,
      en: en,
      kind: _extraKindOf(m['kind']),
      source: _extraSourceOf(m['source']),
      zh: zh.isEmpty ? null : zh,
      issueKey: issueKey.isEmpty ? null : issueKey,
      at: at.isEmpty ? null : at,
    ));
    if (out.length >= 50) break;
  }
  return out;
}

GoldenSectionRole _sectionRoleOf(Object? v) {
  final s = goldenStr(v);
  for (final r in GoldenSectionRole.values) {
    if (r.name == s) return r;
  }
  return GoldenSectionRole.body;
}

GoldenSource _sourceOf(Object? v) {
  final s = goldenStr(v);
  for (final x in GoldenSource.values) {
    if (x.name == s) return x;
  }
  return GoldenSource.local;
}

Map _optionsOf(Object? raw) =>
    isGoldenObject(raw) ? raw as Map : const <String, Object?>{};

/// 外部输入 → 金句课内容。坏内容丢弃；全坏返回 null（整课作废）。
GoldenLesson? normalizeGoldenLesson(Object? raw, List<GoldenTextMeta> sentences) {
  if (!isGoldenObject(raw)) return null;
  final m = raw as Map;
  final byId = <String, GoldenTextMeta>{
    for (final s in sentences) s.id: s,
  };
  final out = <GoldenSentence>[];
  final rawSentences = m['sentences'] is List ? m['sentences'] as List : const <Object?>[];
  for (final item in rawSentences) {
    if (!isGoldenObject(item)) continue;
    final im = item as Map;
    final id = goldenStr(im['id']);
    final sentence = byId[id];
    if (id.isEmpty || sentence == null) continue;
    final targets = normalizeGoldenTargets(sentence.text, im['targets']);
    final zhRaw = goldenStr(im['zh']);
    final zh = zhRaw.isNotEmpty ? zhRaw : (sentence.translation ?? '');
    final pattern = goldenStr(im['pattern']);
    final tense = goldenStr(im['tense']);
    final note = goldenStr(im['note']);
    if (targets.isEmpty &&
        pattern.isEmpty &&
        tense.isEmpty &&
        note.isEmpty &&
        zh.isEmpty) {
      continue;
    }
    out.add(GoldenSentence(
      id: id,
      zh: zh.isEmpty ? null : zh,
      pattern: pattern.isEmpty ? null : pattern,
      tense: tense.isEmpty ? null : tense,
      note: note.isEmpty ? null : note,
      targets: targets,
    ));
  }
  if (out.isEmpty) return null;

  final outline = <GoldenSection>[];
  final rawOutline = m['outline'] is List ? m['outline'] as List : const <Object?>[];
  for (final item in rawOutline) {
    if (!isGoldenObject(item)) continue;
    final om = item as Map;
    final paraId = goldenStr(om['paraId']);
    if (paraId.isEmpty) continue;
    final title = goldenStr(om['title']);
    outline.add(GoldenSection(
      paraId: paraId,
      role: _sectionRoleOf(om['role']),
      title: title.isEmpty ? null : title,
      points: goldenStrList(om['points']),
    ));
  }

  final validIds = out.map((s) => s.id).toSet();
  final extraPoints = normalizeGoldenExtraPoints(m['extraPoints'], validIds);
  final selected = goldenStrList(m['selected'])
      .where(validIds.contains)
      .toList();
  final aiSelected = goldenStrList(m['aiSelected'])
      .where(validIds.contains)
      .toList();

  final opts = _optionsOf(m['options']);
  final pickRaw = goldenStr(opts['pick']);
  GoldenPickMode? pick;
  for (final p in GoldenPickMode.values) {
    if (p.name == pickRaw) pick = p;
  }
  final blankRaw = goldenStr(opts['blankUnit']);
  GoldenBlankUnit? blankUnit;
  for (final b in GoldenBlankUnit.values) {
    if (b.name == blankRaw) blankUnit = b;
  }
  final fillRaw = opts['sentenceFill'];
  final bool? sentenceFill =
      fillRaw == false ? false : (fillRaw == true ? true : null);
  final int? examAfter = opts['examAfter'] == 10 ? 10 : null;

  final exam = normalizeGoldenExam(m['exam'], sentences);
  final summary = goldenStr(m['summary']);
  final updatedAt = goldenStr(m['updatedAt']);

  return GoldenLesson(
    source: _sourceOf(m['source']),
    summary: summary.isEmpty ? null : summary,
    outline: outline,
    sentences: out,
    selected: selected.isNotEmpty ? selected : out.map((s) => s.id).toList(),
    aiSelected: aiSelected.isEmpty ? null : aiSelected,
    exam: exam.isEmpty ? null : exam,
    extraPoints: extraPoints.isEmpty ? null : extraPoints,
    options: GoldenLessonOptions(
      dedupe: opts['dedupe'] == true,
      pick: pick,
      blankUnit: blankUnit,
      sentenceFill: sentenceFill,
      examAfter: examAfter,
    ),
    updatedAt: updatedAt.isEmpty ? null : updatedAt,
  );
}

/// 导入/合并文章时保住金句课：旧备份没 golden 就保留现有的；
/// 两边都有时按文章 updatedAt 取较新；「加入本课」的结果两边取并集。
GoldenLesson? mergeGoldenIntoArticle({
  required GoldenLesson? existing,
  required GoldenLesson? incoming,
  required String existingUpdatedAt,
  required String incomingUpdatedAt,
}) {
  final base = incoming != null &&
          (existing == null || incomingUpdatedAt.compareTo(existingUpdatedAt) >= 0)
      ? incoming
      : (existing ?? incoming);
  if (base == null) return null;
  final validIds = base.sentences.map((s) => s.id).toSet();
  final seen = <String>{};
  final extraPoints = <GoldenExtraPoint>[];
  for (final p in <GoldenExtraPoint>[
    ...(existing?.extraPoints ?? const <GoldenExtraPoint>[]),
    ...(incoming?.extraPoints ?? const <GoldenExtraPoint>[]),
  ]) {
    if (!validIds.contains(p.sentenceId)) continue;
    final key = _extraKey(p.sentenceId, p.en);
    if (!seen.add(key)) continue;
    extraPoints.add(p);
  }
  return base.copyWith(
    extraPoints: () => extraPoints.isEmpty ? null : extraPoints,
  );
}

/// 改正文后丢掉已经不存在 / 内容对不上的句子；没有可练目标就整课作废。
GoldenLesson? pruneGoldenLesson(
  GoldenLesson? lesson,
  List<GoldenTextMeta> sentences,
) {
  if (lesson == null) return null;
  final next = normalizeGoldenLesson(lesson.toJson(), sentences);
  if (next == null) return null;
  final kept = next.sentences.where((s) => s.targets.isNotEmpty).toList();
  if (kept.isEmpty) return null;
  final ids = kept.map((s) => s.id).toSet();
  final exam = pruneGoldenExam(next.exam, sentences);
  final extraPoints = next.extraPoints
      ?.where((p) => ids.contains(p.sentenceId))
      .toList();
  return next.copyWith(
    sentences: kept,
    selected: next.selected.where(ids.contains).toList(),
    extraPoints: () => (extraPoints == null || extraPoints.isEmpty) ? null : extraPoints,
    exam: () => exam,
  );
}
