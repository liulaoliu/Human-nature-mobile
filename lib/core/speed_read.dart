import 'dart:math' show Random;

import '../models/document.dart' show Sentence;
import 'language.dart' show getSentenceLanguages;
import 'quiz_parts.dart' show blankWord, canonical, normalizeAnswer, shuffleQuiz;
import 'vocab/word.dart' show lemmaOf;
import 'word_select.dart' show wordSpans;

/// 逐句速读：纯逻辑。
///
/// 给一句算「目标阅读时长」（含少量思考余量），超时算「不太理解」，
/// 并挑一道**四选一**的「拷打」题：
/// 优先语言点搭配里的短语，其次生词，最后最长实词。
///
/// 对照 Web 版 `src/core/speedRead.ts`。

/// 默认语速（词/分钟）。
const int defaultWpm = 120;

/// 每句额外给的思考余量（毫秒），避免短句太紧。
const int speedGraceMs = 1500;

/// 目标时长上下限（毫秒）。
const int minTargetMs = 2000;
const int maxTargetMs = 30000;

/// 停用词：挑挖空目标时跳过。
const Set<String> stopWords = <String>{
  'the', 'and', 'that', 'with', 'this', 'from', 'have', 'were', 'which', 'their',
  'about', 'would', 'there', 'these', 'those', 'been', 'into', 'than', 'them',
  'then', 'when', 'what', 'your', 'more', 'some', 'such', 'only', 'also', 'over',
  'because', 'could', 'should', 'other', 'many', 'most', 'much', 'very', 'they',
  'will', 'while', 'where', 'after', 'before', 'between', 'still', 'just',
};

/// 兜底干扰词（真词不够时补）。
const List<String> fallbackWords = <String>[
  'increase', 'reduce', 'demand', 'supply', 'capital', 'emission', 'investment',
  'project', 'capacity', 'policy', 'market', 'energy', 'climate', 'support',
  'target', 'growth', 'source', 'network', 'reform', 'device',
];

final Random _random = Random();

double _defaultRnd() => _random.nextDouble();

/// 词数（按空白切，空串算 0）。
int wordCount(String text) {
  final t = text.trim();
  if (t.isEmpty) return 0;
  return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

/// 速读游标的本机键：`articleKey`（文章标识 + 正文签名）由调用方一次算好。
String speedCursorKey(String articleKey) => 'reader:speedCursor:$articleKey';

/// 目标阅读时长（毫秒）：词数 / WPM + 思考余量，并给上下限。
int targetMs(String text, {int wpm = defaultWpm}) {
  final words = wordCount(text);
  final ms = (words / (wpm < 50 ? 50 : wpm)) * 60000 + speedGraceMs;
  final rounded = ms.round();
  if (rounded < minTargetMs) return minTargetMs;
  if (rounded > maxTargetMs) return maxTargetMs;
  return rounded;
}

/// 句子里的实词（≥4 字母、非停用词）。
List<String> contentWords(String text) {
  final out = <String>[];
  for (final w in wordSpans(text)) {
    final cleaned = w.text.replaceAll(RegExp(r"[^A-Za-z'-]"), '');
    if (cleaned.length >= 4 && !stopWords.contains(cleaned.toLowerCase())) {
      out.add(cleaned);
    }
  }
  return out;
}

/// 挖空目标是怎么挑出来的。
enum SpeedReadVia {
  /// 语言点搭配里的短语。
  phrase,

  /// 这句的生词。
  vocab,

  /// 最长实词兜底。
  word,
}

/// 挖空结果。
class SpeedReadBlank {
  const SpeedReadBlank({required this.blanked, required this.surface, required this.via});

  /// 挖空后的句子（`____` 替换掉目标词）。
  final String blanked;

  /// 命中的原始词形。
  final String surface;

  final SpeedReadVia via;
}

/// 一道四选一拷打题。
class SpeedReadDrill {
  const SpeedReadDrill({
    required this.prompt,
    required this.answer,
    required this.accept,
    required this.via,
    required this.options,
  });

  /// 挖空后的句子（拷打时原文隐藏，只给这句）。
  final String prompt;

  /// 标准答案（原文里的词形）。
  final String answer;

  /// 可接受的写法（归一化后）。
  final List<String> accept;

  final SpeedReadVia via;

  /// 四选一选项（含正确答案，已打乱）。
  final List<String> options;
}

/// 在句子里找目标并挖空。优先语言点搭配里的实词，其次生词，最后最长实词。
SpeedReadBlank? pickTargetBlank(Sentence sentence) {
  final text = sentence.text.trim();
  if (text.isEmpty) return null;

  // 语言点可能是旧的单条 `language`，也可能是 `languages[]`（手动改过之后就走后者）
  final phrases = <String>[
    for (final l in getSentenceLanguages(sentence)) ...?l.phrases,
  ];
  if (phrases.isNotEmpty) {
    for (final p in phrases) {
      final toks = p
          .split(RegExp(r'\s+'))
          .map((t) => t.replaceAll(RegExp(r"[^A-Za-z'-]"), ''))
          .where((t) => t.length >= 4 && !stopWords.contains(t.toLowerCase()))
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final tok in toks) {
        final b = blankWord(text, lemmaOf(tok));
        if (b != null) {
          return SpeedReadBlank(blanked: b.blanked, surface: b.surface, via: SpeedReadVia.phrase);
        }
      }
    }
  }

  for (final v in sentence.vocab) {
    final b = blankWord(text, v.trim());
    if (b != null) {
      return SpeedReadBlank(blanked: b.blanked, surface: b.surface, via: SpeedReadVia.vocab);
    }
  }

  final sorted = contentWords(text)..sort((a, b) => b.length.compareTo(a.length));
  for (final w in sorted) {
    final b = blankWord(text, lemmaOf(w));
    if (b != null) {
      return SpeedReadBlank(blanked: b.blanked, surface: b.surface, via: SpeedReadVia.word);
    }
  }
  return null;
}

/// 挑一道四选一拷打题。
///
/// [pool] 建议传整篇实词（干扰项更像样）。凑不够 3 个干扰项时返回 null
/// （这句就不拷打）。
SpeedReadDrill? pickDrill(
  Sentence sentence, {
  List<String> pool = const <String>[],
  double Function() rnd = _defaultRnd,
}) {
  final chosen = pickTargetBlank(sentence);
  if (chosen == null) return null;
  final answer = chosen.surface;

  final seen = <String>{normalizeAnswer(answer)};
  final cands = <String>[];
  for (final c in <String>[...pool, ...contentWords(sentence.text), ...fallbackWords]) {
    final w = c.trim();
    if (w.isEmpty) continue;
    final k = normalizeAnswer(w);
    if (seen.contains(k)) continue;
    seen.add(k);
    cands.add(w);
  }

  // 优先长度接近的，再打乱取 3 个
  cands.sort((a, b) => (a.length - answer.length).abs().compareTo((b.length - answer.length).abs()));
  final head = cands.length > 15 ? cands.sublist(0, 15) : cands;
  final distractors = shuffleQuiz(head, rnd).take(3).toList();
  if (distractors.length < 3) return null;

  final accept = <String>{normalizeAnswer(answer), lemmaOf(answer)}..remove('');
  return SpeedReadDrill(
    prompt: chosen.blanked,
    answer: answer,
    accept: accept.toList(),
    via: chosen.via,
    options: shuffleQuiz(<String>[answer, ...distractors], rnd),
  );
}

/// 判分：归一化后命中，或忽略连字符 / 撇号 / 空格后一致。
bool checkDrill(SpeedReadDrill drill, String input) {
  final n = normalizeAnswer(input);
  if (n.isEmpty) return false;
  if (drill.accept.contains(n)) return true;
  final c = canonical(n);
  if (c.isEmpty) return false;
  return drill.accept.any((a) => canonical(a) == c);
}

/// 一句的读数。
class SpeedRow {
  const SpeedRow({required this.words, required this.ms, this.slow = false, this.drillOk});

  final int words;
  final int ms;

  /// 是否超时（算「不太理解」）。
  final bool slow;

  /// 拷打结果；没拷打就是 null。
  final bool? drillOk;
}

/// 一次速读的结算。
class SpeedSummary {
  const SpeedSummary({
    required this.count,
    required this.avgWpm,
    required this.slow,
    required this.drillTotal,
    required this.drillCorrect,
  });

  final int count;
  final int avgWpm;
  final int slow;
  final int drillTotal;
  final int drillCorrect;
}

/// 汇总若干句的读数。
SpeedSummary summarize(List<SpeedRow> rows) {
  var words = 0;
  var ms = 0;
  var slow = 0;
  var drillTotal = 0;
  var drillCorrect = 0;
  for (final r in rows) {
    words += r.words;
    ms += r.ms;
    if (r.slow) slow += 1;
    final ok = r.drillOk;
    if (ok != null) {
      drillTotal += 1;
      if (ok) drillCorrect += 1;
    }
  }
  return SpeedSummary(
    count: rows.length,
    avgWpm: ms > 0 ? ((words / ms) * 60000).round() : 0,
    slow: slow,
    drillTotal: drillTotal,
    drillCorrect: drillCorrect,
  );
}
