/// 按词吸附选区。
///
/// 阅读时用鼠标很难刚好停在词边界：想选 "abandon back"，终点常常落在 back 的
/// b / a / c / k 上。这里把选区两端扩到**整词**，于是只要碰到某个词（哪怕只碰到
/// 首字母），那个词就算整个被选中；没碰到就不算。
///
/// 纯函数，不碰界面，方便单测。界面那边负责把字符偏移量算出来再喂进来。
library;

/// 一个「词」在原文里的位置。
class WordSpan {
  const WordSpan({required this.start, required this.end, required this.text});

  /// 在原文里的起始字符下标
  final int start;

  /// 结束字符下标（开区间）
  final int end;

  final String text;

  @override
  bool operator ==(Object other) =>
      other is WordSpan && other.start == start && other.end == end && other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'WordSpan($start, $end, $text)';
}

/// 连字符（ASCII `-` 和 Unicode `‐`）；en/em dash 不算复合词，避免误并。
final RegExp hyphen = RegExp('^[-\u2010]\$');

/// 把「词-词」这种连字符复合词并成一个词（bad-tempered、burqa-clad）。
List<WordSpan> mergeHyphenated(String text, List<WordSpan> spans) {
  final out = <WordSpan>[];
  for (final w in spans) {
    if (out.isNotEmpty) {
      final prev = out.last;
      if (hyphen.hasMatch(text.substring(prev.end, w.start))) {
        final merged = WordSpan(start: prev.start, end: w.end, text: text.substring(prev.start, w.end));
        out[out.length - 1] = merged;
        continue;
      }
    }
    out.add(WordSpan(start: w.start, end: w.end, text: w.text));
  }
  return out;
}

/// 分词结果缓存（LRU，按原文文本做 key）。
///
/// 为什么需要：正文每渲染一次就要给**每一句**重新分词。实测 300 句约 32ms
/// （冷启动 87ms），而朗读时逐词高亮会让当前词每秒变 3–5 次，等于每秒白跑
/// 100–160ms 的分词。文本是稳定的，结果纯函数可缓存。
///
/// 调用方只读：返回的列表 / 对象**不要原地改**（要改就自己拷一份）。
/// 上限 500 条：一篇长文 + 相邻几篇足够，超出按最久未用淘汰。
const int spanCacheMax = 500;
final Map<String, List<WordSpan>> _spanCache = <String, List<WordSpan>>{};

/// 清空分词缓存（测试用）。
void clearSpanCache() => _spanCache.clear();

/// 切出所有「词」（含字母或数字的片段），标点和空白不算词。
List<WordSpan> wordSpans(String text) {
  final hit = _spanCache.remove(text);
  if (hit != null) {
    // 命中后挪到队尾（Map 保持插入序，最前面的就是最久未用）
    _spanCache[text] = hit;
    return hit;
  }
  final spans = computeWordSpans(text);
  if (_spanCache.length >= spanCacheMax) {
    final oldest = _spanCache.keys.firstOrNull;
    if (oldest != null) _spanCache.remove(oldest);
  }
  _spanCache[text] = spans;
  return spans;
}

final RegExp _wordRun = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// 不经过缓存的分词（内部用；测试可直接调）。
List<WordSpan> computeWordSpans(String text) {
  final out = <WordSpan>[];
  for (final m in _wordRun.allMatches(text)) {
    out.add(WordSpan(start: m.start, end: m.end, text: m.group(0)!));
  }
  return mergeHyphenated(text, out);
}

/// 把区间 [start, end) 扩到整词。
///   - 只落在某个词里 → 返回那个词
///   - 跨了多个词 → 返回首词到末词（中间全包）
///   - 落在标点/空白里 → 就近归到旁边的词
///
/// start/end 顺序无所谓；没有词时返回 null。
WordSpan? snapSelection(String text, int start, int end) {
  final spans = wordSpans(text);
  if (spans.isEmpty) return null;
  final lo = start < end ? start : end;
  final lo0 = lo < 0 ? 0 : lo;
  final hiRaw = start > end ? start : end;
  final hi = hiRaw < 0 ? 0 : hiRaw;

  var first = spans.where((w) => lo0 >= w.start && lo0 < w.end).firstOrNull;
  first ??= spans.where((w) => w.start >= lo0).firstOrNull;
  first ??= spans.last;
  // hi 是开区间：看 hi-1 落在哪个词里，这样正好停在词边界时不会多包一个词
  final edge = hi > lo0 ? hi - 1 : lo0;
  var last = spans.where((w) => edge >= w.start && edge < w.end).firstOrNull;
  last ??= spans.where((w) => w.end <= hi).lastOrNull;
  last ??= first;

  final iFirst = spans.indexOf(first);
  final iLast = spans.indexOf(last);
  final from = iFirst < iLast ? iFirst : iLast;
  final to = iFirst > iLast ? iFirst : iLast;
  return WordSpan(
    start: spans[from].start,
    end: spans[to].end,
    text: text.substring(spans[from].start, spans[to].end),
  );
}

/// 切换某个**词下标**的选中状态。
///
/// 按位置而不是按词形：同一句里出现多次的同一个词（如两个 `a`）各自独立，
/// 点其中一个不会把另一个也选上。
List<int> toggleIndex(List<int> indices, int i) =>
    indices.contains(i) ? indices.where((x) => x != i).toList() : <int>[...indices, i];

/// 取选中下标对应的词形（按句内顺序）。
List<String> wordsAtIndex(List<WordSpan> spans, List<int> indices) {
  final sorted = <int>[...indices]..sort();
  final out = <String>[];
  for (final i in sorted) {
    if (i < 0 || i >= spans.length) continue;
    out.add(spans[i].text);
  }
  return out;
}

/// 字符区间 [start, end) 覆盖了这句话的第几到第几个词（下标区间，end 开）。
/// 起点不在任何词上、或整句没词时返回 null。
({int start, int end})? wordIndexRange(String text, int start, int end) {
  final spans = wordSpans(text);
  var first = -1;
  for (var i = 0; i < spans.length; i++) {
    if (spans[i].end > start) {
      first = i;
      break;
    }
  }
  if (first < 0) return null;
  var last = first;
  for (var i = spans.length - 1; i >= 0; i--) {
    if (spans[i].start < end) {
      last = i;
      break;
    }
  }
  return (start: first, end: last + 1);
}
