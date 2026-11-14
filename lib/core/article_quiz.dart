/// 文章级测验：按句子 / 段落出题，考理解与结构（对应 Web `src/core/articleQuiz.ts`）。
///
/// 题型（都是「文章级」，不写 SRS）：
///   - translate    英译中：给英文原句，选正确中文
///   - translate2   中译英：给中文，选正确英文原句
///   - functionWord 功能词填空：挖掉介词 / 冠词 / 连词，选词填回
///   - ordering     句子排序：一段的 3 句打乱，选回原文顺序
///   - grammar      结构 / 语法：给句子，选它真实用到的语法点（依语言点数据）
///   - phraseBlank  词组 / 习语填空：把句中的词组 / 习语挖空，选回去
///
/// 纯函数：可注入 [rnd]，方便单测；不碰界面、不碰存储。
/// 这就是 `quiz.dart` 的 `makeQuestion` 一开头 `if (kind.isArticle) return null`
/// 挡掉的那部分 —— 词级出题器拿不到整篇，文章题必须单独生成。
library;

import '../models/document.dart';
import 'language.dart' show getSentenceLanguages;
import 'quiz.dart';
import 'word_select.dart' show wordSpans;

/// 介词 / 冠词 / 连词（功能词填空的可挖集合）。
const List<String> articlePreps = <String>[
  'of', 'in', 'on', 'at', 'to', 'for', 'with', 'by', 'from', 'into', 'over',
  'under', 'about', 'after', 'before', 'between', 'during', 'against', 'among',
  'through', 'without', 'within', 'across', 'along', 'behind', 'beyond',
  'despite', 'except', 'toward', 'towards', 'upon', 'per', 'via', 'throughout',
  'besides',
];

const List<String> articleArticles = <String>['a', 'an', 'the'];

const List<String> articleConjs = <String>[
  'and', 'but', 'or', 'nor', 'so', 'yet', 'because', 'although', 'though',
  'while', 'whereas', 'if', 'unless', 'since', 'than', 'whether', 'once',
  'until',
];

/// 句子排序的 6 种三句排列（A/B/C）。
const List<List<String>> orderPermutations3 = <List<String>>[
  <String>['A', 'B', 'C'],
  <String>['A', 'C', 'B'],
  <String>['B', 'A', 'C'],
  <String>['B', 'C', 'A'],
  <String>['C', 'A', 'B'],
  <String>['C', 'B', 'A'],
];

/// 从候选里挑 n 个与答案不同的（按归一化去重）。
List<String> _pickN(String answer, List<String> pool, int n, double Function() rnd) {
  final seen = <String>{normalizeAnswer(answer)};
  final out = <String>[];
  for (final p in shuffleQuiz(pool, rnd)) {
    final k = normalizeAnswer(p);
    if (k.isEmpty || !seen.add(k)) continue;
    out.add(p);
    if (out.length >= n) break;
  }
  return out;
}

QuizQuestion _mc({
  required String id,
  required String itemId,
  required QuizKind kind,
  required String prompt,
  String? context,
  String? translation,
  required String answer,
  required List<String> options,
  required double Function() rnd,
}) {
  return QuizQuestion(
    id: id,
    itemId: itemId,
    lemma: '',
    kind: kind,
    source: 'article',
    word: '',
    prompt: prompt,
    context: context,
    translation: translation,
    options: shuffleQuiz(options, rnd),
    answer: answer,
    accept: <String>[normalizeAnswer(answer)],
  );
}

/// 该句所有语言点里的语法要点（合并；兼容多条）。
String _grammarOf(Sentence s) => getSentenceLanguages(s)
    .map((l) => (l.grammar ?? '').trim())
    .where((x) => x.isNotEmpty)
    .join('；');

/// 生成文章级题目。
///
/// [kinds] 为空 / 不传时按默认五种（不含 phraseBlank，与 Web 一致）。
/// [rnd] 默认固定种子随机源（`quiz.dart` 的 `shuffleQuiz` 默认），测试可注入。
List<QuizQuestion> buildArticleQuestions(
  List<Sentence> sentences, {
  List<QuizKind> kinds = const <QuizKind>[],
  double Function()? rnd,
}) {
  final random = rnd ?? _defaultRnd;
  final want = kinds.isEmpty
      ? <QuizKind>{
          QuizKind.translate,
          QuizKind.translate2,
          QuizKind.functionWord,
          QuizKind.ordering,
          QuizKind.grammar,
        }
      : kinds.toSet();
  final out = <QuizQuestion>[];

  final withText = sentences.where((s) => s.text.trim().isNotEmpty).toList();
  final withTr = withText
      .where((s) => (s.translation ?? '').trim().isNotEmpty)
      .toList();

  // ---------- 英译中 / 中译英 ----------
  if (want.contains(QuizKind.translate) || want.contains(QuizKind.translate2)) {
    final allTr = <String>{
      for (final s in withTr) (s.translation ?? '').trim(),
    }.toList();
    final allText = <String>{
      for (final s in withText) s.text.trim(),
    }.toList();
    for (final s in withTr) {
      final tr = (s.translation ?? '').trim();
      if (want.contains(QuizKind.translate)) {
        final dist = _pickN(tr, allTr, 3, random);
        if (dist.length >= 3) {
          out.add(_mc(
            id: 'article:translate:${s.id}',
            itemId: s.id,
            kind: QuizKind.translate,
            prompt: s.text.trim(),
            context: s.text.trim(),
            translation: tr,
            answer: tr,
            options: <String>[tr, ...dist],
            rnd: random,
          ));
        }
      }
      if (want.contains(QuizKind.translate2)) {
        final en = s.text.trim();
        final dist = _pickN(en, allText, 3, random);
        if (dist.length >= 3) {
          out.add(_mc(
            id: 'article:translate2:${s.id}',
            itemId: s.id,
            kind: QuizKind.translate2,
            prompt: tr,
            context: en,
            translation: tr,
            answer: en,
            options: <String>[en, ...dist],
            rnd: random,
          ));
        }
      }
    }
  }

  // ---------- 功能词填空 ----------
  if (want.contains(QuizKind.functionWord)) {
    final func = <String>{
      ...articlePreps,
      ...articleArticles,
      ...articleConjs,
    };
    for (final s in withText) {
      final cands = wordSpans(s.text)
          .where((w) => func.contains(w.text.toLowerCase()))
          .toList(growable: false);
      if (cands.isEmpty) continue;
      final pick = cands[(random() * cands.length).floor()];
      final lower = pick.text.toLowerCase();
      final cat = articleArticles.contains(lower)
          ? articleArticles
          : articleConjs.contains(lower)
              ? articleConjs
              : articlePreps;
      final dist = _pickN(lower, cat, 3, random);
      if (dist.length < 3) continue;
      final blanked =
          '${s.text.substring(0, pick.start)}____${s.text.substring(pick.end)}';
      out.add(_mc(
        id: 'article:functionWord:${s.id}:${pick.start}',
        itemId: s.id,
        kind: QuizKind.functionWord,
        prompt: blanked,
        context: s.text,
        translation: (s.translation ?? '').trim().isEmpty
            ? null
            : (s.translation ?? '').trim(),
        answer: lower,
        options: <String>[lower, ...dist],
        rnd: random,
      ));
    }
  }

  // ---------- 句子排序（按段落取前 3 句） ----------
  if (want.contains(QuizKind.ordering)) {
    final byPara = <String, List<Sentence>>{};
    for (final s in withText) {
      (byPara[s.paraId] ??= <Sentence>[]).add(s);
    }
    for (final entry in byPara.entries) {
      final arr = entry.value;
      if (arr.length < 3) continue;
      final three = arr.sublist(0, 3);
      // 展示顺序：position -> 原句下标
      final perm = shuffleQuiz(<int>[0, 1, 2], random);
      final letterOf = <int, String>{};
      const letters = <String>['A', 'B', 'C'];
      for (var pos = 0; pos < perm.length; pos++) {
        letterOf[perm[pos]] = letters[pos];
      }
      final presented = <String>[
        for (var pos = 0; pos < perm.length; pos++)
          '${letters[pos]}. ${three[perm[pos]].text.trim()}',
      ];
      final correct = <String>[
        for (var i = 0; i < 3; i++) letterOf[i]!,
      ].join(' ');
      final all = <String>[
        for (final p in orderPermutations3) p.join(' '),
      ].where((x) => x != correct).toList();
      final dist = _pickN(correct, all, 3, random);
      if (dist.length < 3) continue;
      out.add(_mc(
        id: 'article:ordering:${entry.key}',
        itemId: entry.key,
        kind: QuizKind.ordering,
        prompt: '把下面三句排回原文顺序：\n${presented.join('\n')}',
        context: <String>[
          for (var i = 0; i < 3; i++) three[i].text.trim(),
        ].join(' '),
        answer: correct,
        options: <String>[correct, ...dist],
        rnd: random,
      ));
    }
  }

  // ---------- 词组 / 习语填空（依语言点数据） ----------
  if (want.contains(QuizKind.phraseBlank)) {
    // 全篇的词组 / 习语池（当干扰项）
    final pool = <String>[];
    for (final s in sentences) {
      for (final l in getSentenceLanguages(s)) {
        for (final p in <String>[
          ...(l.phrases ?? const <String>[]),
          ...(l.idioms ?? const <String>[]),
        ]) {
          final t = p.trim();
          if (t.isNotEmpty &&
              !pool.any((x) => normalizeAnswer(x) == normalizeAnswer(t))) {
            pool.add(t);
          }
        }
      }
    }
    for (final s in withText) {
      final chunks = <String>[];
      for (final l in getSentenceLanguages(s)) {
        for (final p in <String>[
          ...(l.phrases ?? const <String>[]),
          ...(l.idioms ?? const <String>[]),
        ]) {
          final t = p.trim();
          if (t.isNotEmpty &&
              !chunks.any((x) => normalizeAnswer(x) == normalizeAnswer(t))) {
            chunks.add(t);
          }
        }
      }
      for (final chunk in chunks) {
        final idx = s.text.toLowerCase().indexOf(chunk.toLowerCase());
        if (idx < 0) continue; // 词组没原样出现在句子里 → 挖不出空
        final dist = _pickN(chunk, pool, 3, random);
        if (dist.length < 3) continue;
        final blanked =
            '${s.text.substring(0, idx)}____${s.text.substring(idx + chunk.length)}';
        out.add(_mc(
          id: 'article:phraseBlank:${s.id}:$idx',
          itemId: s.id,
          kind: QuizKind.phraseBlank,
          prompt: blanked,
          context: s.text.trim(),
          translation: (s.translation ?? '').trim().isEmpty
              ? null
              : (s.translation ?? '').trim(),
          answer: chunk,
          options: <String>[chunk, ...dist],
          rnd: random,
        ));
      }
    }
  }

  // ---------- 结构 / 语法（依语言点数据） ----------
  if (want.contains(QuizKind.grammar)) {
    final withGram = withText.where((s) => _grammarOf(s).isNotEmpty).toList();
    final allGram = <String>{
      for (final s in withGram) _grammarOf(s),
    }.toList();
    for (final s in withGram) {
      final answer = _grammarOf(s);
      final dist = _pickN(answer, allGram, 3, random);
      if (dist.isEmpty) continue;
      out.add(_mc(
        id: 'article:grammar:${s.id}',
        itemId: s.id,
        kind: QuizKind.grammar,
        prompt: s.text.trim(),
        context: s.text.trim(),
        answer: answer,
        options: <String>[answer, ...dist],
        rnd: random,
      ));
    }
  }

  return out;
}

/// 默认随机源（固定种子，测试可注入）。
double _defaultRnd() {
  _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF;
  return _seed / 0x7FFFFFFF;
}

int _seed = 20261113;
