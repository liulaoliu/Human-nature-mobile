import 'review.dart';

/// 「复习单词」三键（认识 / 模糊 / 忘记了）的判定（纯函数）。
///
/// 复习模式和背新词不一样：这里**不需要先翻面**——看见单词就该能判断认识不认识。
/// 所以三键直接可点，只有「判模糊 / 判忘记」时才把卡摊开（看释义、例句），
/// 让用户在**看过答案之后**还能反悔一次：
///
///   - 认识      → 直接写 good 并换下一张（不摊卡，说明真认识；组末拼写会核验）
///   - 模糊      → **先不写库**，摊开单词卡，等用户选「下一词」或「记错了」
///   - 忘记了    → 立刻写 again（判不认识），摊开卡片让用户看一眼再换下一张
///   - 记错了    → 把模糊改成 again（用户看过释义才反应过来「其实不认识」）
///
/// 「模糊先不落库」是刻意的：先写 hard、再改 again 等于同一张卡落两次库、
/// 统计里也算两次，而且 again 会把 hard 刚加的那次 repetitions 又清零——
/// 中间那次写库除了制造脏数据没有任何意义。等用户选完再写，一次决定一次落库。
/// 与 Web 版 `src/core/vocab/reviewStep.ts` 一一对应。

/// 按了某个键之后，会话要做什么。
class ReviewStepPlan {
  const ReviewStepPlan({
    required this.commit,
    required this.advance,
    required this.showCard,
  });

  /// 要落库的评分；null = 先不写，等用户在单词卡上选。
  final ReviewGrade? commit;

  /// 落库后是否立刻换下一张。
  final bool advance;

  /// 是否把这张卡摊开（显示释义 / 例句 / 用法）。
  final bool showCard;
}

/// 模糊后停在单词卡上的两个出口。
enum ReviewFuzzyChoice { next, missed }

/// 三键之一按下去：怎么落库、要不要摊卡、要不要推进。
ReviewStepPlan planReviewGrade(ReviewGrade grade) {
  if (grade == ReviewGrade.good || grade == ReviewGrade.easy) {
    return ReviewStepPlan(commit: grade, advance: true, showCard: false);
  }
  // 模糊：留一个「看过释义还能改口」的机会，先不写库
  if (grade == ReviewGrade.hard) {
    return const ReviewStepPlan(commit: null, advance: false, showCard: true);
  }
  // 忘记了 / 已判不认识：立刻写 again，但停在卡上让人看一眼答案
  return const ReviewStepPlan(commit: ReviewGrade.again, advance: false, showCard: true);
}

/// 模糊摊卡之后的选择：
///   - 「下一词」= 认下模糊（hard），推进
///   - 「记错了」= 改成不认识（again），继续停在卡上看答案
ReviewStepPlan planReviewFuzzyChoice(ReviewFuzzyChoice choice) => choice == ReviewFuzzyChoice.next
    ? const ReviewStepPlan(commit: ReviewGrade.hard, advance: true, showCard: false)
    : const ReviewStepPlan(commit: ReviewGrade.again, advance: false, showCard: true);
