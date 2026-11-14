/// 答题事件：每答一题追加一条 append-only 记录。
///
/// 为什么要有：`activity` / `kindStats` 只有聚合值，算错/丢一条就再也无法对账。
/// 事件表保存原始对错（时间 / 文章 / 题型 / 所属统计分类），聚合值仍照常写
/// （兼容老数据），事件用于以后重建或核对。
///
/// 纯函数；存储由 `LearningData.answerEvents` 负责。
/// 对应 Web 版 `src/core/answerEvents.ts`（112 行）。
library;

import 'activity/activity.dart';
import 'kind_stats.dart';
import 'practice.dart';
import 'quiz.dart' show QuizKind;

class AnswerEvent {
  const AnswerEvent({
    required this.at,
    required this.day,
    required this.articleId,
    required this.source,
    required this.kind,
    required this.cat,
    required this.correct,
    this.questionId,
  });

  /// ISO 时间。
  final String at;

  /// 本地结算日 YYYY-MM-DD（04:00 结算，由 [dayKeyLocal] 统一算）。
  final String day;

  /// 来源文章；没有归属时为空串。
  final String articleId;

  /// 哪个会话出的题。
  final PracticeKind source;

  /// 题型：考试是 `cloze`/`spell`/…，听写/听力分别是 `dictation`/`listening`。
  final String kind;

  /// 这条事件计入哪类活动（与当时 recordActivity 的口径一致）。
  final ActivityCat cat;

  final bool correct;

  /// 题目 id（重做错题时便于对账；旧数据可缺）。
  final String? questionId;

  @override
  String toString() => 'AnswerEvent($kind, $correct, $at)';
}

/// 缓存上限：sqflite 才是耐久主存，这里只保证最近一段能离线对账。
const int answerEventCap = 5000;

const Set<String> _sources = {'quiz', 'dictation', 'listening', 'golden'};
final Set<String> _cats = {for (final c in activityCats) c.name};

/// 运行时守卫：坏条目丢弃，不因一条脏数据拖垮整份学习记录。
///
/// 导入备份 / 本地缓存 / 服务端返回都先过这里。
List<AnswerEvent> normalizeAnswerEvents(Object? raw) {
  if (raw is! List) return const [];
  final out = <AnswerEvent>[];
  for (final row in raw) {
    if (row is! Map) continue;
    final at = row['at'] is String ? row['at'] as String : '';
    final source = row['source'] is String ? row['source'] as String : '';
    final kind = row['kind'] is String ? (row['kind'] as String).trim() : '';
    final cat = row['cat'] is String ? row['cat'] as String : '';
    if (at.isEmpty || DateTime.tryParse(at) == null) continue;
    if (!_sources.contains(source) || kind.isEmpty || !_cats.contains(cat)) continue;
    final correct = row['correct'];
    if (correct is! bool) continue;
    final questionId = row['questionId'];
    out.add(AnswerEvent(
      at: at,
      day: row['day'] is String && (row['day'] as String).isNotEmpty
          ? row['day'] as String
          : dayKeyLocal(DateTime.parse(at).toLocal()),
      articleId: row['articleId'] is String ? row['articleId'] as String : '',
      source: parsePracticeKind(source)!,
      kind: kind,
      cat: ActivityCat.values.firstWhere((c) => c.name == cat),
      correct: correct,
      questionId: questionId is String && questionId.isNotEmpty ? questionId : null,
    ));
  }
  return out;
}

/// 新建事件：`at` 为空串就取 [now]；`day` 为空串就按 [at] 现算。
///
/// 语义与 Web 版 `createAnswerEvent(input, now)` 一致：两个字段都可以「不填」，
/// 不填的由它补，填了的原样保留。
AnswerEvent createAnswerEvent(AnswerEvent event, {DateTime? now}) {
  final at = event.at.isNotEmpty
      ? event.at
      : (now ?? DateTime.now()).toUtc().toIso8601String();
  final day = event.day.isNotEmpty
      ? event.day
      : dayKeyLocal(DateTime.parse(at).toLocal());
  return AnswerEvent(
    at: at,
    day: day,
    articleId: event.articleId,
    source: event.source,
    kind: event.kind,
    cat: event.cat,
    correct: event.correct,
    questionId: event.questionId,
  );
}

/// 追加一条（保留最近 cap 条）。纯函数。
List<AnswerEvent> addAnswerEvent(List<AnswerEvent> list, AnswerEvent event, {int cap = answerEventCap}) {
  final next = [...list, event];
  final keep = cap < 0 ? 0 : cap;
  return next.length <= keep ? next : next.sublist(next.length - keep);
}

/// 从事件重建「文章 → 题型」正确率。
///
/// 只有考试题有题型维度；听写/听力没有 kindStats 口径，跳过。
KindStats answerEventsToKindStats(List<AnswerEvent> events) {
  final out = <String, Map<String, KindStat>>{};
  for (final ev in events) {
    if (ev.source != PracticeKind.quiz || ev.articleId.isEmpty || ev.kind.isEmpty) continue;
    final byKind = out.putIfAbsent(ev.articleId, () => <String, KindStat>{});
    final cur = byKind[ev.kind] ?? const KindStat();
    byKind[ev.kind] = cur.plus(total: 1, correct: ev.correct ? 1 : 0);
  }
  return out;
}

/// 从事件重建活动热力图（按事件里记录的结算日归档）。
List<DayActivity> answerEventsToActivity(List<AnswerEvent> events) {
  var out = <DayActivity>[];
  for (final ev in events) {
    out = addActivity(out, ev.day, ev.cat);
  }
  return out;
}

/// 一道题计入哪类活动（与 Web 版 `createQuizCheck.ts:100` 同口径）：
/// 文章级题算「读」，听音 / 听音拼词算「听」，其余算「词」。
///
/// 为什么单独提出来：考试会话与快速拷打都要写答题事件，两处各抄一份迟早漂移。
ActivityCat quizActivityCat(QuizKind kind) {
  if (kind.isArticle) return ActivityCat.read;
  if (kind == QuizKind.listen || kind == QuizKind.ear) {
    return ActivityCat.listen;
  }
  return ActivityCat.vocab;
}
