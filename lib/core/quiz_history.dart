/// 考试历史：每一轮考试的摘要 + 逐题明细。
///
/// 为什么不进 sqflite：`docs/PLAN.md` 明确「不加 v14 迁移」。这一份是
/// 「丢了最多少看几轮历史」的数据，按 `schema.dart` 的口径该进 SharedPreferences；
/// 汇总口径（正确率 / 按题型）另有 `practice_records`，两边互不依赖。
library;

import 'quiz.dart' show QuizKind, quizKindLabel;
import 'quiz_pool.dart' show QuizMode;

/// 一条逐题明细。
class QuizAnswerRow {
  const QuizAnswerRow({
    required this.word,
    required this.kind,
    required this.correct,
    required this.answer,
    this.input = '',
  });

  final String word;
  final QuizKind kind;
  final bool correct;

  /// 标准答案。
  final String answer;

  /// 用户写的那版（选项题也是选中的那项）。
  final String input;

  String get kindLabel => quizKindLabel[kind] ?? kind.name;

  Map<String, Object?> toJson() => <String, Object?>{
        'word': word,
        'kind': kind.name,
        'correct': correct,
        'answer': answer,
        'input': input,
      };
}

/// 一轮考试的摘要 + 明细。
class QuizRoundRow {
  const QuizRoundRow({
    required this.at,
    required this.mode,
    required this.total,
    required this.correct,
    required this.seconds,
    this.articleId,
    this.articleTitle = '',
    this.entries = const <QuizAnswerRow>[],
  });

  /// ISO 时间。
  final String at;
  final QuizMode mode;
  final int total;
  final int correct;
  final int seconds;
  final String? articleId;

  /// 篇名（存下来是为了文章改名 / 删篇后历史还能看）。
  final String articleTitle;
  final List<QuizAnswerRow> entries;

  /// 正确率（0–1）；`total <= 0` 时 0。
  double get accuracy => total > 0 ? correct / total : 0;

  /// 「3 题 · 对 2 · 67%」这类一行摘要。
  String get summary =>
      '$total 题 · 对 $correct · ${(accuracy * 100).round()}%';

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at,
        'mode': mode.name,
        'total': total,
        'correct': correct,
        'seconds': seconds,
        if (articleId != null) 'articleId': articleId,
        if (articleTitle.isNotEmpty) 'articleTitle': articleTitle,
        'entries': [for (final e in entries) e.toJson()],
      };
}

/// 历史最多留多少轮（每轮最多 [maxQuizHistoryEntries] 题）。
const int maxQuizHistoryRounds = 50;
const int maxQuizHistoryEntries = 40;

/// 追加一轮（新的在前，超出上限丢最旧的）。
List<QuizRoundRow> addQuizRound(
  List<QuizRoundRow> list,
  QuizRoundRow row, {
  int cap = maxQuizHistoryRounds,
}) {
  final next = [row, ...list];
  final keep = cap < 0 ? 0 : cap;
  return next.length <= keep ? next : next.sublist(0, keep);
}

/// 宽容解析：坏轮次整条丢掉，不因为一条坏数据把整份历史清空。
List<QuizRoundRow> parseQuizHistory(Object? raw) {
  if (raw is! List) return const <QuizRoundRow>[];
  final out = <QuizRoundRow>[];
  for (final e in raw) {
    final row = _parseRound(e);
    if (row != null) out.add(row);
    if (out.length >= maxQuizHistoryRounds) break;
  }
  return out;
}

Map<String, Object?> quizHistoryToJson(List<QuizRoundRow> rows) =>
    <String, Object?>{
      'rounds': [for (final r in rows) r.toJson()],
    };

/// 从 `{'rounds': [...]}` 或直接一个 List 都认。
List<QuizRoundRow> parseQuizHistoryPayload(Object? raw) {
  if (raw is Map) return parseQuizHistory(raw['rounds']);
  return parseQuizHistory(raw);
}

QuizRoundRow? _parseRound(Object? raw) {
  if (raw is! Map) return null;
  final at = raw['at'];
  if (at is! String || at.isEmpty) return null;
  final total = _asInt(raw['total']);
  final correct = _asInt(raw['correct']);
  if (total == null || correct == null) return null;
  final mode = switch (raw['mode']) {
    'article' => QuizMode.article,
    _ => QuizMode.vocab,
  };
  return QuizRoundRow(
    at: at,
    mode: mode,
    total: total,
    correct: correct,
    seconds: _asInt(raw['seconds']) ?? 0,
    articleId: switch (raw['articleId']) {
      final String s when s.isNotEmpty => s,
      _ => null,
    },
    articleTitle: switch (raw['articleTitle']) {
      final String s => s,
      _ => '',
    },
    entries: _parseEntries(raw['entries']),
  );
}

List<QuizAnswerRow> _parseEntries(Object? raw) {
  if (raw is! List) return const <QuizAnswerRow>[];
  final out = <QuizAnswerRow>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final word = e['word'];
    if (word is! String) continue;
    final kind = _parseKind(e['kind']);
    if (kind == null) continue;
    out.add(
      QuizAnswerRow(
        word: word,
        kind: kind,
        correct: e['correct'] == true,
        answer: switch (e['answer']) {
          final String s => s,
          _ => '',
        },
        input: switch (e['input']) {
          final String s => s,
          _ => '',
        },
      ),
    );
    if (out.length >= maxQuizHistoryEntries) break;
  }
  return out;
}

QuizKind? _parseKind(Object? raw) {
  if (raw is! String) return null;
  for (final k in QuizKind.values) {
    if (k.name == raw) return k;
  }
  return null;
}

int? _asInt(Object? raw) => switch (raw) {
      int i => i,
      num d when d.isFinite => d.toInt(),
      String s => int.tryParse(s.trim()),
      _ => null,
    };

/// 按天分组的日期键（历史页用它做小标题）；坏时间回空串。
String quizHistoryDayKey(String iso) {
  final at = DateTime.tryParse(iso);
  if (at == null) return '';
  final local = at.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$d';
}
