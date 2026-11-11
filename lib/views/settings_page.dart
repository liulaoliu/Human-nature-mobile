/// 设置页：以后所有设置都放这里（首页侧边栏进）。
///
/// 为什么设置不放在练习页里：背单词页天天要开，设置一周改一次。挤在一起既占地方，
/// 又容易在练习中途误触（Web 版左栏那排按钮就是这个毛病）。
///
/// 范围与牌组例外：它们每天可能换，所以挪到首页「背单词」那一行的小按键里，
/// 这里只留「背诵设置」（每组词数 / 每天新词上限 / 锤炼阈值 / 卡面拼写）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/study_prefs.dart';
import '../viewmodels/study_view_model.dart';

/// 设置页。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            _StudySection(),
            SizedBox(height: 16),
            _AboutSection(),
          ],
        ),
      ),
    );
  }
}

/// 背诵设置（持久化在 `study:prefs`）。
class _StudySection extends StatelessWidget {
  const _StudySection();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyViewModel>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('背诵设置', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '范围和牌组在首页「背单词」那一行的小按键里改（每天都可能换）。',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            Text('每组词数', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final n in const [0, 5, 10, 20, 50])
                  ChoiceChip(
                    label: Text(n == 0 ? '每组跟本篇' : '$n'),
                    selected: vm.groupSize == n,
                    onSelected: (_) => vm.settings.setGroupSize(n),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('每天新词上限', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final n in const [0, 10, 20, 30, 50])
                  ChoiceChip(
                    label: Text(n == 0 ? '新词不限' : '$n'),
                    selected: vm.newLimit == n,
                    onSelected: (_) => vm.settings.setNewLimit(n),
                  ),
              ],
            ),
            if (vm.newLimit > 0) ...[
              const SizedBox(height: 6),
              Text(
                '今天已引入 ${vm.newToday}/${vm.newLimit}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            const SizedBox(height: 16),
            Text('卡停多久算「锤炼」', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final n in drillAfterChoices)
                  ChoiceChip(
                    label: Text(n == 0 ? '不锤炼' : '$n 秒'),
                    selected: vm.prefs.drillAfter == n,
                    onSelected: (_) => vm.settings.setDrillAfter(n),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '停太久说明没进脑子：过一遍拼写 / 选义 / 搭配才允许评分。',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('卡面拼写'),
              subtitle: const Text('看到释义直接拼单词，不先翻面'),
              value: vm.prefs.spelling,
              onChanged: (v) => vm.settings.setSpelling(v),
            ),
          ],
        ),
      ),
    );
  }
}

/// 关于。
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('关于', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'D哥帮你办 · 精读 / 背单词 / 速读 / 产出训练 / 小课堂 / 金句课',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
