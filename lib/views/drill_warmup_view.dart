/// 拷打前「先看一遍」预习页（对应 Web `src/reader/panels/DrillWarmup.tsx`）。
///
/// 记忆 / 词块是**闭卷回忆**：直接开考，第一次见到的词只能靠猜，猜错还会
/// 记进错题本 —— 等于把「没见过」当成「没记住」。开考前先把这轮要考的词
/// 连同释义 / 词块摊开看一遍，分数才反映记忆。
///
/// 页面只认 [DrillViewModel] 的预习态 getter，动作也只调它的
/// `setWarmupLimit` / `beginWarmup` / `cancelWarmup`，不碰出题规则。
library;

import 'package:flutter/material.dart';

import '../core/quiz_drill.dart';
import '../core/quiz_warmup.dart';
import '../viewmodels/drill_view_model.dart';

class DrillWarmupView extends StatelessWidget {
  const DrillWarmupView({super.key, required this.vm});

  final DrillViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cards = vm.warmupCards;
    return Column(
      children: <Widget>[
        // 顶部信息条：取消 / 标题 / 本轮词数。
        Container(
          width: double.infinity,
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          child: Row(
            children: <Widget>[
              TextButton(
                key: const ValueKey<String>('drill-warm-cancel'),
                onPressed: vm.cancelWarmup,
                child: const Text('取消'),
              ),
              Expanded(
                child: Text(
                  warmupTitle(vm.kind),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                '这轮要考 ${vm.warmupCount} 个词',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            warmupHint(vm.kind),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // 本轮题数：换数量会重新抽这一轮要看的词（照 Web `setWarmupLimit`）。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: <Widget>[
              Text('本轮', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final n in drillLimitOptions)
                      ChoiceChip(
                        key: ValueKey<String>('drill-warm-limit-$n'),
                        label: Text('$n'),
                        selected: vm.limit == n,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => vm.setWarmupLimit(n),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: cards.isEmpty
              ? const Center(
                  child: Text('这轮没有可预习的词（题目里没有词条信息）。'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: <Widget>[
                    for (final c in cards) ...<Widget>[
                      _WarmupCard(card: c),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
        // 底部功能区吸底：看完了就开考。
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FilledButton.icon(
                    key: const ValueKey<String>('drill-warm-start'),
                    onPressed: vm.beginWarmup,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('看完了，开始拷打'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '开考后按题型作答；答对推进 SRS，答错进错题本',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WarmupCard extends StatelessWidget {
  const _WarmupCard({required this.card});

  final DrillWarmupCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(card.word, style: theme.textTheme.titleLarge),
                if ((card.phonetic ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    card.phonetic!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if ((card.meaning ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(card.meaning!, style: theme.textTheme.bodyMedium),
              ),
            if (card.chunks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final s in card.chunks)
                      Text(
                        '• $s',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            if ((card.example ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  card.example!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
