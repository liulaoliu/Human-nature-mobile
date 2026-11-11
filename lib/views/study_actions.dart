/// 单词卡下面那排按钮：九态优先级（与 Web 的 `StudyActions.tsx` 同序）。
///
/// 顺序不是随便排的，改之前先看每一态的注释：**越靠上的越紧急**，
/// 比如锤炼没做完就不该给评分按钮。
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

    // ④ 模糊摊卡之后：下一词 / 记错了
    if (flow.reviewFuzzy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => flow.chooseFuzzy(ReviewFuzzyChoice.next),
                  child: const Text('下一词'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => flow.chooseFuzzy(ReviewFuzzyChoice.missed),
                  child: const Text('记错了 · 其实不认识'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // ⑤ 已评过分、停在卡上等下一张
    if (flow.reviewGraded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: onNext, child: const Text('下一词')),
        ],
      );
    }

    // ⑦ 可以评分：认识 / 模糊 / 忘记了
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

    // ⑨ 兜底：还没翻面
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
