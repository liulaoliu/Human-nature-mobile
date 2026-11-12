/// 速读设置：语速与「超时就拷打」。
///
/// 为什么从速读页搬到这里：速读页打开是「挑一篇来读」，语速是**一次定好、长期有效**
/// 的偏好，摊在选篇页顶部既占地方又容易误触。搬过来以后速读页只剩选篇和正文。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/speed_read.dart' show minWpm, maxWpm, defaultWpm;
import '../viewmodels/speed_read_view_model.dart';

/// 速读设置页。
class SpeedSettingsPage extends StatelessWidget {
  const SpeedSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final vm = context.watch<SpeedReadViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('速读设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('语速', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        Text(
                          '${vm.wpm} 词/分钟',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '一句话读多久算达标，是按时长算的：词数 ÷ 语速，每句再多给 1.5 秒。'
                      '读超了这句就记「慢」。',
                      style: theme.textTheme.bodySmall?.copyWith(color: dim),
                    ),
                    Slider(
                      value: vm.wpm.toDouble(),
                      min: minWpm.toDouble(),
                      max: maxWpm.toDouble(),
                      divisions: (maxWpm - minWpm) ~/ 10,
                      label: '${vm.wpm}',
                      onChanged: (v) => vm.setWpm(v.round()),
                    ),
                    Row(
                      children: [
                        Text(
                          '$minWpm',
                          style: theme.textTheme.bodySmall?.copyWith(color: dim),
                        ),
                        const Spacer(),
                        Text(
                          '默认 $defaultWpm',
                          style: theme.textTheme.bodySmall?.copyWith(color: dim),
                        ),
                        const Spacer(),
                        Text(
                          '$maxWpm',
                          style: theme.textTheme.bodySmall?.copyWith(color: dim),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                value: vm.autoDrill,
                title: const Text('超时就拷打'),
                subtitle: Text(
                  '读超目标时长的句子，读完要选词填空；关掉就只标「慢」。',
                  style: theme.textTheme.bodySmall?.copyWith(color: dim),
                ),
                onChanged: vm.setAutoDrill,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '改完就生效，不用保存 —— 这两项记在本机，重启也还在。',
              style: theme.textTheme.bodySmall?.copyWith(color: dim),
            ),
          ],
        ),
      ),
    );
  }
}
