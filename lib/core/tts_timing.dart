/// 把 TTS 的逐词时间戳对齐到句子里的词序（跟读 / 逐词高亮用）。
///
/// 对应 Web 版 `src/core/ttsTiming.ts`（45 行）。服务端（或合成引擎）给的
/// 时间戳未必和原文逐字一致：可能少一个词、多一个词、大小写或标点不同。
/// 这里的原则是**宁可不高亮，也不把时间戳错配到别的词上**。
///
/// 纯函数，不碰播放器。
library;

import 'text_norm.dart';
import 'word_select.dart';

/// 一个词的音频区间（毫秒）。
class WordTiming {
  const WordTiming({required this.start, required this.end});

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is WordTiming && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'WordTiming($start, $end)';
}

/// 时间戳里的一段：`part` 是它念的词（可能带标点 / 大小写差异）。
class TimingPart {
  const TimingPart({this.part, required this.start, required this.end});

  final String? part;
  final int start;
  final int end;

  @override
  String toString() => 'TimingPart(${part ?? ''}, $start, $end)';
}

/// 比较用的归一化：小写 + 近似 NFKC + 只留字母数字和撇号。
String _normW(String s) =>
    nfkc(s.toLowerCase()).replaceAll(RegExp(r"[^a-z0-9']"), '');

/// 朗读引擎报的字符区间 → 这句话里该亮第几个词（0 起）。
///
/// 为什么有这条：安卓 TTS 的 `onRangeStart` 报的是**字符区间**，不是毫秒；
/// [alignTimings] 那条是给「服务端带时间戳的音频」用的，真机上没有那种数据。
/// 所以逐词高亮（跟读）走这里，单位是字符下标，直接对上 [wordSpans]。
///
/// 规则比 [alignTimings] 更保守：**整句一个区间时不猜**。老系统（API < 26）
/// 只在开口时回一条整句区间；要是拿它当「第一个词」，第一个词会亮一整句。
/// 返回 null = 这一拍不高亮。
int? spokenWordIndex(String text, int start, int end) {
  if (start < 0 || end <= start) return null;
  final spans = wordSpans(text);
  if (spans.isEmpty) return null;
  final range = wordIndexRange(text, start, end);
  if (range == null) return null;
  // `wordIndexRange` 在「区间落在词间空白」时会返回首尾倒置的区间；
  // 这里只取起点（= 下一个词），别把倒置的 end 当成覆盖范围。
  final first = range.start;
  final last = range.end > first ? range.end : first + 1;
  // 整句一个区间（且不止一个词）→ 引擎没给逐词信息，不亮。
  if (first == 0 && last >= spans.length && spans.length > 1) return null;
  return first;
}

/// 把逐词时间戳对齐到 [text] 的词序。
///
/// 规则：按顺序往后找同一个词（归一化后比较）；找不到时用「同位置」的时间戳兜底，
/// 再没有就给 0（宁可不高亮，也不把时间戳错配到别的词上）。
List<WordTiming> alignTimings(String text, List<TimingPart> timings) {
  final spans = wordSpans(text);
  final out = <WordTiming>[];
  var j = 0;
  for (final sp in spans) {
    final key = _normW(sp.text);
    var found = -1;
    for (var k = j; k < timings.length; k++) {
      if (_normW(timings[k].part ?? '') == key) {
        found = k;
        break;
      }
    }
    if (found >= 0) {
      final t = timings[found];
      out.add(WordTiming(start: t.start, end: t.end));
      j = found + 1;
      continue;
    }
    if (j < timings.length) {
      final t = timings[j];
      out.add(WordTiming(start: t.start, end: t.end));
      j++;
      continue;
    }
    out.add(const WordTiming(start: 0, end: 0));
  }
  return out;
}
