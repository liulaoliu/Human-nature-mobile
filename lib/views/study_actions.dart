/// 单词卡下面那排按钮：按优先级依次判定（与 Web 的 `StudyActions.tsx` 同序）。
///
/// 顺序不是随便排的，改之前先看每一态的注释：**越靠上的越紧急**，
/// 比如锤炼没做完就不该给评分按钮。
///
/// **口径（用户 2026-11-14 定）**：复习 / 回顾阶段任何一档评完都摊开释义并停住，
/// 出口按档位给：
///   - 认识 / 模糊 → 「下一词」「记错了」
///   - 忘记了      → 只有「下一词」
library;

import 'package:flutter/material.dart';

import '../core/vocab/review.dart';
import '../core/vocab/review_step.dart';
import '../viewmodels/study_card_flow.dart';

/// 动作区。
class StudyActions extends StatelessWidget {
  const StudyActions({
    super.key,
    required this.flow,
    required this.onNext,
    required this.onShowMeaning,
  });

  final StudyCardFlow flow;
  final VoidCallback onNext;
  final VoidCallback onShowMeaning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // ① 锤炼中：面板自己接管，这里什么都不给
    if (flow.drill != null) return const SizedBox.shrink();

    // ② 学习四选一：判完只给「继续（看单词卡）」
    if (flow.learnGraded && !flow.learnContinued) {
      return FilledButton(
        onPressed: flow.continueAfterLearn,
        child: const Text('继续（看单词卡）'),
      );
    }

    // ③ 复习已评分、摊着释义等出口
    if (flow.reviewFuzzy || flow.reviewGraded) {
      return _ReviewExits(flow: flow, onNext: onNext);
    }

    // ④ 可以评分：认识 / 模糊 / 忘记了
    if (flow.reviewMode || flow.revealed) {
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

    // ⑤ 兜底：还没翻面
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(onPressed: onShowMeaning, child: const Text('显示释义')),
        const SizedBox(height: 6),
        Text(
          '看完再评：认识 / 模糊 / 忘记了',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 复习摊卡之后的出口行。
class _ReviewExits extends StatelessWidget {
  const _ReviewExits({required this.flow, required this.onNext});

  final StudyCardFlow flow;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // 「记错了」只在还能改判时给：已判成 again 就只剩「下一词」
    final allowMistake = flow.reviewPending != null &&
        reviewExitAllowsMistake(flow.reviewPending!);
    if (!allowMistake) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: onNext, child: const Text('下一词')),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: () => flow.chooseReviewExit(ReviewExitChoice.next),
            child: const Text('下一词'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => flow.chooseReviewExit(ReviewExitChoice.missed),
            child: const Text('记错了 · 其实不认识'),
          ),
        ),
      ],
    );
  }
}
