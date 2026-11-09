/// 金句课的三种练习：挖空、拼句、逆向默写。
///
/// 对应 Web `src/core/goldenDrill.ts`（434 行）。这里只做**构造与判分**，
/// 不碰会话状态 —— 轮次、当前第几空、对错记录都在页面层。
///
/// 三种练习的难度梯度是设计过的，别随手合并：
///   - 挖空：给整句，抠掉目标，一个语言点一个空（`splitWords` 才一词一空）；
///   - 细碎轮：目标后缀逐步变长（`with` → `up with` → `keep up with`）；
///   - 整句渐进：一个词 → 本句所有目标词 → 分句 / 整句；
///   - 拼句：只给打乱的目标块，按顺序拼回；
///   - 逆向默写：只给中文，整句默写，按与原句的接近度判「首次是否算掌握」。
library;

import 'golden.dart';
import 'quiz_parts.dart';
import 'text_diff.dart';
import 'word_select.dart';

/// 一个空。
class GoldenClozeBlank {
  const GoldenClozeBlank({
    required this.index,
    required this.targetIndex,
    required this.answer,
    required this.kind,
    this.wordIndex,
    this.hint,
  });

  /// 空序号（1 起）；同一语言点的多个词各占一个。
  final int index;

  /// 对应原句里的第几个语言点（0 起）。
  final int targetIndex;

  /// 按词拆时，词在该语言点内的序号（0 起）；按整块时没有。
  final int? wordIndex;

  final String answer;
  final String? hint;
  final GoldenTargetKind kind;

  GoldenClozeBlank copyWith({int? index, int? targetIndex, String? answer}) =>
      GoldenClozeBlank(
        index: index ?? this.index,
        targetIndex: targetIndex ?? this.targetIndex,
        wordIndex: wordIndex,
        answer: answer ?? this.answer,
        kind: kind,
        hint: hint,
      );
}

/// 句子被切成「文本段」和「空」交替的片段。
class GoldenClozePart {
  const GoldenClozePart({
    required this.text,
    required this.blank,
    this.targetIndex,
    this.blankIndex,
  });

  final String text;
  final bool blank;
  final int? targetIndex;
  final int? blankIndex;
}

/// 一句的挖空结果。
class GoldenCloze {
  const GoldenCloze({
    required this.sentence,
    required this.parts,
    required this.blanks,
    required this.targets,
  });

  final String sentence;
  final List<GoldenClozePart> parts;
  final List<GoldenClozeBlank> blanks;
  final List<GoldenTarget> targets;
}

/// 挖空选项。
class GoldenClozeOptions {
  const GoldenClozeOptions({this.splitWords = false});

  /// `true` = 一个词一个空；`false`（默认）= 一个语言点一个空。
  final bool splitWords;
}

/// 内部用：候选 span + 它属于第几个语言点。
class _Candidate {
  const _Candidate({
    required this.start,
    required this.end,
    required this.text,
    required this.targetIndex,
  });

  final int start;
  final int end;
  final String text;
  final int targetIndex;
}

/// 把目标在句子里挖空。
///
/// - 默认按语言点整块挖（拼句也用这份）；
/// - `splitWords: true` 时一个词一个空；
/// - 同一目标重复出现时共用同一组空（一个输入管所有出现位置）。
GoldenCloze? buildGoldenCloze(
  String text,
  List<GoldenTarget> targets, [
  GoldenClozeOptions opts = const GoldenClozeOptions(),
]) {
  final found = <({GoldenTarget target, int targetIndex, List<GoldenTargetSpan> spans})>[];
  for (var i = 0; i < targets.length; i++) {
    final spans = findGoldenTargetSpans(text, targets[i].en);
    if (spans.isEmpty) continue;
    found.add((target: targets[i], targetIndex: i, spans: spans));
  }
  if (found.isEmpty) return null;

  final candidates = <_Candidate>[
    for (final x in found)
      for (final sp in x.spans)
        _Candidate(
          start: sp.start,
          end: sp.end,
          text: sp.text,
          targetIndex: x.targetIndex,
        ),
  ]..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.end.compareTo(a.end);
    });

  final resolved = <_Candidate>[];
  for (final sp in candidates) {
    final overlap = resolved.any((x) => sp.start < x.end && sp.end > x.start);
    if (overlap) continue;
    resolved.add(sp);
  }
  if (resolved.isEmpty) return null;

  final usedIndexes = <int>{for (final x in resolved) x.targetIndex};
  final finalTargets = <GoldenTarget>[
    for (var i = 0; i < targets.length; i++)
      if (usedIndexes.contains(i)) targets[i],
  ];
  final remap = <int, int>{};
  for (var finalIndex = 0; finalIndex < finalTargets.length; finalIndex++) {
    final original = targets.indexOf(finalTargets[finalIndex]);
    remap[original] = finalIndex;
  }
  final spans = <_Candidate>[
    for (final sp in resolved)
      _Candidate(
        start: sp.start,
        end: sp.end,
        text: sp.text,
        targetIndex: remap[sp.targetIndex] ?? 0,
      ),
  ];

  if (!opts.splitWords) {
    final parts = <GoldenClozePart>[];
    var pos = 0;
    for (final sp in spans) {
      if (sp.start > pos) {
        parts.add(GoldenClozePart(text: text.substring(pos, sp.start), blank: false));
      }
      parts.add(GoldenClozePart(
        text: text.substring(sp.start, sp.end),
        blank: true,
        targetIndex: sp.targetIndex,
        blankIndex: sp.targetIndex + 1,
      ));
      pos = sp.end;
    }
    if (pos < text.length) {
      parts.add(GoldenClozePart(text: text.substring(pos), blank: false));
    }
    final blanks = <GoldenClozeBlank>[
      for (var i = 0; i < finalTargets.length; i++)
        GoldenClozeBlank(
          index: i + 1,
          targetIndex: i,
          answer: finalTargets[i].en,
          kind: finalTargets[i].kind,
          hint: (finalTargets[i].zh == null || finalTargets[i].zh!.isEmpty)
              ? null
              : finalTargets[i].zh,
        ),
    ];
    return GoldenCloze(
      sentence: text,
      parts: parts,
      blanks: blanks,
      targets: finalTargets,
    );
  }

  final blanks = <GoldenClozeBlank>[];
  final blankByTargetWord = <String, int>{};
  final pieces = <({int start, int end, int targetIndex, int blankIndex})>[];
  for (final sp in spans) {
    if (sp.targetIndex >= finalTargets.length) continue;
    final target = finalTargets[sp.targetIndex];
    final words = wordSpans(sp.text);
    final units = words.isNotEmpty
        ? words
        : <WordSpan>[WordSpan(start: 0, end: sp.text.length, text: sp.text)];
    for (var wordIndex = 0; wordIndex < units.length; wordIndex++) {
      final w = units[wordIndex];
      final key = '${sp.targetIndex}|$wordIndex';
      var blankIndex = blankByTargetWord[key];
      if (blankIndex == null) {
        blankIndex = blanks.length + 1;
        blankByTargetWord[key] = blankIndex;
        blanks.add(GoldenClozeBlank(
          index: blankIndex,
          targetIndex: sp.targetIndex,
          wordIndex: wordIndex,
          answer: w.text,
          kind: target.kind,
          hint: (wordIndex == 0 && target.zh != null && target.zh!.isNotEmpty)
              ? target.zh
              : null,
        ));
      }
      pieces.add((
        start: sp.start + w.start,
        end: sp.start + w.end,
        targetIndex: sp.targetIndex,
        blankIndex: blankIndex,
      ));
    }
  }
  pieces.sort((a, b) => a.start.compareTo(b.start));
  final parts = <GoldenClozePart>[];
  var pos = 0;
  for (final p in pieces) {
    if (p.start > pos) {
      parts.add(GoldenClozePart(text: text.substring(pos, p.start), blank: false));
    }
    parts.add(GoldenClozePart(
      text: text.substring(p.start, p.end),
      blank: true,
      targetIndex: p.targetIndex,
      blankIndex: p.blankIndex,
    ));
    pos = p.end;
  }
  if (pos < text.length) {
    parts.add(GoldenClozePart(text: text.substring(pos), blank: false));
  }
  return GoldenCloze(
    sentence: text,
    parts: parts,
    blanks: blanks,
    targets: finalTargets,
  );
}

/// 一轮填空。
class GoldenFillRound {
  const GoldenFillRound({
    required this.targetIndex,
    required this.wordFrom,
    required this.cloze,
    this.scope,
  });

  /// 对应原句里的第几个语言点；整句渐进轮固定 0。
  final int targetIndex;

  /// 从该语言点的第几个词开始（0 起）。
  final int wordFrom;

  final GoldenCloze cloze;

  /// `target` = 细碎语言点轮；`sentence` = 从单词到分句/整句的复述轮。
  final String? scope;
}

/// 整句渐进最多挖到多少词；更长的句子退化成「挖一个分句」。
const int goldenSentenceFillMaxWords = 24;

/// 只挖某个语言点的一段（从 wordFrom 到末尾）。
GoldenCloze? _buildWordClozeForSpan(
  String text,
  GoldenTarget target,
  int spanStart,
  int spanEnd,
  int wordFrom,
) {
  final targetText = text.substring(spanStart, spanEnd);
  final words = wordSpans(targetText);
  if (words.isEmpty || wordFrom < 0 || wordFrom >= words.length) return null;
  final selected = words.sublist(wordFrom);
  final blanks = <GoldenClozeBlank>[
    for (var i = 0; i < selected.length; i++)
      GoldenClozeBlank(
        index: i + 1,
        targetIndex: 0,
        wordIndex: wordFrom + i,
        answer: selected[i].text,
        kind: target.kind,
        hint: (i == 0 && target.zh != null && target.zh!.isNotEmpty)
            ? target.zh
            : null,
      ),
  ];
  final pieces = <({int start, int end, int blankIndex})>[
    for (var i = 0; i < selected.length; i++)
      (
        start: spanStart + selected[i].start,
        end: spanStart + selected[i].end,
        blankIndex: i + 1,
      ),
  ];
  final parts = <GoldenClozePart>[];
  var pos = 0;
  for (final p in pieces) {
    if (p.start > pos) {
      parts.add(GoldenClozePart(text: text.substring(pos, p.start), blank: false));
    }
    parts.add(GoldenClozePart(
      text: text.substring(p.start, p.end),
      blank: true,
      targetIndex: 0,
      blankIndex: p.blankIndex,
    ));
    pos = p.end;
  }
  if (pos < text.length) {
    parts.add(GoldenClozePart(text: text.substring(pos), blank: false));
  }
  return GoldenCloze(
    sentence: text,
    parts: parts,
    blanks: blanks,
    targets: <GoldenTarget>[target],
  );
}

/// 细碎填空轮次：一个语言点从最后一个词开始，逐步扩大后缀。
///
/// `keep up with` → `with` → `up with` → `keep up with`。
List<GoldenFillRound> buildGoldenFillRounds(
  String text,
  List<GoldenTarget> targets,
) {
  final base = buildGoldenCloze(text, targets);
  if (base == null) return const <GoldenFillRound>[];
  final rounds = <GoldenFillRound>[];
  for (var targetIndex = 0; targetIndex < base.targets.length; targetIndex++) {
    final target = base.targets[targetIndex];
    final spans = findGoldenTargetSpans(text, target.en);
    if (spans.isEmpty) continue;
    final span = spans.first;
    final words = wordSpans(span.text);
    if (words.isEmpty) continue;
    for (var wordFrom = words.length - 1; wordFrom >= 0; wordFrom--) {
      final cloze = _buildWordClozeForSpan(text, target, span.start, span.end, wordFrom);
      if (cloze != null) {
        rounds.add(GoldenFillRound(
          targetIndex: targetIndex,
          wordFrom: wordFrom,
          cloze: cloze,
          scope: 'target',
        ));
      }
    }
  }
  return rounds;
}

/// 内部用：带目标归属的 span。
class _IndexedSpan {
  const _IndexedSpan({
    required this.start,
    required this.end,
    required this.targetIndex,
    required this.target,
  });

  final int start;
  final int end;
  final int targetIndex;
  final GoldenTarget target;
}

List<_IndexedSpan> _targetSpans(String text, List<GoldenTarget> targets) => <_IndexedSpan>[
      for (var i = 0; i < targets.length; i++)
        for (final span in findGoldenTargetSpans(text, targets[i].en))
          _IndexedSpan(
            start: span.start,
            end: span.end,
            targetIndex: i,
            target: targets[i],
          ),
    ];

/// 只挖指定词序号；用于「从单词到分句/整句」的复述轮。
GoldenCloze? _buildClozeForWordIndexes(
  String text,
  List<GoldenTarget> targets,
  List<WordSpan> words,
  List<int> indexes,
) {
  final picked = indexes.toSet().where((i) => i >= 0 && i < words.length).toList()
    ..sort();
  if (picked.isEmpty) return null;
  final spans = _targetSpans(text, targets);
  final blanks = <GoldenClozeBlank>[];
  final pieces = <({int start, int end, int targetIndex, int blankIndex})>[];
  for (final wordIndex in picked) {
    final word = words[wordIndex];
    _IndexedSpan? hit;
    for (final sp in spans) {
      if (word.start >= sp.start && word.end <= sp.end) {
        hit = sp;
        break;
      }
    }
    final targetIndex = hit?.targetIndex ?? 0;
    final target = hit?.target;
    final blankIndex = blanks.length + 1;
    var hitWordIndex = -1;
    if (hit != null) {
      final inner = wordSpans(text.substring(hit.start, hit.end));
      for (var i = 0; i < inner.length; i++) {
        if (hit.start + inner[i].start == word.start) {
          hitWordIndex = i;
          break;
        }
      }
    }
    blanks.add(GoldenClozeBlank(
      index: blankIndex,
      targetIndex: targetIndex,
      wordIndex: hitWordIndex >= 0 ? hitWordIndex : null,
      answer: word.text,
      kind: target?.kind ?? GoldenTargetKind.word,
      hint: (hit != null &&
              hitWordIndex == 0 &&
              target?.zh != null &&
              target!.zh!.isNotEmpty)
          ? target.zh
          : null,
    ));
    pieces.add((
      start: word.start,
      end: word.end,
      targetIndex: targetIndex,
      blankIndex: blankIndex,
    ));
  }
  final parts = <GoldenClozePart>[];
  var pos = 0;
  for (final p in pieces) {
    if (p.start > pos) {
      parts.add(GoldenClozePart(text: text.substring(pos, p.start), blank: false));
    }
    parts.add(GoldenClozePart(
      text: text.substring(p.start, p.end),
      blank: true,
      targetIndex: p.targetIndex,
      blankIndex: p.blankIndex,
    ));
    pos = p.end;
  }
  if (pos < text.length) {
    parts.add(GoldenClozePart(text: text.substring(pos), blank: false));
  }
  return GoldenCloze(
    sentence: text,
    parts: parts,
    blanks: blanks,
    targets: targets,
  );
}

/// 词序号 → 目标覆盖到的词；重复出现的目标各自算一次。
List<int> _targetWordIndexes(
  String text,
  List<GoldenTarget> targets,
  List<WordSpan> words,
) {
  final at = <int, int>{for (var i = 0; i < words.length; i++) words[i].start: i};
  final out = <int>{};
  for (final sp in _targetSpans(text, targets)) {
    for (final w in wordSpans(text.substring(sp.start, sp.end))) {
      final index = at[sp.start + w.start];
      if (index != null) out.add(index);
    }
  }
  final list = out.toList()..sort();
  return list;
}

/// 用标点把句子切成词序号区间；长句的最后一轮只挖一个分句。
List<List<int>> _clauseIndexRanges(String text, List<WordSpan> words) {
  if (words.length <= 1) return words.isEmpty ? const <List<int>>[] : <List<int>>[<int>[0]];
  final ranges = <List<int>>[];
  var from = 0;
  final splitter = RegExp('[,;:\u2014\u2013]');
  for (var i = 1; i < words.length; i++) {
    final gap = text.substring(words[i - 1].end, words[i].start);
    if (splitter.hasMatch(gap)) {
      ranges.add(<int>[for (var k = from; k < i; k++) k]);
      from = i;
    }
  }
  ranges.add(<int>[for (var k = from; k < words.length; k++) k]);
  return ranges;
}

/// 轮次去重指纹：空白位置 + 原文；只用于同一句内判重。
String goldenClozeKey(GoldenCloze cloze) =>
    cloze.parts.map((p) => p.blank ? '#${p.text}' : p.text).join();

/// 整句复述轮：一个词 → 本句所有目标词 → 分句 / 整句。
List<GoldenFillRound> buildGoldenSentenceFillRounds(
  String text,
  List<GoldenTarget> targets,
) {
  final words = wordSpans(text);
  if (words.isEmpty) return const <GoldenFillRound>[];
  final targetIndexes = _targetWordIndexes(text, targets, words);
  final focus = targetIndexes.isNotEmpty ? targetIndexes.last : words.length - 1;
  final indexSets = <List<int>>[
    <int>[focus],
  ];
  if (targetIndexes.length > 1) indexSets.add(targetIndexes);
  var finalIndexes = <int>[for (var i = 0; i < words.length; i++) i];
  if (words.length > goldenSentenceFillMaxWords) {
    final ranges = _clauseIndexRanges(text, words);
    int score(List<int> range) => range.where(targetIndexes.contains).length;
    final sorted = <List<int>>[...ranges]..sort((a, b) {
        final byScore = score(b).compareTo(score(a));
        return byScore != 0 ? byScore : b.length.compareTo(a.length);
      });
    final best = sorted.isEmpty ? null : sorted.first;
    if (best != null && best.isNotEmpty) finalIndexes = best;
  }
  indexSets.add(finalIndexes);

  final rounds = <GoldenFillRound>[];
  final seen = <String>{};
  for (final indexes in indexSets) {
    final cloze = _buildClozeForWordIndexes(text, targets, words, indexes);
    if (cloze == null) continue;
    final key = goldenClozeKey(cloze);
    if (!seen.add(key)) continue;
    rounds.add(GoldenFillRound(
      targetIndex: 0,
      wordFrom: 0,
      cloze: cloze,
      scope: 'sentence',
    ));
  }
  return rounds;
}

/// 填空计划选项。
class GoldenFillPlanOptions {
  const GoldenFillPlanOptions({this.blankUnit = 'word', this.sentenceFill = true});

  /// `target` = 一个语言点一个空；`word`（默认）= 先按词细碎轮。
  final String blankUnit;

  /// 是否在语言点轮后追加「单词 → 目标词 → 分句 / 整句」。
  final bool sentenceFill;
}

/// 一句金句的完整填空计划：语言点轮 + 整句渐进轮，同一组空只出现一次。
List<GoldenFillRound> buildGoldenFillPlan(
  String text,
  List<GoldenTarget> targets, [
  GoldenFillPlanOptions opts = const GoldenFillPlanOptions(),
]) {
  final List<GoldenFillRound> targetRounds;
  if (opts.blankUnit == 'target') {
    final cloze = buildGoldenCloze(text, targets);
    targetRounds = cloze == null
        ? const <GoldenFillRound>[]
        : <GoldenFillRound>[
            GoldenFillRound(
              targetIndex: 0,
              wordFrom: 0,
              cloze: cloze,
              scope: 'target',
            ),
          ];
  } else {
    targetRounds = buildGoldenFillRounds(text, targets);
  }
  if (!opts.sentenceFill) return targetRounds;
  final seen = <String>{for (final r in targetRounds) goldenClozeKey(r.cloze)};
  final extra = <GoldenFillRound>[];
  for (final r in buildGoldenSentenceFillRounds(text, targets)) {
    if (!seen.add(goldenClozeKey(r.cloze))) continue;
    extra.add(r);
  }
  return <GoldenFillRound>[...targetRounds, ...extra];
}

/// 一个空是否正确：忽略大小写/首尾标点/空白；连字符和撇号也宽容。
bool isGoldenBlankCorrect(GoldenClozeBlank blank, String input) {
  final n = normalizeAnswer(input);
  if (n.isEmpty) return false;
  final a = normalizeAnswer(blank.answer);
  return n == a || canonical(n) == canonical(a);
}

/// 逐空判分，顺序与 `cloze.blanks` 一致。
List<bool> checkGoldenFill(GoldenCloze cloze, List<String> inputs) => <bool>[
      for (final b in cloze.blanks)
        isGoldenBlankCorrect(
          b,
          b.index - 1 < inputs.length ? inputs[b.index - 1] : '',
        ),
    ];

/// 是否全对（空列表算不通过）。
bool goldenFillAllCorrect(List<bool> results) =>
    results.isNotEmpty && results.every((x) => x);

/// 拼句：挖空 + 打乱的目标块。
class GoldenAssembly {
  const GoldenAssembly({required this.cloze, required this.bank});

  final GoldenCloze cloze;

  /// 打乱后的目标英文；点选后按空顺序拼回。
  final List<String> bank;
}

/// 拼句银行：同一组目标打乱；用句子文本做种子，刷新不跳。
GoldenAssembly? buildGoldenAssembly(String text, List<GoldenTarget> targets) {
  final cloze = buildGoldenCloze(text, targets);
  if (cloze == null) return null;
  var seed = 7;
  for (final unit in text.codeUnits) {
    seed = (seed * 31 + unit) & 0xFFFFFFFF;
  }
  var x = seed == 0 ? 1 : seed;
  double rnd() {
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >>> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    return ((x & 0xFFFFFFFF) % 1000000) / 1000000;
  }

  return GoldenAssembly(
    cloze: cloze,
    bank: shuffleQuiz(<String>[for (final t in targets) t.en], rnd),
  );
}

/// 拼句判分：数量与顺序都对才算对。
bool checkGoldenAssembly(List<GoldenTarget> targets, List<String> order) {
  if (order.length != targets.length) return false;
  for (var i = 0; i < targets.length; i++) {
    final a = normalizeAnswer(targets[i].en);
    final b = normalizeAnswer(order[i]);
    if (a != b && canonical(a) != canonical(b)) return false;
  }
  return true;
}

/// 逆向默写结果。
class GoldenRecallResult {
  const GoldenRecallResult({
    required this.closeness,
    required this.diff,
    required this.firstOk,
  });

  final Closeness closeness;
  final List<DiffPart> diff;

  /// 首次作答是否算「掌握」：原句或接近原句。
  final bool firstOk;
}

/// 逆向默写：严格按原句（exact / near ≥ 0.9）；自评只影响完成，不影响掌握。
GoldenRecallResult checkGoldenRecall(String input, String reference) {
  final closeness = compareToReference(input, reference);
  return GoldenRecallResult(
    closeness: closeness,
    diff: diffWords(input, reference),
    firstOk: input.trim().isNotEmpty &&
        (closeness.exact || closeness.tier == 'near'),
  );
}
