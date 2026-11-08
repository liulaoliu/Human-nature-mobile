/// 离线词典（数据来自 ECDICT，构建脚本预处理成两个紧凑 TSV）。
///
/// 纯逻辑：解析 TSV、查词、词形→原形、「是否超出某词汇水平」。
/// **不碰文件系统**：读 TSV 由 `data/` 层负责，这里只吃字符串，便于单测。
///
/// 对应 Web 版 `src/core/ecdict.ts`。
library;

import '../models/vocab.dart';
import 'article_vocab.dart' show kindOfItem;
import 'entry_kind.dart';
import 'vocab/word.dart';

/// 一个词条。
class EcdictEntry {
  const EcdictEntry({
    required this.word,
    required this.phonetic,
    required this.pos,
    required this.en,
    required this.zh,
    required this.tag,
    required this.collins,
    required this.oxford,
    required this.bnc,
    required this.frq,
  });

  /// 原词形（显示用）。
  final String word;
  final String phonetic;
  final String pos;

  /// 英文释义（可能多行，用 `\n` 连接，带 n./v./a. 前缀）。
  final String en;

  /// 中文释义（可能多行）。
  final String zh;

  /// 分级标签，空格分隔：zk gk cet4 cet6 ky toefl ielts gre。
  final String tag;
  final int collins;
  final int oxford;
  final int bnc;
  final int frq;

  @override
  String toString() => 'EcdictEntry($word)';
}

/// 词典三张表。
class Ecdict {
  const Ecdict({required this.entries, required this.forms, required this.near});

  /// lower(word) → 词条（仅常用词）。
  final Map<String, EcdictEntry> entries;

  /// lower(词形) → lower(原形)。
  final Map<String, String> forms;

  /// lower(word) → 拼写近邻候选（用于本地生成混淆项）。
  final Map<String, List<String>> near;
}

/// 还原转义：`\n` → 换行、`\t` → 制表、`\\` → 反斜杠。
///
/// 顺序与 Web 版一致：先换行、再制表、最后反斜杠，避免 `\\n` 被二次展开。
String _unesc(String s) =>
    s.replaceAll(r'\n', '\n').replaceAll(r'\t', '\t').replaceAll(r'\\', r'\');

int _intOf(String? raw) {
  if (raw == null || raw.isEmpty) return 0;
  return num.tryParse(raw)?.toInt() ?? 0;
}

/// 解析构建脚本产出的两个 TSV（`nearTsv` 可选）。
Ecdict parseEcdict(String wordsTsv, String formsTsv, [String nearTsv = '']) {
  final entries = <String, EcdictEntry>{};

  for (final line in wordsTsv.split('\n')) {
    if (line.isEmpty) continue;
    final c = line.split('\t');
    if (c.length < 2 || c[0] == 'word') continue;
    final word = c[0];
    String at(int i) => i < c.length ? _unesc(c[i]) : '';
    entries[word.toLowerCase()] = EcdictEntry(
      word: word,
      phonetic: at(1),
      pos: at(2),
      en: at(3),
      zh: at(4),
      tag: at(5),
      collins: _intOf(c.length > 6 ? c[6] : null),
      oxford: _intOf(c.length > 7 ? c[7] : null),
      bnc: _intOf(c.length > 8 ? c[8] : null),
      frq: _intOf(c.length > 9 ? c[9] : null),
    );
  }

  final forms = <String, String>{};
  for (final line in formsTsv.split('\n')) {
    if (line.isEmpty) continue;
    final i = line.indexOf('\t');
    if (i <= 0) continue;
    forms[line.substring(0, i)] = line.substring(i + 1);
  }

  final near = <String, List<String>>{};
  for (final line in nearTsv.split('\n')) {
    if (line.isEmpty) continue;
    final i = line.indexOf('\t');
    if (i <= 0) continue;
    near[line.substring(0, i)] =
        line.substring(i + 1).split(',').where((s) => s.isNotEmpty).toList();
  }

  return Ecdict(entries: entries, forms: forms, near: near);
}

/// 查词结果。
class ResolvedWord {
  const ResolvedWord({required this.lemma, required this.entry});

  final String lemma;
  final EcdictEntry entry;
}

/// 查词：按词形先还原原形，再取词条。查不到为 null。
ResolvedWord? resolveWord(Ecdict dict, String word) {
  final lower = word.trim().toLowerCase();
  if (lower.isEmpty) return null;
  final lemma = dict.forms[lower] ?? lower;
  final entry = dict.entries[lemma] ?? dict.entries[lower];
  if (entry == null) return null;
  return ResolvedWord(lemma: lemma, entry: entry);
}

/// 只取原形（词典里没有则返回 null）。
String? dictLemmaOf(Ecdict dict, String word) {
  final lower = word.trim().toLowerCase();
  if (lower.isEmpty) return null;
  final lemma = dict.forms[lower];
  if (lemma != null) return lemma;
  return dict.entries.containsKey(lower) ? lower : null;
}

/// 这个词条能不能交给**单词**词典做词形归并。
///
/// 只有「单个英文单词」才算：词组 / 习语 / 用法笔记不做 —— 词典里没有它们的词形表，
/// 而且把它们并进某个单词后，「语言点自动收藏」下一轮又会加回来，两边来回打架、
/// 词库数量就会跳（2026-10 那批「生词在 7694/7696 之间跳」）。
bool isDictWord(VocabItem item) {
  if (kindOf(kind: kindOfItem(item), word: item.word) != VocabKind.word) return false;
  final w = normalizeWord(item.word);
  return w.isNotEmpty && !w.contains(' ');
}

/// 一条「词形 → 原形」的修正。
class LemmaPair {
  const LemmaPair({required this.from, required this.to});

  final String from;
  final String to;

  @override
  bool operator ==(Object other) =>
      other is LemmaPair && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'LemmaPair($from → $to)';
}

/// 由词库 + 词典算出「词形 → 原形」的修正对（幂等）。只处理单个英文单词。
List<LemmaPair> dictLemmaPairs(
  Ecdict dict,
  List<VocabItem> items, {
  bool skipLocked = false,
}) {
  final out = <LemmaPair>[];
  for (final it in items) {
    if (skipLocked &&
        (it.status == VocabStatus.edited || it.status == VocabStatus.mastered)) {
      continue;
    }
    if (!isDictWord(it)) continue;
    final to = dictLemmaOf(dict, it.word);
    if (to == null || normalizeWord(it.word) == to) continue;
    out.add(LemmaPair(from: it.word, to: to));
  }
  return out;
}

/// 一个拼写近邻候选。
class DictConfusable {
  const DictConfusable({required this.word, this.meaning});

  final String word;
  final String? meaning;
}

/// 用词典给一个词挑拼写近邻（形近、义不同）作选择题干扰项。
List<DictConfusable> dictConfusables(Ecdict dict, String word, {int n = 3}) {
  final lemma = dictLemmaOf(dict, word) ?? word.trim().toLowerCase();
  final cands = dict.near[lemma] ?? const <String>[];
  final out = <DictConfusable>[];
  for (final c in cands) {
    final e = dict.entries[c];
    if (e == null) continue;
    final meaning = firstLine(e.zh);
    out.add(DictConfusable(word: e.word, meaning: meaning.isEmpty ? null : meaning));
    if (out.length >= n) break;
  }
  return out;
}

/// 词汇水平档位。
enum EcdictLevel { cet4, cet6, kaoyan, ielts, ielts65 }

/// 各档「以内」包含哪些标签（超出这些即算超纲）。
const Map<EcdictLevel, List<String>> levelWithin = <EcdictLevel, List<String>>{
  EcdictLevel.cet4: <String>['zk', 'gk', 'cet4'],
  EcdictLevel.cet6: <String>['zk', 'gk', 'cet4', 'cet6'],
  EcdictLevel.kaoyan: <String>['zk', 'gk', 'cet4', 'cet6', 'ky'],
  EcdictLevel.ielts: <String>['zk', 'gk', 'cet4', 'cet6', 'ielts'],
  EcdictLevel.ielts65: <String>['zk', 'gk', 'cet4', 'cet6', 'ielts', 'toefl'],
};

/// 分级判定结果。
enum LevelVerdict {
  /// 超纲（该留）。
  above,

  /// 在档内 / 属于基础常见词（不该留）。
  within,

  /// 词典里是「太生僻」（无标签 / 无频次）。
  rare,

  /// 词典里根本没收录 —— **不能因此判定它不超纲**。
  unknown,
}

/// 无级别标签的词，用词频排名兜底：排名 ≤ 这个数（越大越生僻）算「常见词」，不算超纲。
///
/// 治的是 `entirely / john / killer` 这类 ECDICT 漏标的基本词。
const int coreFreqRank = 5000;

/// 判定一个词相对某词汇水平的位置。
LevelVerdict levelVerdict(Ecdict dict, String word, EcdictLevel level) {
  final hit = resolveWord(dict, word);
  if (hit == null) return LevelVerdict.unknown;
  final e = hit.entry;
  final tags = e.tag.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (levelWithin[level]!.any(tags.contains)) return LevelVerdict.within;
  // 无级别标签 → 用词频排名兜底（ECDICT 标签不全，entirely 这类基础词常没标签）。
  if (tags.isEmpty) {
    final ranks = <int>[e.bnc, e.frq].where((n) => n > 0).toList();
    if (ranks.isNotEmpty && ranks.reduce((a, b) => a < b ? a : b) <= coreFreqRank) {
      return LevelVerdict.within;
    }
  }
  final common = tags.isNotEmpty || e.collins >= 1 || e.oxford == 1 || e.frq > 0 || e.bnc > 0;
  return common ? LevelVerdict.above : LevelVerdict.rare;
}

/// 是否「超出某词汇水平」（词典里有、且不属于该档、且是常用词）。
bool isAboveLevel(Ecdict dict, String word, EcdictLevel level) =>
    levelVerdict(dict, word, level) == LevelVerdict.above;

final RegExp _glossBreak = RegExp(r'\\n|\n');

/// 首行非空文本（ECDICT 的中英释义都是多行）。转义 `\n` 与真换行都切。
String firstLine(String s) {
  for (final line in s.split(_glossBreak)) {
    final t = line.trim();
    if (t.isNotEmpty) return t;
  }
  return '';
}

/// 释义行开头的词性标记 → 粗类（`vt.`/`vi.`/`t.` 都算动词，`s.` 是 WordNet 的形容词卫星）。
final List<(RegExp, String)> _linePosRules = <(RegExp, String)>[
  (RegExp(r'^(?:n|noun)\.?\s', caseSensitive: false), 'n'),
  (RegExp(r'^(?:v|vt|vi|verb|t)\.?\s', caseSensitive: false), 'v'),
  (RegExp(r'^(?:a|adj|s|satellite)\.?\s', caseSensitive: false), 'adj'),
  (RegExp(r'^(?:ad|adv|adverb)\.?\s', caseSensitive: false), 'adv'),
  (RegExp(r'^(?:prep|preposition)\.?\s', caseSensitive: false), 'prep'),
];

String _posClass(String pos) {
  final p = normalizePos(pos);
  if (p.isEmpty) return '';
  for (final (re, cls) in _linePosRules) {
    if (re.hasMatch('$p ')) return cls;
  }
  return '';
}

/// 按词性挑一条中文释义（挑不到再退回第一行）。
///
/// 为什么要挑：ECDICT 的释义是多行的，每行自带词性标记（`vow` → `n. 誓约` /
/// `vi. 起誓` / `vt. 立誓`），而词性是从 M-W / 词典 pos 列拿的（`vow` 是动词）。
/// 只取第一行就会出现「v. n. 誓约, 誓言」这种卡上自相矛盾的词条（2026-10-22 那批）。
String glossForPos(String zh, String pos) {
  final cls = _posClass(pos);
  if (cls.isEmpty) return firstLine(zh);
  // 数据里可能是真换行，也可能是构建脚本留下来的转义 `\n`，两种都切开。
  for (final line in zh.split(_glossBreak)) {
    final t = line.trim();
    if (t.isEmpty) continue;
    for (final (re, c) in _linePosRules) {
      if (re.hasMatch(t) && c == cls) return t;
    }
  }
  return firstLine(zh);
}

/// 连字符复合词的词性（词典查不到整词时的兜底）。
///
/// 为什么需要：`self-described` / `taxpayer-funded` / `world-leading` / `50-odd` 这类词
/// ECDICT 一条都没收录，于是卡上是「只有一句中文释义，没有词性也没有英英」，
/// 语法标记、复习题型都拿不到词性。复合词的**末段**决定了整个词的词性，按后缀就能判。
///
/// 只看末段、只认明确的后缀 —— `waiting-times`（末段 times）这类判不出就返回 null，
/// 宁可没有词性，也不要把名词短语标成形容词。
final List<(RegExp, String)> _compoundSuffix = <(RegExp, String)>[
  (RegExp(r'(?:ed|ing)$', caseSensitive: false), 'adj.'),
  (RegExp(r'(?:less|ful|ous|ive|able|ible|ant|ent|al)$', caseSensitive: false), 'adj.'),
  (RegExp(r'(?:like|free|made|blind|proof|wide|odd|worthy)$', caseSensitive: false), 'adj.'),
  (RegExp(r'ly$', caseSensitive: false), 'adv.'),
];

final RegExp _lettersOnly = RegExp(r'^[a-z]+$', caseSensitive: false);

String? guessCompoundPos(String? word) {
  final w = (word ?? '').trim();
  if (!w.contains('-')) return null;
  final segs = w.split('-').where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final last = segs.last;
  if (last.length < 3 || !_lettersOnly.hasMatch(last)) return null;
  for (final (re, pos) in _compoundSuffix) {
    if (re.hasMatch(last)) return pos;
  }
  return null;
}

final RegExp _wordRun = RegExp(r"[A-Za-z][A-Za-z'-]*");
final RegExp _allCaps = RegExp(r'^[A-Z]{2,}$');
final RegExp _startsUpper = RegExp('^[A-Z]');
final RegExp _sentencePunct = RegExp(r'''[.!?\u2026\u3002\uff01\uff1f"'\u201c\u201d\u2018\u2019)\]\u3011\uff09]''');
final RegExp _isSpace = RegExp(r'\s');

/// 这个位置是不是「句首」（前一个非空白字符是句末标点/引号，或文本开头）。
bool _isSentenceStart(String text, int index) {
  var i = index - 1;
  while (i >= 0 && _isSpace.hasMatch(text[i])) {
    i--;
  }
  if (i < 0) return true;
  return _sentencePunct.hasMatch(text[i]);
}

/// 从一段英文里挑「超出某水平」的词（按出现顺序、去重、返回原形）。纯本地，不用 AI。
///
/// 会跳过**句中大写**的词（`Trump` / `Islamic` / `CIA` 这类专有名词），
/// 但句首大写照常收（那可能只是句首字母大写）。
List<String> pickAboveLevelWords(
  Ecdict dict,
  String text,
  EcdictLevel level, {
  int max = 40,
}) {
  final seen = <String>{};
  final out = <String>[];
  for (final m in _wordRun.allMatches(text)) {
    final surface = m[0]!;
    final lower = surface.toLowerCase();
    if (!seen.add(lower)) continue;
    // 句中大写 → 多半是专有名词，跳过；全大写缩写（CIA / NATO）也跳过。
    if (_allCaps.hasMatch(surface)) continue;
    if (_startsUpper.hasMatch(surface) && !_isSentenceStart(text, m.start)) continue;
    final hit = resolveWord(dict, surface);
    if (hit == null) continue;
    if (hit.lemma.length < 3) continue;
    if (!isAboveLevel(dict, surface, level)) continue;
    if (out.contains(hit.lemma)) continue;
    out.add(hit.lemma);
    if (out.length >= max) break;
  }
  return out;
}
