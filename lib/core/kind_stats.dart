/// 按「文章 → 题型」统计的正确率（词块 / 搭配量化用）。
///
/// 单独一个文件是为了断开依赖：`answerEvents` 要能重建它，`learning` 要把它当成
/// 学习记录的一节，两边都 import 这里就不会互指。
/// 对应 Web 版 `src/core/learning.ts` 里的 `KindStats` 类型。
library;

/// 一个题型的一次累计。
class KindStat {
  const KindStat({this.total = 0, this.correct = 0});

  final int total;
  final int correct;

  KindStat plus({int total = 0, int correct = 0}) =>
      KindStat(total: this.total + total, correct: this.correct + correct);

  @override
  bool operator ==(Object other) =>
      other is KindStat && other.total == total && other.correct == correct;

  @override
  int get hashCode => Object.hash(total, correct);

  @override
  String toString() => 'KindStat($correct/$total)';
}

/// `文章 id → 题型 → 累计`。
typedef KindStats = Map<String, Map<String, KindStat>>;

/// 空统计（每次都返回新 Map，避免调用方改到共享常量）。
KindStats emptyKindStats() => <String, Map<String, KindStat>>{};

/// 取 `[articleId][kind]`，没有就给 0/0（不建键）。
KindStat kindStatOf(KindStats stats, String articleId, String kind) =>
    stats[articleId]?[kind] ?? const KindStat();

/// 宽容解析统计表：坏行丢掉，整行都坏就连文章键一起不建。
///
/// 与 Web 版 `normalizeLearning` 里那段手写守卫同口径：`total`/`correct`
/// 必须是有限数（`'x'`、`null` 都丢），空行不留在结果里。
KindStats normalizeKindStats(Object? raw) {
  final out = emptyKindStats();
  if (raw is! Map) return out;
  for (final entry in raw.entries) {
    final articleId = '${entry.key}';
    final byKind = entry.value;
    if (byKind is! Map) continue;
    final row = <String, KindStat>{};
    for (final sub in byKind.entries) {
      final stat = sub.value;
      if (stat is! Map) continue;
      final total = _finiteInt(stat['total']);
      final correct = _finiteInt(stat['correct']);
      if (total == null || correct == null) continue;
      row['${sub.key}'] = KindStat(total: total, correct: correct);
    }
    if (row.isNotEmpty) out[articleId] = row;
  }
  return out;
}

int? _finiteInt(Object? v) => switch (v) {
      int i => i,
      double d when d.isFinite => d.toInt(),
      // Web 版是 `Number.isFinite(Number(v))`，纯数字字符串也算合法。
      String s => num.tryParse(s.trim())?.toInt(),
      _ => null,
    };
