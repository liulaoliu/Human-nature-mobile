/// 首页「背单词」那一行的快捷设置：范围 + 牌组。
///
/// 为什么这两项留在首页而不是设置页：它们**每天**都可能换（今天背本篇、明天背
/// 全部；这周背单词、下周背搭配），进设置页改太重。其余（每组词数、每天新词上限、
/// 锤炼阈值、卡面拼写）一周改不了几次，才放设置页。
///
/// 改完立刻落盘（走 `StudySettings` 的 `study:prefs`），下次开 App 还是这个组合。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/entry_kind.dart' show StudyDeck;
import '../core/study_pool.dart';
import '../viewmodels/study_view_model.dart';

/// 打开快捷设置面板。
Future<void> showStudyQuickSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<StudyViewModel>.value(
      value: context.read<StudyViewModel>(),
      child: const _StudyQuickSheet(),
    ),
  );
}

class _StudyQuickSheet extends StatelessWidget {
  const _StudyQuickSheet();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyViewModel>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('背单词的范围与牌组', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '改完就存住，下次打开还是这套。',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            Text('范围', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final scope in StudyScope.values)
                  ChoiceChip(
                    label: Text(studyScopeLabel[scope] ?? scope.name),
                    selected: vm.scope == scope,
                    onSelected: (_) => vm.settings.setScope(scope),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('牌组', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<StudyDeck>(
              segments: const [
                ButtonSegment(value: StudyDeck.word, label: Text('单词')),
                ButtonSegment(value: StudyDeck.collocation, label: Text('搭配')),
              ],
              selected: {vm.deck},
              onSelectionChanged: (s) => vm.settings.setDeck(s.first),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '候选 ${vm.poolCounts.total} 个',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(width: 12),
                Text(
                  '该复习 ${vm.poolCounts.due} · 没学过 ${vm.poolCounts.fresh}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('好了'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
