/// 单词卡上的派生信息：热度、到期文案、SRS 行（纯函数）。
///
/// 为什么单独一个文件：这三样都是「卡片上显示什么字」的规则，Web 版散在
/// `StudyCardView.tsx` 的 JSX 里（`heat` 三元套娃 + `fmtDue` + SRS 行拼接）。
/// 规则留在视图里就只能靠截图验证，抽出来才有测试。
library;

import '../../models/vocab.dart';
import '../study_session.dart' show fmtInterval;
import 'library.dart' show isPriority;
import 'review.dart';

/// 卡片「热度」：停得越久越红，到 [drillAfter] 秒就算「该锤炼了」。
///
/// 与 Web 版 `StudyPanel.tsx` 的 `heat` 同口径（顺序不能换：先看 90，再看阈值）：
///   - ≥ 90 秒 → 4
///   - ≥ [drillAfter]（且 [drillAfter] > 0）→ 3
///   - ≥ 30 秒 → 2
///   - ≥ 12 秒 → 1
///   - 否则 0
int cardHeat({required int seconds, required int drillAfter}) {
  if (seconds >= 90) return 4;
  if (drillAfter > 0 && seconds >= drillAfter) return 3;
  if (seconds >= 30) return 2;
  if (seconds >= 12) return 1;
  return 0;
}

/// 计时文案：`12s`；超过 25 秒再加一句「别墨迹」（与 Web 版同一句）。
String cardTimerLabel(int seconds) =>
    seconds >= 25 ? '${seconds}s · 别墨迹' : '${seconds}s';

/// 到期时间（ISO）→「现在 / 明天 / N 天后」；没排期或读不出来返回空串。
///
/// 与 Web 版 `fmtDue` 同口径：按**毫秒差除以一天再向上取整**，不是按日历天。
String fmtDue(String? iso, {DateTime? now}) {
  if (iso == null || iso.isEmpty) return '';
  final at = DateTime.tryParse(iso);
  if (at == null) return '';
  final ms = at.difference(now ?? DateTime.now()).inMilliseconds;
  final days = (ms / Duration.millisecondsPerDay).ceil();
  if (days <= 0) return '现在';
  if (days == 1) return '明天';
  return '$days 天后';
}

/// 卡片背面那行 SRS 摘要。
///
/// 形如：`复习 3 次 · 忘记 1 次 · 下次 明天 · 预计下次：认识 6 天后 / 模糊 3 天后 /
/// 忘记了 1 天后 · 🔥 优先重练 · ♻️ 重学中 · 🆕 标为不认识`。
///
/// 「预计下次」只在 [gradeable] 且不是复习模式时给——复习模式的三键走的是另一套
/// 判定（`useStudyReviewStep`），提前算出间隔反而误导。
String cardSrsLine({
  required VocabItem card,
  bool gradeable = false,
  bool reviewMode = false,
  bool relearning = false,
  DateTime? now,
}) {
  final s = card.reviewState;
  final parts = <String>['复习 ${s.repetitions} 次'];
  if (s.lapses > 0) parts.add('忘记 ${s.lapses} 次');
  final due = fmtDue(s.due, now: now);
  parts.add(due.isEmpty ? '还没排期' : '下次 $due');
  if (gradeable && !reviewMode) {
    parts.add(
      '预计下次：认识 ${fmtInterval(review(s, ReviewGrade.good, now).interval)}'
      ' / 模糊 ${fmtInterval(review(s, ReviewGrade.hard, now).interval)}'
      ' / 忘记了 ${fmtInterval(review(s, ReviewGrade.again, now).interval)}',
    );
  }
  if (isPriority(card, now: now)) parts.add('🔥 优先重练');
  if (relearning) parts.add('♻️ 重学中');
  if (card.tags.contains(spellingMissTag)) parts.add('🆕 标为不认识');
  return parts.join(' · ');
}
