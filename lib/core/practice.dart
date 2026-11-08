/// 练习记录：把每次「考试 / 听写 / 听力理解 / 小课堂」的成绩记下来，供统计与回顾。
///
/// 纯函数、零 IO，存储由 `LearningData.practice` 负责（sqflite）。
/// 对应 Web 版 `src/core/practice.ts`（100 行）。
library;

/// 记录类型。
enum PracticeKind { quiz, dictation, listening, golden }

const List<PracticeKind> practiceKinds = [
  PracticeKind.quiz,
  PracticeKind.dictation,
  PracticeKind.listening,
  PracticeKind.golden,
];

const Map<PracticeKind, String> practiceLabel = {
  PracticeKind.quiz: '考试',
  PracticeKind.dictation: '听写',
  PracticeKind.listening: '听力理解',
  PracticeKind.golden: 'D老师小课堂',
};

PracticeKind? parsePracticeKind(Object? raw) {
  for (final k in practiceKinds) {
    if (k.name == raw) return k;
  }
  return null;
}

class PracticeRecord {
  const PracticeRecord({
    required this.at,
    required this.kind,
    required this.total,
    required this.correct,
    this.seconds,
    this.articleId,
  });

  /// ISO 时间。
  final String at;
  final PracticeKind kind;

  /// 题数 / 段数。
  final int total;

  /// 答对数量。
  final int correct;

  /// 用时（秒），可选。
  final int? seconds;

  /// 来源文章（用于按篇统计掌握度）；旧记录可能没有。
  final String? articleId;

  @override
  String toString() => 'PracticeRecord($kind, $correct/$total, $at)';
}

/// 追加一条记录（保留最近 cap 条）。纯函数。
List<PracticeRecord> addPracticeRecord(List<PracticeRecord> list, PracticeRecord rec, {int cap = 500}) {
  final next = [...list, rec];
  final keep = cap < 0 ? 0 : cap;
  return next.length <= keep ? next : next.sublist(next.length - keep);
}

/// 正确率（0–1）；`total <= 0` 时为 0。
double accuracy(PracticeRecord rec) => rec.total > 0 ? rec.correct / rec.total : 0;

/// 最近 n 条（新的在前）。
List<PracticeRecord> recentPractice(List<PracticeRecord> list, {int n = 10}) {
  final keep = n < 0 ? 0 : n;
  final tail = keep >= list.length ? list : list.sublist(list.length - keep);
  return tail.reversed.toList();
}

class PracticeSum {
  const PracticeSum({this.total = 0, this.correct = 0});

  final int total;
  final int correct;

  @override
  bool operator ==(Object other) =>
      other is PracticeSum && other.total == total && other.correct == correct;

  @override
  int get hashCode => Object.hash(total, correct);

  @override
  String toString() => 'PracticeSum($correct/$total)';
}

/// 合计 total/correct。
PracticeSum sumPractice(List<PracticeRecord> list) {
  var total = 0;
  var correct = 0;
  for (final r in list) {
    total += r.total;
    correct += r.correct;
  }
  return PracticeSum(total: total, correct: correct);
}

/// 按类型合计（四种类型都出现，缺的给 0）。
Map<PracticeKind, PracticeSum> sumByKind(List<PracticeRecord> list) {
  final total = {for (final k in practiceKinds) k: 0};
  final correct = {for (final k in practiceKinds) k: 0};
  for (final r in list) {
    total[r.kind] = total[r.kind]! + r.total;
    correct[r.kind] = correct[r.kind]! + r.correct;
  }
  return {
    for (final k in practiceKinds) k: PracticeSum(total: total[k]!, correct: correct[k]!),
  };
}

/// 只看某篇文章的练习记录（用于按篇算掌握度）。
List<PracticeRecord> practiceForArticle(List<PracticeRecord> list, String articleId) {
  if (articleId.isEmpty) return const [];
  return [
    for (final r in list)
      if (r.articleId == articleId) r,
  ];
}

class PracticeDayTotals {
  const PracticeDayTotals({this.total = 0, this.correct = 0, this.count = 0});

  final int total;
  final int correct;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is PracticeDayTotals &&
      other.total == total &&
      other.correct == correct &&
      other.count == count;

  @override
  int get hashCode => Object.hash(total, correct, count);

  @override
  String toString() => 'PracticeDayTotals($total, $correct, $count)';
}

/// 按天汇总（key = 逻辑日，由调用方给 [dayKeyOf]）。
Map<String, PracticeDayTotals> practiceByDay(
  List<PracticeRecord> list,
  String Function(String iso) dayKeyOf,
) {
  final map = <String, PracticeDayTotals>{};
  for (final r in list) {
    final k = dayKeyOf(r.at);
    final cur = map[k] ?? const PracticeDayTotals();
    map[k] = PracticeDayTotals(
      total: cur.total + r.total,
      correct: cur.correct + r.correct,
      count: cur.count + 1,
    );
  }
  return map;
}
