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
