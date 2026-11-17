/// 单词卡下面那排按钮：按优先级依次判定（与 Web 的 `StudyActions.tsx` 同序）。
///
/// 顺序不是随便排的，改之前先看每一态的注释：**越靠上的越紧急**，
/// 比如锤炼没做完就不该给评分按钮。
///
/// **口径（用户 2026-11-14 定，2026-11-17 改出口）**：复习 / 回顾阶段任何一档评完都
/// 摊开释义并停住：
///   - 底部出口统一只有「下一词」（认识 / 模糊 / 忘记了 同一个按钮，不再并排两个）；
///   - 「记错了 · 其实不认识」功能保留，但按钮搬到**单词卡上方**（`study_page.dart`），
///     只有认识 / 模糊之后才出现；
///   - **点一下看释义 = 模糊**（`StudyCardFlow.reveal`）：摊卡即待定 hard；
///   - 学习四选一落库后进卡只给「下一词」，卡上不再给三键（防 SRS 双写）。
library;

import 'package:flutter/material.dart';

import '../core/vocab/review.dart';
import '../core/vocab/review_step.dart';
import '../viewmodels/study_card_flow.dart';
import '../viewmodels/study_spelling_front.dart';

/// 动作区。
class StudyActions extends StatelessWidget {
  const StudyActions({
    super.key,
    required this.flow,
    required this.onNext,
    required this.onShowMeaning,
    this.spelling,
  });

  final StudyCardFlow flow;
  final VoidCallback onNext;
  final VoidCallback onShowMeaning;

  /// 卡面拼写状态机（不传 = 这个入口不考拼写）。
  final StudySpellingFront? spelling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // ① 锤炼中：面板自己接管，这里什么都不给
    if (flow.drill != null) return const SizedBox.shrink();

    // ② 卡面拼写还没检查：只给「检查」
    final spell = spelling;
    if (spell != null && spell.front) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            key: const ValueKey<String>('study-spell-check'),
            onPressed: spell.check,
            child: const Text('检查（回车）'),
          ),
          const SizedBox(height: 6),
          Text(
            '拼写错一次就判「不认识」，没有第二次机会',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    // ③ 拼错确认：只给「知道了，下一个」
    final miss = spell?.miss;
    if (miss != null) {
      return FilledButton(
        key: const ValueKey<String>('study-spell-ack'),
        onPressed: spell!.ack,
        child: const Text('知道了，下一个'),
      );
    }

    // ④ 学习四选一：判完只给「继续（看单词卡）」
    if (flow.learnGraded && !flow.learnContinued) {
      return FilledButton(
        onPressed: flow.continueAfterLearn,
        child: const Text('继续（看单词卡）'),
      );
    }

    // ⑤ 四选一已经落库：卡只负责看一遍，不再给三键（否则 SRS 双写）
    if (flow.learnCommitted && flow.learnContinued) {
      return FilledButton(
        onPressed: onNext,
        child: const Text('下一词'),
      );
    }

    // ⑥ 复习 / 回顾摊卡：出口统一只给「下一词」（与「忘记了」对齐）。
    // 「记错了 · 其实不认识」功能保留，按钮渲染在单词卡上方（`_CardBody`）。
    if (flow.reviewFuzzy || flow.reviewGraded) {
      return FilledButton(
        onPressed: () => flow.chooseReviewExit(ReviewExitChoice.next),
        child: const Text('下一词'),
      );
    }

    // ⑦ 可以评分：认识 / 模糊 / 忘记了
    if (flow.reviewMode || flow.revealed || (spell?.checked ?? false)) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => flow.chooseGrade(ReviewGrade.again),
              child: const Text('忘记了'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => flow.chooseGrade(ReviewGrade.hard),
              child: const Text('模糊'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () => flow.chooseGrade(ReviewGrade.good),
              child: const Text('认识'),
            ),
          ),
        ],
      );
    }

    // ⑧ 兜底：还没翻面（点一下卡也算「看释义 = 模糊」，见 StudyCardFlow.reveal）
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(onPressed: onShowMeaning, child: const Text('显示释义')),
        const SizedBox(height: 6),
        Text(
          '点开释义会按「模糊」记一档',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
