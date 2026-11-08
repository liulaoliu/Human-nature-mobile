import 'review.dart';

/// 背单词「加练 / 重练」的出场账本（纯函数）。
///
/// 规则（2026-10-21 改版，用户明确要求）：
///   - 评「忘记了」→ 本轮队尾再出现一次，**不设次数上限**，直到用户评「认识」或「模糊」；
///   - 评「模糊」/「认识」→ 本轮不再追加（模糊就是收尾条件，不是再来一遍）；
///   - 「重练忘记的」每轮只发起一次，全部忘记过的词都进队（不再按旧上限剔除）。
///
/// 为什么不再封顶：3 次上限会让「一直记不住」的词在第 3 次之后被放过，等于替用户
/// 决定「可以了」。代价是用户一直点「忘记」时这一轮做不完——但停不停由用户决定
/// （评认识/模糊、切下一个、结束），程序不替他跳过。
///
/// 复习侧仍有兜底：again 会写 `ReviewState.relearn`（+1），这个词下次进复习队列
/// 时排在「需要多复习」的最前，并从「看词 → 释义 → 锤炼」重新走一遍。
///
/// 与 Web 版 `src/core/vocab/extra.ts` 一一对应。
class ExtraRound {
  const ExtraRound({this.appearances = const {}, this.retried = false});

  /// 每张卡本轮已出场次数（首见算 1），只用于展示 / 审计。
  final Map<String, int> appearances;

  /// 本轮是否已经点过「重练忘记的」。
  final bool retried;

  ExtraRound copyWith({Map<String, int>? appearances, bool? retried}) => ExtraRound(
        appearances: appearances ?? this.appearances,
        retried: retried ?? this.retried,
      );
}

/// 还没开始的空账本。
ExtraRound emptyExtraRound() => const ExtraRound();

/// 开新一轮：队列里每出现一次记 1 次出场。
ExtraRound beginExtraRound(List<String> ids) {
  final appearances = <String, int>{};
  for (final id in ids) {
    appearances[id] = (appearances[id] ?? 0) + 1;
  }
  return ExtraRound(appearances: appearances);
}

class ExtraDecision {
  const ExtraDecision({required this.round, required this.append});

  /// 记账后的状态（没有追加时原样返回）。
  final ExtraRound round;

  /// 是否把这张卡追加到队尾。
  final bool append;
}

/// 评分后要不要把这张卡追加到队尾再加练一次。
///
/// 只有「忘记了」追加；「认识 / 模糊」都是本轮收尾，不再追加。
/// 不封顶：同一个词连续评忘记，就会一直回到队尾，直到评出认识或模糊。
ExtraDecision planExtra(ExtraRound round, String id, ReviewGrade grade) {
  if (grade != ReviewGrade.again) return ExtraDecision(round: round, append: false);
  final seen = round.appearances[id] ?? 0;
  return ExtraDecision(
    round: round.copyWith(appearances: {...round.appearances, id: seen + 1}),
    append: true,
  );
}

class RetryDecision {
  const RetryDecision({required this.round, required this.ids, required this.blocked});

  /// 记账后的状态（不管有没有真的进重练，`retried` 都会置位）。
  final ExtraRound round;

  /// 真正进入重练的 id（去重后保持传入顺序）。
  final List<String> ids;

  /// 本轮已经重练过了，这次不发起。
  final bool blocked;
}

/// 收尾「重练忘记的」：每轮只发起一次，忘记过的词全部进队。
/// 进重练的卡也算一次出场（记进账本）。
RetryDecision planRetryForgot(ExtraRound round, List<String> ids) {
  if (round.retried) {
    return RetryDecision(round: round, ids: const [], blocked: true);
  }
  final kept = <String>[];
  final seen = <String>{};
  for (final id in ids) {
    if (seen.add(id)) kept.add(id);
  }
  final appearances = {...round.appearances};
  for (final id in kept) {
    appearances[id] = (appearances[id] ?? 0) + 1;
  }
  return RetryDecision(
    round: ExtraRound(appearances: appearances, retried: true),
    ids: kept,
    blocked: false,
  );
}
