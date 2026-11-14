/// 「复习单词」三键（认识 / 模糊 / 忘记了）的判定（纯函数）。
///
/// **口径（用户 2026-11-14 定，App 刻意偏离 Web）**：复习 / 回顾阶段先只显示英文，
/// 用户按了任何一档之后，都要**摊开释义并停在页面上**，再给出口：
///
///   - 认识 → 「下一词」「记错了」
///   - 模糊 → 「下一词」「记错了」
///   - 忘记了 → 只有「下一词」
///
/// 所以三键按下去**一律不写库、不推进**（`commit == null, advance == false`），
/// 等用户在卡上选出口时才落库一次：
///
///   - 「下一词」→ 认下这一档（good / hard / again 原样写），推进；
///   - 「记错了」→ 一律改成 again，继续停在卡上看答案。
///
/// 为什么「认识」也不能立刻写 good：用户看过释义后可能反悔点「记错了」，
/// 那时再写 again 就是同一张卡落两次库（统计里算两次，again 还会把 good
/// 刚加的那次 repetitions 清零）。一次决定一次落库。
///
/// Web 版 `src/core/vocab/reviewStep.ts` 的旧口径是「good 直接推进、不摊卡」，
/// 与用户要求不一致；以用户为准，Web 侧不改。
library;

import 'review.dart';

/// 按了某个键之后，会话要做什么。
class ReviewStepPlan {
  const ReviewStepPlan({
    required this.commit,
    required this.advance,
    required this.showCard,
  });

  /// 要落库的评分；null = 先不写，等用户在单词卡上选出口。
  final ReviewGrade? commit;

  /// 落库后是否立刻换下一张。
  final bool advance;

  /// 是否把这张卡摊开（显示释义 / 例句 / 用法）。
  final bool showCard;
}

/// 摊卡之后的两个出口。
enum ReviewExitChoice { next, missed }

/// 三键之一按下去：**一律摊卡停住**，等出口。
///
/// 返回的 [ReviewStepPlan] 永远是「不写库、不推进、摊卡」——保留这个函数
/// 是为了让「按了键之后干什么」这件事仍然有唯一出处，界面不用自己拼。
ReviewStepPlan planReviewGrade(ReviewGrade grade) =>
    const ReviewStepPlan(commit: null, advance: false, showCard: true);

/// 这一档摊卡之后允不允许点「记错了」。
///
/// 按用户口径：认识了也允许反悔（改判不认识），忘记了就只给「下一词」。
bool reviewExitAllowsMistake(ReviewGrade grade) => grade != ReviewGrade.again;

/// 摊卡之后的出口：
///   - 「下一词」= 认下这一档（原样写），推进；
///   - 「记错了」= 改成不认识（again），继续停在卡上看答案。
ReviewStepPlan planReviewExit(ReviewGrade grade, ReviewExitChoice choice) =>
    choice == ReviewExitChoice.next
        ? ReviewStepPlan(commit: grade, advance: true, showCard: false)
        : const ReviewStepPlan(
            commit: ReviewGrade.again,
            advance: false,
            showCard: true,
          );

/// 兼容旧调用名：模糊摊卡后的出口（语义等同于 [planReviewExit] 的 hard 档）。
ReviewStepPlan planReviewFuzzyChoice(ReviewExitChoice choice) =>
    planReviewExit(ReviewGrade.hard, choice);
