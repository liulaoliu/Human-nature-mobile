import 'package:flutter/material.dart';

import '../core/golden_drill.dart';
import '../viewmodels/golden_drill_session.dart';

/// 拼句正文。
///
/// 原文只画**挖空版**：非学习点照常显示，学习点换成 `[1]` `[2]` 空位；
/// 下面才是打乱后的词块，按句子顺序点。Web 版同样如此
/// （`GoldenDrillView.SentenceLine` 的 `mode="assemble"`）——
/// 用户 2026-11-16 报「原文所有英文全部一直显示、选项还能反复选」，
/// 这两条都按 Web 版对齐。
///
/// 单独成文件（不是塞在 `golden_drill_view.dart` 里）：那个文件管填空的
/// 焦点 / 键盘 / 滚屏，已经够长；拼句是纯展示 + 转发到 session。
class GoldenAssembleView extends StatelessWidget {
  const GoldenAssembleView({super.key, required this.session});

  final GoldenDrillSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assembly = session.assembly;
    final order = session.order;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text(
          assembly == null
              ? '这一句没有可拼的学习点。'
              : '按正确顺序点出这句话：空位按 [空号] 找对应词块，点过的词块会用掉。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (assembly != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _AssembleSentence(cloze: assembly.cloze),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Text(
                '已拼 ${order.length}/${assembly.bank.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (order.isNotEmpty && !session.assembleScored)
                TextButton(
                  onPressed: session.clearOrder,
                  child: const Text('清空'),
                ),
            ],
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: order.isEmpty
                ? Text(
                    '（还没点）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (var i = 0; i < order.length; i++)
                        InputChip(
                          label: Text(order[i]),
                          visualDensity: VisualDensity.compact,
                          deleteButtonTooltipMessage: '撤回这一块',
                          deleteIcon: const Icon(
                            Icons.close,
                            size: 18,
                            key: ValueKey<String>('golden-assemble-undo'),
                          ),
                          // 点 × 撤掉这一块，不用一路撤回。
                          onDeleted: session.assembleScored
                              ? null
                              : () => session.removeAt(i),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            '词块：',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String w in assembly.bank)
                ActionChip(
                  label: Text(w),
                  // 一个词块一份：已经点过的置灰（`canPick` 按份数算，
                  // 重复出现的同一词块各有一次）。
                  onPressed: session.assembleScored || !session.canPick(w)
                      ? null
                      : () => session.pick(w),
                ),
            ],
          ),
        ],
        if (session.assembleScored) ...<Widget>[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: session.assembleOk
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              // 只说「不对」，不给正确顺序 —— 报了顺序等于把答案送了
              // （用户 2026-11-16 要求：可以选错，但不能变相提醒）。
              session.assembleOk ? '顺序对了。' : '顺序不对，再试一次。',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

/// 挖空版原文：文字按原样排，学习点换成 `[空号]` 的占位块。
///
/// 用 `Text.rich` 而不是一排 `Chip`：空位要跟着词一起换行，
/// 否则长句会被拆成「一行文字 + 一行空」，读不出句子结构。
class _AssembleSentence extends StatelessWidget {
  const _AssembleSentence({required this.cloze});

  final GoldenCloze cloze;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge;
    final spans = <InlineSpan>[];
    var slot = 0;
    for (final GoldenClozePart p in cloze.parts) {
      if (!p.blank) {
        spans.add(TextSpan(text: p.text));
        continue;
      }
      final index = p.blankIndex ?? 0;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            // key 按「第几个空位」拼，测试用来定位（同一学习点重复出现时
            // 空号相同，位置不同）。
            key: ValueKey<String>('golden-assemble-slot-${slot++}'),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '[$index]',
              style: (style ?? const TextStyle()).copyWith(
                fontSize: ((style?.fontSize) ?? 16) - 2,
                height: 1.2,
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
