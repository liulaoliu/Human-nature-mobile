/// 设置页：以后所有设置都放这里（首页侧边栏进）。
///
/// 为什么设置不放在练习页里：背单词页天天要开，设置一周改一次。挤在一起既占地方，
/// 又容易在练习中途误触（Web 版左栏那排按钮就是这个毛病）。
///
/// 例外：牌组（单词 / 搭配）每天可能换，挪到首页「背单词」那一行的小按键里；
/// 学哪一批（学习 / 复习 / 回顾）在背单词页选。这里只留「背诵设置」与「朗读」。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/study_prefs.dart';
import '../core/tts_engine.dart' show speechEngineLabel;
import '../viewmodels/shadowing_view_model.dart';
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
            _SpeechSection(),
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
              '牌组在首页「背单词」那一行的小按键里改（每天都可能换）；'
          '学哪一批（学习 / 复习 / 回顾）在背单词页选。',
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

/// 朗读设置（引擎 / 语速）。持久化：引擎 `tts:engine`、语速 `shadowing.ui.speechRate`。
///
/// 为什么不把引擎选项塞进跟读页：换引擎是一辈子改一次的事，
/// 而跟读页每一句都在用；放那儿既占位置又容易在跟读中途误触。
class _SpeechSection extends StatelessWidget {
  const _SpeechSection();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ShadowingViewModel>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // 引擎列表与选中项在 `picker` 自己身上（它是 ChangeNotifier），
    // 换引擎只会通知它，所以这一块要自己听它 —— 听 vm 不会重建。
    final picker = vm.speechEngine;
    return ListenableBuilder(
      listenable: picker,
      builder: (BuildContext context, Widget? _) {
        final engines = picker.engines;
        final selected = engines.any((e) => e.name == picker.selected)
            ? picker.selected
            : null;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('朗读', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '跟读页的「听标准音」用这个引擎；语言固定 en-US。'
                  '换引擎之后第一次朗读会慢一点点。',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 16),
                if (!picker.available)
                  Text(
                    '这台设备的朗读器不支持挑引擎，会用系统默认。',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  )
                else ...[
                  DropdownButtonFormField<String?>(
                    // 引擎列表是异步取的，取到之前只有「系统默认」一项。
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '合成引擎',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('系统默认'),
                      ),
                      for (final e in engines)
                        DropdownMenuItem<String?>(
                          value: e.name,
                          child: Text(
                            speechEngineLabel(e),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: picker.select,
                  ),
                  if (engines.isEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      '没读到本机的引擎列表（有些系统不给），现在用系统默认。',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                Text(
                  '朗读语速 ${(vm.prefs.speechRate * 100).round()}%',
                  style: theme.textTheme.titleSmall,
                ),
                Slider(
                  value: vm.prefs.speechRate.clamp(0.1, 1.0),
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  label: '${(vm.prefs.speechRate * 100).round()}%',
                  onChanged: (v) => vm.setRate(v),
                ),
                Text(
                  '调到能听清又跟得上就行；跟读页里也能临时改，改完会记住。',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        );
      },
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
