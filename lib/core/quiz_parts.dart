/// 出题用的「题干素材」：答案归一化 / 挖空 / 干扰项 / 语法标记 / 洗牌。
///
/// 从 `quiz.dart` 抽出来的原因：这些都是无状态纯函数，跟「题型有哪些」「怎么判分」
/// 不是一件事；`quiz.dart` 里 `makeQuestion` 的分支已经够长，素材工具混在里面
/// 很难找。这里只管「把词条变成可考的题干与选项」，不判分、不碰界面。
library;

import '../models/vocab.dart';
import 'vocab/word.dart';
import 'word_select.dart';

/// 填空题的「形状提示」：把字母/数字换成下划线，保留空格、连字符、撇号。
/// 例如 `bad-temperedly` → `___-___________`，`run a business` → `___ _ ________`。
/// 只暗示长度（几个字母、几个词），不泄露任何字母。
String maskAnswer(String answer) => answer.replaceAll(RegExp('[A-Za-z0-9]'), '_');

final RegExp _leadingPunct = RegExp('^[.!?,;:"\'“”‘’()\\[\\]{}]+');
final RegExp _trailingPunct = RegExp('[.!?,;:"\'“”‘’()\\[\\]{}]+\$');
final RegExp _ws = RegExp(r'\s+');

/// 归一化作答：小写、去首尾标点、压缩空白。
String normalizeAnswer(String s) => s
    .trim()
    .toLowerCase()
    .replaceFirst(_leadingPunct, '')
    .replaceFirst(_trailingPunct, '')
    .replaceAll(_ws, ' ');

/// 只留字母数字（用于宽容比较：忽略连字符、撇号、空格）。
String canonical(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// 按答案的标点给输入「补全」连字符 / 撇号：
/// 只要已输入的字母序列是答案字母序列的前缀，就把答案里对应的
/// `-` / `'` 自动带上（bad → bad-t → bad-temperedly）。
/// 这样连字符词、缩写不用手打连接符。
String formatAnswerInput(String raw, String answer) {
  final typed = canonical(raw);
  if (typed.isEmpty) return raw;
  if (!canonical(answer).startsWith(typed)) return raw;
  var count = 0;
  for (var i = 0; i < answer.length; i++) {
    final ch = answer[i];
    if (RegExp('[a-z0-9]', caseSensitive: false).hasMatch(ch)) {
      count += 1;
      if (count == typed.length) return answer.substring(0, i + 1);
    }
  }
  return raw;
}

/// 在 [text] 里找目标词并按 lemma 归位，返回挖空后的文本与命中的原始词形。
/// 找不到返回 null。短语（含空格）按整段子串匹配。
({String blanked, String surface})? blankWord(String text, String lemma) {
  if (text.isEmpty || lemma.isEmpty) return null;
  if (lemma.contains(' ')) {
    final idx = text.toLowerCase().indexOf(lemma.toLowerCase());
    if (idx < 0) return null;
    final surface = text.substring(idx, idx + lemma.length);
    return (
      blanked: '${text.substring(0, idx)}____${text.substring(idx + lemma.length)}',
      surface: surface,
    );
  }
  for (final w in wordSpans(text)) {
    if (w.text.length > 1 && lemmaOf(w.text) == lemma) {
      return (blanked: '${text.substring(0, w.start)}____${text.substring(w.end)}', surface: w.text);
    }
  }
  return null;
}

List<String> baseAccept(VocabItem it, String surface) {
  final set = <String>{normalizeAnswer(surface), normalizeAnswer(it.word), it.lemma}..remove('');
  return set.toList();
}

/// 两个释义是否「近义/包含」（去标点后相等或互为子串）。
/// 用来剔掉「微调 / 微调，调整」这类会造成多个正确答案的干扰项。
bool meaningOverlaps(String a, String b) {
  String strip(String s) => normalizeAnswer(s).replaceAll(RegExp('[，,；;、\\s。.!?！？]+'), '');
  final x = strip(a);
  final y = strip(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x == y || x.contains(y) || y.contains(x);
}

/// 形近度打分：越小越像（首字母相同、共同前缀长、长度接近）。
int similarScore(String a, String b) {
  final al = a.toLowerCase();
  final bl = b.toLowerCase();
  var s = (al.length - bl.length).abs();
  if (al.isNotEmpty && bl.isNotEmpty && al[0] == bl[0]) s -= 2;
  var p = 0;
  while (p < al.length && p < bl.length && al[p] == bl[p]) {
    p += 1;
  }
  s -= p;
  return s;
}

/// 从候选词里挑 n 个与词条形近/音近的干扰项（优先 AI 混淆项，再补生词本）。
List<String> pickDistractors(
  VocabItem it,
  List<VocabItem> pool,
  int n, [
  double Function() rnd = _defaultRnd,
]) {
  final word = it.word.trim();
  final seen = <String>{word.toLowerCase()};
  final out = <String>[];
  // 优先用 AI 生成的易混词（跳过与目标近义的，否则选择题有多个答案）
  for (final c in it.confusables ?? const <VocabConfusable>[]) {
    final w = c.word.trim();
    if (w.isEmpty || seen.contains(w.toLowerCase())) continue;
    final m = c.meaning;
    if (m != null && m.isNotEmpty && meaningOverlaps(m, it.meaning ?? '')) continue;
    seen.add(w.toLowerCase());
    out.add(w);
    if (out.length >= n) return out;
  }
  final cands = shuffleQuiz(
    pool.where((x) => x.word.trim().isNotEmpty && !seen.contains(x.word.trim().toLowerCase())).toList(),
    rnd,
  );
  cands.sort((a, b) => similarScore(word, a.word) - similarScore(word, b.word));
  for (final c in cands) {
    final w = c.word.trim();
    if (seen.contains(w.toLowerCase())) continue;
    seen.add(w.toLowerCase());
    out.add(w);
    if (out.length >= n) break;
  }
  return out;
}

/// 从候选词里挑 n 个中文释义作干扰项（优先 AI 混淆项，再补生词本）。
List<String> pickMeaningDistractors(
  VocabItem it,
  List<VocabItem> pool,
  int n, [
  double Function() rnd = _defaultRnd,
]) {
  final seen = <String>{normalizeAnswer(it.meaning ?? '')};
  final out = <String>[];
  // 与目标释义近义 / 与已选干扰项近义 → 不用
  bool tooClose(String m) => meaningOverlaps(m, it.meaning ?? '') || out.any((o) => meaningOverlaps(m, o));
  for (final c in it.confusables ?? const <VocabConfusable>[]) {
    final m = (c.meaning ?? '').trim();
    if (m.isEmpty) continue;
    final key = normalizeAnswer(m);
    if (key.isEmpty || seen.contains(key) || tooClose(m)) continue;
    seen.add(key);
    out.add(m);
    if (out.length >= n) return out;
  }
  for (final c in shuffleQuiz(pool, rnd)) {
    final m = (c.meaning ?? '').trim();
    if (m.isEmpty) continue;
    final key = normalizeAnswer(m);
    if (key.isEmpty || seen.contains(key) || tooClose(m)) continue;
    seen.add(key);
    out.add(m);
    if (out.length >= n) break;
  }
  return out;
}

/// 该词可练的「词块」：用法 + 词组（去空、去重、去掉等于词本身的）。
List<String> chunkList(VocabItem it) {
  final word = it.word.trim().toLowerCase();
  final out = <String>[];
  for (final c in <String>[...it.usage, ...?(it.phrases)]) {
    final t = c.trim();
    if (t.isEmpty || t.toLowerCase() == word) continue;
    if (!out.any((x) => x.toLowerCase() == t.toLowerCase())) out.add(t);
  }
  return out;
}

/// 常见介词 / 小品词（做填空干扰项）。
const List<String> particles = <String>[
  'on', 'in', 'at', 'of', 'to', 'for', 'with', 'from', 'about', 'into', 'over', //
  'by', 'up', 'out', 'down', 'off', 'away', 'against', 'upon', 'through', 'after', 'under', 'across', //
];

/// 把搭配里最后一个介词/小品词挖空（run out of → run out ____）。没有则返回 null。
({String blanked, String particle})? blankParticle(String collocation) {
  final spans = wordSpans(collocation);
  for (var i = spans.length - 1; i >= 0; i--) {
    final w = spans[i];
    if (particles.contains(w.text.toLowerCase())) {
      return (
        blanked: '${collocation.substring(0, w.start)}____${collocation.substring(w.end)}',
        particle: w.text,
      );
    }
  }
  return null;
}

/// 语法标记成对题（可数/不可数、及物/不及物、可分级/不可分级）。
const List<({String a, String b, String label})> markPairs = <({String a, String b, String label})>[
  (a: '可数', b: '不可数', label: '这个名词（此义）可数吗？'),
  (a: '及物', b: '不及物', label: '这个动词（此义）及物吗？（要不要跟宾语）'),
  (a: '可分级', b: '不可分级', label: '这个形容词可分级吗？（能不能用 more/most 比较）'),
];

/// 由语法标记生成一道「判断」题（兼类 / 无标记 → 没有唯一答案，返回 null）。
({String label, String answer, List<String> options})? markQuestion(VocabItem it) {
  final marks = it.grammarMarks ?? const <String>[];
  for (final p in markPairs) {
    final hasA = marks.contains(p.a);
    final hasB = marks.contains(p.b);
    if (hasA == hasB) continue;
    return (label: p.label, answer: hasA ? p.a : p.b, options: <String>[p.a, p.b]);
  }
  return null;
}

int _seed = 20260101;

/// 默认随机源（测试里一律注入固定序列，不要用这个）。
double _defaultRnd() {
  _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF;
  return _seed / 0x7FFFFFFF;
}

/// Fisher–Yates 洗牌（可注入随机源，便于测试）。
List<T> shuffleQuiz<T>(List<T> arr, [double Function() rnd = _defaultRnd]) {
  final a = <T>[...arr];
  for (var i = a.length - 1; i > 0; i--) {
    final j = (rnd() * (i + 1)).floor();
    final tmp = a[i];
    a[i] = a[j];
    a[j] = tmp;
  }
  return a;
}
