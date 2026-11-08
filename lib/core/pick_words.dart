/// 选字定块：把鼠标选区换算成原文的词序号区间。
///
/// UI 层只负责量出「选区两端在整段文字里的字符下标」，剩下的换算放这里，
/// 不碰 DOM / Widget，方便单测。
///
/// 这样比按渲染节点去猜更稳（选区端点常常落在节点上、或在段与段交界）。
///
/// 对应 Web 版 `src/core/pickWords.ts`。
library;

import 'dart:math' as math;

final RegExp _trailingSpace = RegExp(r'\s$');
final RegExp _spaces = RegExp(r'\s');
final RegExp _allSpaces = RegExp(r'\s+');

/// 一个文字边界落在第几个词上（相对它所在文本的开头）。
///
/// - 以空白结尾 = 已经跨过前一个词，落在下一个词开头
/// - 否则 = 落在这个词上（词中间或词尾）
///
/// 例（文本 `"aa bb cc "`）：
///   ""            → 0
///   "aa"          → 0  （在第一个词里）
///   "aa "         → 1  （跨过第一个词）
///   "aa bb"       → 1
///   "aa bb "      → 2
int caretWordIndex(String prefix) {
  if (prefix.isEmpty) return 0;
  if (_trailingSpace.hasMatch(prefix)) return countWords(prefix);
  return _spaces.allMatches(prefix).length;
}

/// 这段文本里有几个词（按空白切）。
int countWords(String text) {
  final t = text.trim();
  return t.isEmpty ? 0 : t.split(_allSpaces).length;
}

/// 把选区换算成词序号区间 `[from, to)`；光标 / 空选区返回 null。
///
/// - [text]：整块文本（各段拼起来，词之间单空格）
/// - [startOffset] / [endOffset]：选区两端在 text 里的字符下标
({int start, int end})? wordRangeFromText(
  String text,
  int startOffset,
  int endOffset,
) {
  final len = text.length;
  var a = math.max(0, math.min(startOffset, len));
  var b = math.max(0, math.min(endOffset, len));
  if (a > b) {
    final t = a;
    a = b;
    b = t;
  }
  if (b <= a) return null; // 光标 / 空选区

  final total = countWords(text);
  final from = caretWordIndex(text.substring(0, a));
  final endPrefix = text.substring(0, b);
  // 终点落在词中间/词尾时把它算进来（+1）；正好落在空格后就不算
  final tail = _trailingSpace.hasMatch(endPrefix) ? 0 : 1;
  final to = math.min(total, caretWordIndex(endPrefix) + tail);
  if (to <= from) return null;
  return (start: from, end: to);
}
