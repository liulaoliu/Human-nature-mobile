/// 「D老师小课堂」金句课：纯逻辑层（对应 Web `src/core/golden.ts`）。
///
/// 一条学习链：预览整句 → 句子填空 → 拼接整句 → 本句小结 → 逆向回顾。
/// 这里只做「算」：选金句、抽目标、挖空、拼句银行、判分、回忆 diff、掌握统计；
/// Flutter / 存储 / TTS 一律不碰（分层门禁 R1）。
library;

import '../models/document.dart';
import 'golden_types.dart';
import 'lang_points.dart';
import 'language.dart';
import 'quiz_parts.dart';
import 'word_select.dart';

export 'golden_types.dart';

/// 默认 / 最多选几句金句。
const int goldenDefaultLimit = 10;
const int goldenMaxLimit = 20;

/// 逆向默写「接近」的阈值；低于它只能算完成，不能算掌握。
const double goldenRecallNear = 0.9;

/// 一句最多 / 最少练多少个目标；上限防 AI/坏数据无限塞，下限照顾短句。
const int goldenTargetMin = 6;
const int goldenTargetLimit = 20;

/// 目标类型中文名。
const Map<GoldenTargetKind, String> goldenTargetKindLabel = <GoldenTargetKind, String>{
  GoldenTargetKind.pattern: '句型',
  GoldenTargetKind.tense: '时态',
  GoldenTargetKind.collocation: '搭配',
  GoldenTargetKind.idiom: '习语',
  GoldenTargetKind.usage: '用法',
  GoldenTargetKind.word: '单词',
};

bool isGoldenObject(Object? v) => v is Map && v is! List;

String goldenStr(Object? v) => v is String ? v.trim() : '';

List<String> goldenStrList(Object? v) => v is List
    ? v.map(goldenStr).where((s) => s.isNotEmpty).toList(growable: false)
    : const <String>[];

/// 按句长给目标上限：短句少、长句多，最多 [goldenTargetLimit]。
int goldenTargetLimitFor(String text) {
  final words = wordSpans(text).length;
  return words < goldenTargetMin
      ? goldenTargetMin
      : (words > goldenTargetLimit ? goldenTargetLimit : words);
}

/// djb2：短、稳定、不用引第三方；只用于内容指纹，不用于安全。
/// 与 Web 完全一致：`h = ((h << 5) + h + code) | 0`、`>>> 0` 再取 36 进制。
String _hashText(String s) {
  var h = 5381;
  for (final unit in s.codeUnits) {
    h = ((h << 5) + h + unit) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

String goldenTargetKey(GoldenTarget t) =>
    '${t.kind.name}|${normalizeAnswer(t.en)}';

/// 句子 + 目标的内容指纹：改正文或改目标后，旧进度不会误用。
String goldenDrillKey(String text, List<GoldenTarget> targets) {
  final keys = targets
      .map((t) => '${t.kind.name}:${normalizeAnswer(t.en)}')
      .join('\u0001');
  return _hashText('${text.trim()}\u0002$keys');
}

String goldenRecordId(String articleId, String sentenceId, String drillKey) =>
    '$articleId|$sentenceId|$drillKey';

String _escapeRegExp(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m.group(0)}');

/// 找目标在原文里的所有出现位置。
///
/// 只容忍大小写、撇号/连字符变体与空白差异；不允许把词的一部分当目标
/// （`norm` 不能命中 `normal`）。找不到就返回空数组，调用方丢弃该目标。
List<GoldenTargetSpan> findGoldenTargetSpans(String text, String en) {
  final raw = en.trim();
  if (raw.isEmpty || text.isEmpty) return const <GoldenTargetSpan>[];
  final body = raw
      .split(RegExp(r'\s+'))
      .map((part) => _escapeRegExp(part)
          .replaceAll(RegExp("['’]"), "['’]")
          .replaceAll(RegExp(r'[-–—]'), '[-–—]'))
      .join(r'\s+');
  final RegExp re;
  try {
    re = RegExp(
      r'(?<![\p{L}\p{N}])' + body + r'(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
  } catch (_) {
    return const <GoldenTargetSpan>[];
  }
  final out = <GoldenTargetSpan>[];
  for (final m in re.allMatches(text)) {
    final hit = m.group(0);
    if (hit != null && hit.isNotEmpty) {
      out.add(GoldenTargetSpan(start: m.start, end: m.end, text: hit));
    }
  }
  return out;
}

GoldenTargetKind _normalizeKind(Object? v) {
  if (v is! String) return GoldenTargetKind.word;
  for (final k in GoldenTargetKind.values) {
    if (k.name == v) return k;
  }
  return GoldenTargetKind.word;
}

class _SpanTarget {
  const _SpanTarget(this.target, this.span);
  final GoldenTarget target;
  final GoldenTargetSpan span;
}

/// 目标清洗：必须在原句里逐字出现；去重；重叠时长的优先；最多按句长上限。
/// AI 返回的编造片段、备份里的坏数据都在这里被丢掉。
List<GoldenTarget> normalizeGoldenTargets(String text, Object? raw) {
  if (raw is! List) return const <GoldenTarget>[];
  final kept = <_SpanTarget>[];
  final seen = <String>{};
  for (final item in raw) {
    if (!isGoldenObject(item)) continue;
    final m = item as Map;
    final en = goldenStr(m['en']);
    if (en.isEmpty) continue;
    final kind = _normalizeKind(m['kind']);
    final key = '${kind.name}|${normalizeAnswer(en)}';
    if (!seen.add(key)) continue;
    final spans = findGoldenTargetSpans(text, en);
    if (spans.isEmpty) continue;
    final zh = goldenStr(m['zh']);
    kept.add(_SpanTarget(
      GoldenTarget(en: en, kind: kind, zh: zh.isEmpty ? null : zh),
      spans.first,
    ));
  }
  // 先按长度挑重叠项（长语言点优先于被它包住的短词/时态），再按原句顺序输出。
  kept.sort((a, b) {
    final lenCmp = (b.span.end - b.span.start) - (a.span.end - a.span.start);
    return lenCmp != 0 ? lenCmp : a.span.start - b.span.start;
  });
  final out = <_SpanTarget>[];
  for (final row in kept) {
    final overlaps = out.any((x) =>
        row.span.start < x.span.end && row.span.end > x.span.start);
    if (overlaps) continue;
    out.add(row);
  }
  out.sort((a, b) => a.span.start - b.span.start);
  final limit = goldenTargetLimitFor(text);
  return out.take(limit).map((x) => x.target).toList(growable: false);
}

const Set<String> _tenseAux = <String>{
  'has', 'have', 'had', 'is', 'are', 'was', 'were', 'am',
};
const Set<String> _modal = <String>{
  'will', 'would', 'can', 'could', 'may', 'might', 'must', 'should',
};
const Set<String> _stop = <String>{
  'the', 'a', 'an', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'for',
  'with', 'by', 'from', 'as', 'is', 'are', 'was', 'were', 'be', 'been',
  'being', 'it', 'its', 'this', 'that', 'these', 'those', 'i', 'you', 'he',
  'she', 'we', 'they', 'his', 'her', 'their', 'our', 'your', 'my', 'me',
  'him', 'them', 'us', 'not', 'no', 'so', 'if', 'than', 'then', 'when',
  'while', 'into', 'over', 'under', 'also', 'more', 'most', 'much', 'many',
  'very', 'can', 'could', 'will', 'would', 'should', 'may', 'might', 'must',
  'do', 'does', 'did', 'has', 'have', 'had', 'there', 'here', 'what', 'which',
  'who', 'whom', 'how', 'why', 'all', 'any', 'some', 'such', 'only', 'just',
};

/// 本地兜底：语言点词组/习语 → 保守时态块 → 生词 → 较长的实词。
List<GoldenTarget> buildLocalTargets(
  Sentence sentence, [
  Map<String, String>? meanings,
]) {
  final text = sentence.text;
  final raw = <Map<String, Object?>>[];
  for (final l in getSentenceLanguages(sentence)) {
    for (final p in l.phrases ?? const <String>[]) {
      final (:word, :gloss) = splitGlossText(p);
      if (word.isNotEmpty) {
        raw.add(<String, Object?>{
          'en': word,
          'zh': ?gloss,
          'kind': 'collocation',
        });
      }
    }
    for (final i in l.idioms ?? const <String>[]) {
      final (:word, :gloss) = splitGlossText(i);
      if (word.isNotEmpty) {
        raw.add(<String, Object?>{
          'en': word,
          'zh': ?gloss,
          'kind': 'idiom',
        });
      }
    }
  }
  for (final c in sentence.collocations) {
    raw.add(<String, Object?>{'en': c, 'kind': 'collocation'});
  }
  // 保守时态：have/has/had + 实词；be + -ing/-ed。宁可少抽，也别把 is one 当「时态」。
  final spans = wordSpans(text);
  for (var i = 0; i < spans.length - 1; i++) {
    final w = spans[i].text.replaceAll(RegExp("[^A-Za-z']"), '');
    final next = spans[i + 1].text.replaceAll(RegExp("[^A-Za-z']"), '');
    if (w.isEmpty || next.isEmpty) continue;
    final low = w.toLowerCase();
    final nextLow = next.toLowerCase();
    final usefulNext = next.length >= 3 && !_stop.contains(nextLow);
    final hasPattern = _tenseAux.contains(low) &&
        usefulNext &&
        (low.startsWith('ha') || RegExp(r'(ing|ed)$').hasMatch(nextLow));
    if (hasPattern || (_modal.contains(low) && usefulNext)) {
      raw.add(<String, Object?>{
        'en': text.substring(spans[i].start, spans[i + 1].end),
        'kind': 'tense',
      });
    }
  }
  for (final v in sentence.vocab) {
    final key = v.trim().toLowerCase();
    raw.add(<String, Object?>{
      'en': v,
      if (meanings?[key] != null) 'zh': meanings![key],
      'kind': 'word',
    });
  }
  if (raw.isEmpty) {
    final words = spans
        .map((s) => s.text.replaceAll(RegExp(r"[^A-Za-z'-]"), ''))
        .where((w) => w.length >= 5 && !_stop.contains(w.toLowerCase()))
        .toList()
      ..sort((a, b) => b.length - a.length);
    for (final w in words.take(3)) {
      raw.add(<String, Object?>{
        'en': w,
        if (meanings?[w.toLowerCase()] != null) 'zh': meanings![w.toLowerCase()],
        'kind': 'word',
      });
    }
  }
  return normalizeGoldenTargets(text, raw);
}

GoldenSectionRole goldenSectionRole(int index, int total) {
  if (total <= 1 || index <= 0) return GoldenSectionRole.intro;
  if (index >= total - 1) return GoldenSectionRole.conclusion;
  return GoldenSectionRole.body;
}

/// 由段落 / 句子生成文章脉络；没有段落时整篇算一段。
List<GoldenSection> buildGoldenOutline(
  List<Paragraph>? paragraphs,
  List<Sentence> sentences, [
  List<GoldenSentence>? content,
]) {
  final byId = <String, Sentence>{
    for (final s in sentences) s.id: s,
  };
  final byContent = <String, GoldenSentence>{
    for (final s in content ?? const <GoldenSentence>[]) s.id: s,
  };
  final groups = (paragraphs != null && paragraphs.isNotEmpty)
      ? paragraphs
          .map((p) => (paraId: p.id, ids: p.sentenceIds))
          .toList()
      : sentences.isNotEmpty
          ? <({String paraId, List<String> ids})>[
              (paraId: 'p01', ids: sentences.map((s) => s.id).toList()),
            ]
          : <({String paraId, List<String> ids})>[];
  final out = <GoldenSection>[];
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    Sentence? first;
    for (final id in g.ids) {
      final s = byId[id];
      if (s != null) {
        first = s;
        break;
      }
    }
    final points = <String>[];
    for (final id in g.ids) {
      final s = byId[id];
      if (s == null) continue;
      final zh = byContent[s.id]?.zh ?? s.translation ?? '';
      if (zh.trim().isNotEmpty) points.add(zh.trim());
      if (points.length >= 2) break;
    }
    out.add(GoldenSection(
      paraId: g.paraId,
      role: goldenSectionRole(i, groups.length),
      points: points.isNotEmpty
          ? points
          : (first != null ? <String>[first.text] : const <String>[]),
    ));
  }
  return out;
}

({int score, List<String> reasons}) _scoreSentence(Sentence s) {
  final reasons = <String>[];
  var score = 0;
  final languages = getSentenceLanguages(s);
  final phrases = languages.expand((l) => l.phrases ?? const <String>[]).length;
  final idioms = languages.expand((l) => l.idioms ?? const <String>[]).length;
  if (languages.isNotEmpty) {
    score += 2;
    reasons.add('有语言点');
  }
  if (phrases > 0) {
    score += phrases > 3 ? 3 : phrases;
    reasons.add('$phrases 个词组');
  }
  if (idioms > 0) {
    score += 2;
    reasons.add('习语');
  }
  if (languages.any((l) => (l.grammar ?? '').trim().isNotEmpty)) {
    score += 1;
    reasons.add('时态/语法');
  }
  if ((s.translation ?? '').trim().isNotEmpty) {
    score += 1;
  } else {
    reasons.add('缺译文');
  }
  if (s.collocations.isNotEmpty) {
    score += 1;
    reasons.add('搭配');
  }
  if (s.vocab.isNotEmpty) {
    score += 1;
    reasons.add('生词');
  }
  final n = wordSpans(s.text).length;
  if (n >= 8 && n <= 40) score += 1;
  if (n > 45) score -= 1;
  return (score: score, reasons: reasons);
}

/// 金句候选：按「有语言点/搭配/生词/长度合适」打分；同分按原文顺序。
class GoldenCandidate {
  const GoldenCandidate({
    required this.id,
    required this.index,
    required this.score,
    required this.reasons,
  });

  final String id;
  final int index;
  final int score;
  final List<String> reasons;
}

List<GoldenCandidate> rankGoldenCandidates(List<Sentence> sentences) {
  final seen = <String>{};
  final out = <GoldenCandidate>[];
  for (var index = 0; index < sentences.length; index++) {
    final s = sentences[index];
    final text = s.text.trim();
    if (text.isEmpty || !seen.add(text)) continue;
    final scored = _scoreSentence(s);
    out.add(GoldenCandidate(
      id: s.id,
      index: index,
      score: scored.score,
      reasons: scored.reasons,
    ));
  }
  out.sort((a, b) => b.score != a.score
      ? b.score - a.score
      : a.index - b.index);
  return out;
}

List<GoldenCandidate> pickGoldenCandidates(
  List<Sentence> sentences, [
  int limit = goldenDefaultLimit,
]) {
  final max = limit < 1 ? 1 : (limit > goldenMaxLimit ? goldenMaxLimit : limit);
  return rankGoldenCandidates(sentences).take(max).toList(growable: false);
}

GoldenSentence buildLocalGoldenSentence(
  Sentence sentence, [
  Map<String, String>? meanings,
]) {
  final languages = getSentenceLanguages(sentence);
  final grammar = languages
      .map((l) => (l.grammar ?? '').trim())
      .where((s) => s.isNotEmpty)
      .join('；');
  final structure = languages
      .map((l) => (l.structure ?? '').trim())
      .where((s) => s.isNotEmpty)
      .join('；');
  final usage = languages
      .expand((l) => l.usage ?? const <String>[])
      .where((s) => s.trim().isNotEmpty)
      .toList();
  return GoldenSentence(
    id: sentence.id,
    zh: (sentence.translation ?? '').trim().isEmpty
        ? null
        : sentence.translation!.trim(),
    pattern: structure.isEmpty ? null : structure,
    tense: grammar.isEmpty ? null : grammar,
    note: usage.isEmpty ? null : usage.join('；'),
    targets: buildLocalTargets(sentence, meanings),
  );
}

class LocalGoldenOptions {
  const LocalGoldenOptions({
    this.limit = goldenDefaultLimit,
    this.selected,
    this.meanings,
    this.dedupe = false,
    this.blankUnit = GoldenBlankUnit.word,
  });

  final int limit;
  final List<String>? selected;
  final Map<String, String>? meanings;
  final bool dedupe;
  final GoldenBlankUnit blankUnit;
}

/// 没有 AI 也能用的金句课：结构、金句、目标全部由现有译文/语言点推导。
GoldenLesson buildLocalGoldenLesson(
  List<Sentence> sentences, [
  List<Paragraph>? paragraphs,
  LocalGoldenOptions opts = const LocalGoldenOptions(),
]) {
  final List<Sentence> picked;
  if (opts.selected != null && opts.selected!.isNotEmpty) {
    picked = opts.selected!
        .map((id) => sentences.where((s) => s.id == id))
        .expand((it) => it)
        .toList();
  } else {
    picked = pickGoldenCandidates(sentences, opts.limit)
        .map((c) => sentences[c.index])
        .toList();
  }
  final order = <String, int>{
    for (var i = 0; i < sentences.length; i++) sentences[i].id: i,
  };
  final content = picked
      .map((s) => buildLocalGoldenSentence(s, opts.meanings))
      .toList()
    ..sort((a, b) => (order[a.id] ?? 0) - (order[b.id] ?? 0));
  return GoldenLesson(
    source: GoldenSource.local,
    outline: buildGoldenOutline(paragraphs, sentences, content),
    sentences: content,
    selected: content.map((s) => s.id).toList(),
    options: GoldenLessonOptions(
      dedupe: opts.dedupe,
      pick: opts.selected != null && opts.selected!.isNotEmpty
          ? GoldenPickMode.manual
          : GoldenPickMode.recommended,
      blankUnit: opts.blankUnit,
    ),
  );
}

/// 打开「本课去重」只改设置，**不改内容**：真正过滤发生在取目标时
/// （[goldenTargetsFor]），这样用户关掉开关还能恢复完整目标。
GoldenLesson dedupeGoldenLesson(GoldenLesson lesson) => lesson.copyWith(
      options: GoldenLessonOptions(
        dedupe: true,
        pick: lesson.options.pick,
        blankUnit: lesson.options.blankUnit,
        sentenceFill: lesson.options.sentenceFill,
        examAfter: lesson.options.examAfter,
      ),
    );

/// 某句实际要练的目标：去重开启时，同一目标只在第一句（按 selected 顺序）
/// 出现的地方保留；后面句子跳过它。默认按句独立，直接返回全部目标。
List<GoldenTarget> goldenTargetsFor(GoldenLesson lesson, String sentenceId) {
  final s = lesson.sentences.where((x) => x.id == sentenceId);
  if (s.isEmpty) return const <GoldenTarget>[];
  if (!lesson.options.dedupe) return s.first.targets;
  final order = lesson.selected.isNotEmpty
      ? lesson.selected
      : lesson.sentences.map((x) => x.id).toList();
  final seen = <String>{};
  for (final id in order) {
    final cur = lesson.sentences.where((x) => x.id == id);
    if (cur.isEmpty) continue;
    if (id == sentenceId) {
      return cur.first.targets.where((t) => seen.add(goldenTargetKey(t))).toList();
    }
    for (final t in cur.first.targets) {
      seen.add(goldenTargetKey(t));
    }
  }
  return s.first.targets;
}
