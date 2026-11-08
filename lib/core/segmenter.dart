/// 切分模块：把清洗后的规范文本，切成段落 + 句子。
///
/// Web 版优先用浏览器原生 `Intl.Segmenter`（语言感知、零依赖），Dart 没有
/// 对应能力，所以这里**只用正则**（就是 Web 版的兜底路径）：
/// 句末标点 + 可选收尾引号/括号之后断句，再用缩写白名单修补。
///
/// id 稳定：段落 `p01` 递增，句子 `s001` 递增，顺序与原文一致。
///
/// 对应 Web 版 `src/core/segmenter.ts`。
library;

import '../models/document.dart';

/// 常见缩写。句尾若是这些词加句点，说明没到句末，要和下句合并。
const Set<String> abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'prof', 'st', 'vs', 'etc', 'no', 'fig', 'al', //
  'e.g', 'i.e', 'u.s', 'u.k', 'u.n', 'inc', 'ltd', 'co', 'jr', 'sr', //
  'gen', 'sen', 'rep', 'gov', 'approx', 'dept', 'est',
};

/// 句间切分点：句末标点（可带一个收尾引号/括号）之后的空白。
///
/// 用 lookbehind 是为了**不把句号切走**：切分点本身只是空白，标点留在上一句末尾。
/// 对应 Web 版的 `/(?<=[.?!]["”')\]]?)\s+/`。
final RegExp _sentenceBreak = RegExp('(?<=[.!?][)\\]}\\"\u201d\u2019\']?)\\s+');

/// 句尾是否是「缩写 + 句点」。
final RegExp _abbrTail = RegExp(r'([A-Za-z](?:[A-Za-z.]*[A-Za-z])?)\.$');

bool endsWithAbbreviation(String s) {
  final m = _abbrTail.firstMatch(s.trimRight());
  if (m == null) return false;
  final word = m.group(1);
  return word != null && abbreviations.contains(word.toLowerCase());
}

/// 把一段切成一串句子，并把缩写造成的误切合回去。
List<String> splitSentences(String paragraph) {
  final out = <String>[];
  for (final raw in paragraph.split(_sentenceBreak)) {
    final seg = raw.trim();
    if (seg.isEmpty) continue;
    if (out.isNotEmpty && endsWithAbbreviation(out.last)) {
      out[out.length - 1] = '${out.last} $seg';
    } else {
      out.add(seg);
    }
  }
  return out;
}

/// 切分结果。
class SegmentResult {
  const SegmentResult({required this.paragraphs, required this.sentences});

  final List<Paragraph> paragraphs;
  final List<Sentence> sentences;

  bool get isEmpty => paragraphs.isEmpty && sentences.isEmpty;
}

final RegExp _blankLine = RegExp(r'\n{2,}');

/// 切分主入口。输入是清洗后的正文（段落之间用空行分隔）。
SegmentResult segment(String cleaned) {
  final paragraphs = <Paragraph>[];
  final sentences = <Sentence>[];
  var p = 0;
  var s = 0;

  for (final para in cleaned.split(_blankLine)) {
    final text = para.trim();
    if (text.isEmpty) continue;
    p += 1;
    final paraId = 'p${p.toString().padLeft(2, '0')}';
    final sentenceIds = <String>[];
    for (final sentenceText in splitSentences(text)) {
      s += 1;
      final id = 's${s.toString().padLeft(3, '0')}';
      sentenceIds.add(id);
      sentences.add(Sentence(id: id, paraId: paraId, text: sentenceText));
    }
    paragraphs.add(Paragraph(id: paraId, sentenceIds: sentenceIds));
  }

  return SegmentResult(paragraphs: paragraphs, sentences: sentences);
}

/// 重新切句后，把旧句子上挂着的分析结果按「句文相同」搬过来。
///
/// 编辑正文要重新切句（[segment] 会新建一批 Sentence 对象），不搬的话
/// 之前粘回来的翻译 / 语法 / 语言点 / 搭配 / 生词 / 时间轴会全部丢掉。
/// 同一句文出现多次时，按出现顺序一一对应。
List<Sentence> carryAnalysis(List<Sentence> previous, List<Sentence> next) {
  final buckets = <String, List<Sentence>>{};
  for (final p in previous) {
    buckets.putIfAbsent(p.text.trim(), () => []).add(p);
  }
  return next.map((s) {
    final bucket = buckets[s.text.trim()];
    if (bucket == null || bucket.isEmpty) return s;
    final src = bucket.removeAt(0);
    return s.copyWith(
      translation: () => src.translation,
      grammarNote: () => src.grammarNote,
      // 语言点也别丢：编辑正文重切句后，AI 分析要跟着同句文搬过来
      language: () => src.language,
      languages: () => src.languages,
      collocations: src.collocations,
      vocab: src.vocab,
      audio: () => src.audio,
      tags: src.tags,
    );
  }).toList();
}
