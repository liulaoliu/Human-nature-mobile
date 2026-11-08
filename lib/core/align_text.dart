/// 文本 ↔ 音频块的时间对齐。
///
/// 严格说这不是语音识别对齐，是**按块时长比例摊词**：Economist 音频朗读语速
/// 大致恒定，「块时长 / 总时长 × 总词数」一般落在真实范围附近，块内会有几个词
/// 的漂移。当作「这块大概读到哪」的导航足够，不是精确字幕。
///
/// 唯一的硬保证：**所有块按顺序拼起来 == 原文的词序，一个词不丢不重。**
/// 手动锚点能把手撕开/合并后的块重新钉准，见 [alignTextToChunksWithAnchors]。
///
/// 对应 Web 版 `src/core/alignText.ts`（270 行）。
library;

import 'ports.dart';

class AlignedChunk {
  const AlignedChunk({
    required this.index,
    required this.text,
    required this.wordRange,
    this.anchored = false,
  });

  final int index;
  final String text;

  /// 在全文里的起止词序号 `[start, end)`。
  final List<int> wordRange;

  /// 这一块是被手动锚点钉过的（UI 上标出来）。
  final bool anchored;

  int get startWord => wordRange[0];
  int get endWord => wordRange[1];

  @override
  String toString() => 'AlignedChunk($index, $startWord-$endWord, "$text")';
}

/// 锚点映射到具体块号、并重新定位词序号之后的样子。
class ResolvedAnchor {
  const ResolvedAnchor({
    required this.atSec,
    required this.chunkIndex,
    required this.startWord,
    required this.endWord,
  });

  final double atSec;
  final int chunkIndex;
  final int startWord;
  final int endWord;
}

/// 句末标点，后面可以跟收尾的括号引号。
final RegExp sentenceEnd = RegExp(r'''[.!?][)\]}"”’']*$''');

/// 下一句首字母（允许先来一个开引号）。
final RegExp _upperStart = RegExp(r'''^[“‘"']?[A-Z]''');

final RegExp _openParen = RegExp(r'[([{]');
final RegExp _closeParen = RegExp(r'[)\]}]');
final RegExp _space = RegExp(r'\s+');

List<String> splitWords(String text) =>
    text.trim().split(_space).where((w) => w.isNotEmpty).toList();

/// 把一段文本按块的时长比例摊到各块上。
///
/// [offsetWords] 是整体平移：音频不念副题/小标题时，文本会整体比音频「多」一截，
/// 高亮就跟不上听到的。正数把词窗往后推（高亮往前赶），负数反之。
/// 平移加在边界上再夹到 `[0, total]`，首尾锚在 0 和 total，被挤出去的词归给
/// 第一块/最后一块 —— 所以「拼起来等于原文」这条硬保证不受影响。
List<AlignedChunk> alignTextToChunks(String text, List<Chunk> chunks, {int offsetWords = 0}) {
  if (chunks.isEmpty) return const [];
  final words = splitWords(text);
  final total = words.length;

  final durations = [for (final c in chunks) (c.end - c.start).clamp(0.0, double.infinity)];
  final totalDur = durations.fold<double>(0, (a, b) => a + b);
  if (totalDur <= 0) {
    return [for (final c in chunks) AlignedChunk(index: c.index, text: '', wordRange: const [0, 0])];
  }

  // 每块按比例的结束词序号，强制单调。
  final n = chunks.length;
  final raw = <int>[];
  var acc = 0.0;
  for (var i = 0; i < n; i++) {
    acc += durations[i];
    final at = i == n - 1 ? total : (acc / totalDur * total).round();
    raw.add(i == 0 ? at : (at > raw[i - 1] ? at : raw[i - 1]));
  }

  // 整体平移。clamp 是单调的，所以平移后仍然单调；末块锚回 total，
  // 中间的平移量才不会被夹掉。
  final bounds = [for (final v in raw) (v + offsetWords).clamp(0, total)];
  bounds[n - 1] = total;

  final parenDepth = depthAfterEachWord(words);
  final ends = <int>[];
  var start = 0;
  for (var i = 0; i < n; i++) {
    final limit = i == n - 1 ? total : bounds[i + 1];
    var end = i == n - 1
        ? total
        : snapToSentence(words, parenDepth, bounds[i], limit, start);
    final cap = limit > start ? limit : start;
    if (end > cap) end = cap;
    if (end <= start && start < total) end = start + 1; // 不给空块，除非词已用完
    ends.add(end);
    start = end;
  }

  final out = <AlignedChunk>[];
  for (var i = 0; i < n; i++) {
    final s = i == 0 ? 0 : ends[i - 1];
    out.add(AlignedChunk(
      index: chunks[i].index,
      text: words.sublist(s, ends[i]).join(' '),
      wordRange: [s, ends[i]],
    ));
  }
  return out;
}

/// 把锚点解析成「哪一块、对应原文哪几个词」。
///
/// 两步：`atSec` → 块号（按音频时间，换切块粒度不失效）；再找词范围 ——
/// 优先在当前词表里搜锚点记下的原文，搜得到就用它的位置（改别处的文字后
/// 进度不乱），搜不到（那段本身被改了）再退回记下的词序号并夹紧。
///
/// 同一块只留一个锚点；重叠/乱序的靠前的赢。
List<ResolvedAnchor> resolveAnchors(List<String> words, List<Chunk> chunks, List<ManualAnchor> anchors) {
  final byChunk = <int, ResolvedAnchor>{};
  for (final a in anchors) {
    final located = locateAnchor(a, words);
    if (located == null) continue;
    final k = chunkIndexAt(chunks, a.atSec);
    byChunk[k] = ResolvedAnchor(
      atSec: a.atSec,
      chunkIndex: k,
      startWord: located[0],
      endWord: located[1],
    );
  }
  final sorted = byChunk.values.toList()..sort((x, y) => x.chunkIndex - y.chunkIndex);
  final out = <ResolvedAnchor>[];
  for (final a in sorted) {
    if (out.isNotEmpty && a.startWord < out.last.endWord) continue;
    out.add(a);
  }
  return out;
}

/// 在词表里找回锚点记的那段原文；搜不到就退回存下的序号。
List<int>? locateAnchor(ManualAnchor a, List<String> words) {
  final total = words.length;
  final stored = clampInt(a.startWord.toDouble(), 0, total);
  final seq = a.text == null ? const <String>[] : splitWords(a.text!);
  if (seq.isNotEmpty) {
    final at = findWordSequence(words, seq, stored);
    if (at >= 0) return [at, at + seq.length];
  }
  final end = clampInt(a.endWord.toDouble(), 0, total);
  return end > stored ? [stored, end] : null;
}

/// 在 words 里找 seq 出现的位置，取离 hint 最近的那个（防止重复短语认错）。
int findWordSequence(List<String> words, List<String> seq, int hint) {
  var best = -1;
  var bestDist = double.infinity;
  final last = words.length - seq.length;
  for (var i = 0; i <= last; i++) {
    var ok = true;
    for (var j = 0; j < seq.length; j++) {
      if (words[i + j] != seq[j]) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    final d = (i - hint).abs().toDouble();
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

/// 带手动锚点的对齐。
///
/// 每个锚点说「音频里 atSec 那一块，读的是原文的某一段」。锚点之间（以及首尾）
/// 的词按块时长比例摊开 —— 钉住的块是准的，没钉的地方仍是估的，但全文一个词
/// 不丢不重。首尾 `b[0]/b[n]` 一定锚死。
List<AlignedChunk> alignTextToChunksWithAnchors(
  String text,
  List<Chunk> chunks,
  List<ManualAnchor> anchors,
) {
  final n = chunks.length;
  if (n == 0) return const [];
  final words = splitWords(text);
  final total = words.length;
  if (total == 0 || anchors.isEmpty) return alignTextToChunks(text, chunks);

  final clean = resolveAnchors(words, chunks, anchors);
  if (clean.isEmpty) return alignTextToChunks(text, chunks);

  // 已知的块边界（词序号）。锚点把两个相邻边界钉死；
  // 0 和 n 一定要最后设：首尾是硬的，锚点碰不到它们。
  final fixed = <int, int>{};
  for (final a in clean) {
    fixed[a.chunkIndex] = a.startWord;
    fixed[a.chunkIndex + 1] = a.endWord;
  }
  fixed[0] = 0;
  fixed[n] = total;
  final points = fixed.entries.toList()..sort((x, y) => x.key - y.key);

  final anchored = {for (final a in clean) a.chunkIndex};
  final result = List<AlignedChunk?>.filled(n, null);
  for (var p = 0; p < points.length - 1; p++) {
    final i = points[p].key;
    final u = points[p].value;
    final j = points[p + 1].key;
    final v = points[p + 1].value;
    final subText = words.sublist(u, v).join(' ');
    final sub = alignTextToChunks(subText, chunks.sublist(i, j));
    for (final a in sub) {
      result[a.index] = AlignedChunk(
        index: a.index,
        text: a.text,
        wordRange: [u + a.wordRange[0], u + a.wordRange[1]],
      );
    }
  }

  return [
    for (var i = 0; i < n; i++)
      if (anchored.contains(i))
        AlignedChunk(
          index: result[i]?.index ?? chunks[i].index,
          text: result[i]?.text ?? '',
          wordRange: result[i]?.wordRange ?? const [0, 0],
          anchored: true,
        )
      else
        result[i] ?? AlignedChunk(index: chunks[i].index, text: '', wordRange: const [0, 0]),
  ];
}

/// `t` 落在哪一块（按 `start <= t < end`）；落在缝里/外面就取最近的那块。
int chunkIndexAt(List<Chunk> chunks, double t) {
  var best = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < chunks.length; i++) {
    if (t < chunks[i].end) return i;
    final d = (chunks[i].start - t).abs();
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

int clampInt(double v, int lo, int hi) {
  if (!v.isFinite) return lo;
  final r = v.round();
  return r < lo ? lo : (r > hi ? hi : r);
}

/// 每个词读完之后，括号还剩几层没闭合。
List<int> depthAfterEachWord(List<String> words) {
  final out = <int>[];
  var depth = 0;
  for (final w in words) {
    final open = _openParen.allMatches(w).length;
    final close = _closeParen.allMatches(w).length;
    depth = depth + open - close;
    if (depth < 0) depth = 0;
    out.add(depth);
  }
  return out;
}

/// 从 `at` 往两边找最近的句末。三个约束：
/// 1. 下一句首字母要大写，否则 `The U.S. economy` 会被切成两半；
/// 2. 那个句号不能在未闭合的括号里，否则 `(see page 4. Note this).` 会切错；
/// 3. 搜索窗口按块自身大小算（±60%），不越到下一块的地界去 —— 固定窗口会把
///    6 词的小块撑成 16 词，比例就废了。找不到就退回 `at`。
int snapToSentence(List<String> words, List<int> parenDepth, int at, int limit, int floor) {
  final half = (at * 0.6).round();
  final window = half < 2 ? 2 : half;
  final from = at - window > floor ? at - window : floor;
  final to = at + window < limit ? at + window : limit;
  for (var i = from; i < to; i++) {
    if (parenDepth[i] != 0) continue;
    if (!sentenceEnd.hasMatch(words[i])) continue;
    final next = i + 1 < words.length ? words[i + 1] : null;
    if (next == null) return i + 1;
    if (_upperStart.hasMatch(next)) return i + 1;
  }
  final clamped = at > floor ? at : floor;
  return clamped > limit ? limit : clamped;
}
