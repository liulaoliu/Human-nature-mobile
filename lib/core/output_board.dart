/// 产出看板：把**产出性**学习（词块 / 搭配 / 习语 / 仿写 / 复述）量化成看得见的分数。
///
/// 为什么单开一个：泛读（速读）练的是「接受性理解」，光通读容易「自我感动」；
/// 真正决定水平的是**产出**和**词块**。这里把这几项都算成 0–100 的数字，权重也
/// 偏向产出，避免「读得多但说不出」。
///
/// 纯函数，零 IO。对应 Web 版 `src/core/output.ts`（168 行），逐条照搬。
library;

import 'kind_stats.dart';

/// 产出看板的输入。
class OutputInput {
  const OutputInput({
    this.chunkStats = const KindStat(),
    this.grammarStats = const KindStat(),
    this.words = const OutputWords(),
    this.writes = const OutputWrites(),
    this.retells = const OutputRetells(),
    this.streak = 0,
  });

  /// 词块类题型（搭配填空 / 搭配默写 / 介词填空 / 习语填空）的总计。
  final KindStat chunkStats;

  /// 语言点类题型（词组/习语填空 / 结构语法 / 功能词 / 排序 / 翻译）的总计。
  final KindStat grammarStats;

  /// 本篇生词：总数 / 有词块 / 学过 / 稳定。
  final OutputWords words;

  /// 仿写：条数 + 平均分（0–100，没批改过则 null）。
  final OutputWrites writes;

  /// 复述：条数 + 总词数。
  final OutputRetells retells;

  /// 连续学习天数。
  final int streak;
}

/// 本篇生词的四个数。
class OutputWords {
  const OutputWords({this.total = 0, this.withChunks = 0, this.studied = 0, this.stable = 0});

  final int total;
  final int withChunks;
  final int studied;
  final int stable;
}

/// 仿写：条数 + 均分（0–100，没批改过是 null）。
class OutputWrites {
  const OutputWrites({this.count = 0, this.avgScore});

  final int count;
  final double? avgScore;
}

/// 复述：条数 + 总词数。
class OutputRetells {
  const OutputRetells({this.count = 0, this.words = 0});

  final int count;
  final int words;
}

/// 看板的一行。
class OutputRow {
  const OutputRow({
    required this.key,
    required this.label,
    required this.value,
    required this.level,
    required this.detail,
    required this.good,
  });

  final String key;
  final String label;

  /// 展示值（已格式化）。
  final String value;

  /// 0–100，用于色阶。
  final int level;
  final String detail;

  /// 达标（绿）。
  final bool good;
}

/// 看板本体。
class OutputBoard {
  const OutputBoard({
    required this.score,
    required this.grade,
    required this.rows,
    required this.next,
  });

  /// 0–100 产出分（越靠产出/词块越高）。
  final int score;
  final String grade;
  final List<OutputRow> rows;

  /// 下一步（一句）。
  final String next;
}

int _clamp(num n, [int lo = 0, int hi = 100]) => n < lo ? lo : (n > hi ? hi : n.round());

int _pct(int a, int b) => b > 0 ? _clamp(a / b * 100) : 0;

String _gradeOf(int score) {
  if (score < 25) return '还没产出';
  if (score < 50) return '在练';
  if (score < 75) return '有产出';
  return '实打实';
}

/// 由当前数据算产出看板。
OutputBoard buildOutputBoard(OutputInput i) {
  final w = i.words;
  final chunkAcc = i.chunkStats.total > 0 ? _pct(i.chunkStats.correct, i.chunkStats.total) : 0;
  final grammarAcc =
      i.grammarStats.total > 0 ? _pct(i.grammarStats.correct, i.grammarStats.total) : 0;
  final chunkCover = w.total > 0 ? _pct(w.withChunks, w.total) : 0;
  final memory =
      w.total > 0 ? ((_pct(w.studied, w.total) * 0.6 + _pct(w.stable, w.total) * 0.4).round()) : 0;
  // 仿写：**没批改过的一律不给分**。Web 侧以前没批改按 70 算，而 `good` 又按 0 算，
  // 同一行两个口径 —— 看板说「有 70 分」，行上却永远不达标。
  final write = i.writes.count <= 0
      ? 0
      : (_pct(i.writes.count > 4 ? 4 : i.writes.count, 4) * 0.45 +
              (i.writes.avgScore ?? 0) * 0.55)
          .round();
  final retell = i.retells.count <= 0
      ? 0
      : (_pct(i.retells.count > 3 ? 3 : i.retells.count, 3) * 0.45 +
              _pct(i.retells.words > 120 ? 120 : i.retells.words, 120) * 0.55)
          .round();
  final streak = _pct(i.streak > 7 ? 7 : i.streak, 7);

  final score = _clamp(
    0.24 * chunkAcc +
        0.10 * grammarAcc +
        0.20 * write +
        0.16 * retell +
        0.14 * chunkCover +
        0.10 * memory +
        0.06 * streak,
  );

  final rows = <OutputRow>[
    OutputRow(
      key: 'chunkAcc',
      label: '词块 / 搭配正确率',
      value: i.chunkStats.total > 0
          ? '$chunkAcc%（${i.chunkStats.correct}/${i.chunkStats.total}）'
          : '还没测过',
      level: chunkAcc,
      detail: '搭配填空 · 搭配默写 · 介词填空 · 习语填空',
      good: i.chunkStats.total > 0 && chunkAcc >= 80,
    ),
    OutputRow(
      key: 'grammarAcc',
      label: '语法 / 结构正确率',
      value: i.grammarStats.total > 0
          ? '$grammarAcc%（${i.grammarStats.correct}/${i.grammarStats.total}）'
          : '还没测过',
      level: grammarAcc,
      detail: '词组/习语填空 · 结构语法 · 功能词 · 排序 · 翻译',
      good: i.grammarStats.total > 0 && grammarAcc >= 80,
    ),
    OutputRow(
      key: 'chunkCover',
      label: '词块覆盖',
      value: w.total > 0 ? '${w.withChunks}/${w.total}' : '—',
      level: chunkCover,
      detail: '本篇生词里已有词组/搭配的比例',
      good: w.total > 0 && chunkCover >= 80,
    ),
    OutputRow(
      key: 'write',
      label: '仿写',
      value: i.writes.count > 0
          ? '${i.writes.count} 条${i.writes.avgScore != null ? ' · 均分 ${i.writes.avgScore!.round()}' : ' · 待批改'}'
          : '0 条',
      level: write,
      detail: '自己写 + AI 批改才算',
      good: i.writes.count > 0 && (i.writes.avgScore ?? 0) >= 75,
    ),
    OutputRow(
      key: 'retell',
      label: '复述',
      value: i.retells.count > 0 ? '${i.retells.count} 条 · ${i.retells.words} 词' : '0 条',
      level: retell,
      detail: '用自己的话把这段讲一遍',
      good: i.retells.count >= 1,
    ),
    OutputRow(
      key: 'memory',
      label: '记忆（接受性）',
      value: w.total > 0 ? '学过 ${w.studied}/${w.total} · 稳定 ${w.stable}' : '—',
      level: memory,
      detail: '只作基础分；产出才是重点',
      good: w.total > 0 && memory >= 70,
    ),
    OutputRow(
      key: 'streak',
      label: '连续天数',
      value: '${i.streak} 天',
      level: streak,
      detail: '连续有学习记录的天数',
      good: i.streak >= 3,
    ),
  ];

  final String next;
  if (w.total == 0) {
    next = '先建生词（选词 / 自动标词），产出才有原料';
  } else if (i.chunkStats.total == 0) {
    next = '做一轮「🧩 词块拷打」，才有词块正确率可看';
  } else if (i.writes.count == 0) {
    next = '仿写 1 句并让 AI 批改 —— 产出才真正算涨';
  } else if (i.retells.count == 0) {
    next = '复述一遍这段（能说出来才算真懂）';
  } else if (chunkAcc < 75) {
    next = '搭配正确率还偏低，再来一轮「词块拷打」，专攻错的那几条';
  } else if (memory < 60) {
    next = '还有词没学 / 不稳，回「背单词」清一轮到期';
  } else {
    next = '词块 · 产出 · 记忆都在线，隔天复习即可 ✅';
  }

  return OutputBoard(score: score, grade: _gradeOf(score), rows: rows, next: next);
}

/// 词块类题型（对应 `quizDrillKinds[QuizDrillKind.chunk]`）。
const List<String> outputChunkKinds = <String>['usage', 'collocation', 'prep', 'idiom'];

/// 语言点类题型（对应 `quizDrillKinds[QuizDrillKind.grammar]` 去掉 `phraseBlank` 之外的词级项）。
const List<String> outputGrammarKinds = <String>[
  'grammar',
  'phraseBlank',
  'functionWord',
  'ordering',
  'translate',
  'translate2',
];

/// 把一篇文章的题型统计按名单求和。
///
/// `kindStats` 是 `文章 id → 题型名 → KindStat`；题型的键就是 `QuizKind.name`。
KindStat sumKindStats(KindStats stats, String articleId, List<String> kinds) {
  final byKind = stats[articleId];
  if (byKind == null || byKind.isEmpty) return const KindStat();
  var total = 0;
  var correct = 0;
  for (final k in kinds) {
    final s = byKind[k];
    if (s == null) continue;
    total += s.total;
    correct += s.correct;
  }
  return KindStat(total: total, correct: correct);
}
