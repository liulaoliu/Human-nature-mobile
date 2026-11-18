/// 朗读设置：三档引擎（系统 / 离线神经 / Edge 在线）+ 每档的音色 + 试听。
///
/// 为什么要有这一页：App 里六处朗读（精读点句、背单词、拷打、考试、速读、跟读）
/// 用的是同一份选择，摊在各自页面上会变成六份互相打架的开关。
/// 用户 2026-11-15 要求「像 Web 端那样能选」，所以这里按「档位 → 音色」
/// 两级放，选完立刻能试听，听不顺再换。
///
/// 布局照 `docs/ARCHITECTURE.md` §三·六：长滚动列表，功能区（试听）吸底。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/tts_engine.dart';
import '../core/tts_provider.dart';
import '../viewmodels/tts_view_model.dart';

/// 朗读设置页。
class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final vm = context.watch<TtsViewModel>();
    final info = ttsProviderInfos;

    return Scaffold(
      appBar: AppBar(title: const Text('朗读设置')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('用哪一档朗读', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final item in info) ...[
                    _ProviderCard(
                      info: item,
                      selected: vm.provider == item.provider,
                      onTap: () => vm.setProvider(item.provider),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (vm.voiceOptions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('音色', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      child: RadioGroup<String>(
                        groupValue: vm.voice,
                        onChanged: (String? v) => vm.setVoice(v),
                        child: Column(
                          children: [
                            for (final voice in vm.voiceOptions)
                              RadioListTile<String>(
                                key: ValueKey<String>('tts-voice-${voice.id}'),
                                value: voice.id,
                                title: Text(voice.label),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text('语速', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _RateSection(vm: vm),
                  if (vm.provider == TtsProvider.system) ...[
                    const SizedBox(height: 8),
                    const _SystemEnginePicker(),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '改完立刻生效，全 App 的朗读一起换 —— 这几项记在本机，重启也还在。'
                    '语速按档分开记：调 Kitten 的快慢不会动到 Kokoro 和 Edge。',
                    style: theme.textTheme.bodySmall?.copyWith(color: dim),
                  ),
                ],
              ),
            ),
            _PreviewBar(vm: vm),
          ],
        ),
      ),
    );
  }
}

/// 一档引擎的卡片。
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final TtsProviderInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey<String>('tts-provider-${info.provider.name}'),
      margin: EdgeInsets.zero,
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: ListTile(
        leading: Icon(
          info.offline ? Icons.offline_bolt_outlined : Icons.cloud_outlined,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text(info.label),
        subtitle: Text(info.hint, style: theme.textTheme.bodySmall),
        trailing: selected
            ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// 当前这一档的语速滑块。
///
/// 为什么放在这一页而不是「跟读设置」：用户 2026-11-17 反馈「Kitten 有点慢，
/// 想调」。原来只有一个 `shadowing.ui.speechRate`（跟读页在用，速读那个
/// WPM 是完全不同的东西，只算进度条目标时间），而六处朗读里只有跟读页
/// 会在 bootstrap 时把它推给朗读器，其它五处永远是默认值。
///
/// 现在按 `TtsProvider` 各存一份：同一句换档听感差一大截，共用一个值
/// 等于逼用户每换一次档重调一次。
class _RateSection extends StatelessWidget {
  const _RateSection({required this.vm});

  final TtsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (vm.rate * 100).round();
    final maxRate = maxTtsRateOf(vm.provider);
    // 0.05 一格：系统档 0.1–1.0 是 18 格，神经档 0.1–1.5 是 28 格。
    final divisions = ((maxRate - minTtsRate) / 0.05).round();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '朗读语速 $percent%',
                    key: const ValueKey<String>('tts-rate-label'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  key: const ValueKey<String>('tts-rate-reset'),
                  onPressed: vm.rate == defaultTtsRateOf(vm.provider)
                      ? null
                      : () => vm.setRate(defaultTtsRateOf(vm.provider)),
                  child: const Text('恢复默认'),
                ),
              ],
            ),
            Slider(
              key: const ValueKey<String>('tts-rate-slider'),
              value: vm.rate.clamp(minTtsRate, maxRate),
              min: minTtsRate,
              max: maxRate,
              divisions: divisions,
              label: '$percent%',
              onChanged: (double v) => vm.setRate(v),
            ),
            Text(
              '每档单独记。$percent% 只是这一档的值；换到别的档会用它自己的。',
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

/// 系统档专用的「用哪个合成器」（手机里装了多个 TTS 时才不是空表）。
class _SystemEnginePicker extends StatelessWidget {
  const _SystemEnginePicker();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.read<TtsViewModel>();
    return FutureBuilder<List<SpeechEngine>>(
      future: vm.systemEngines(),
      builder: (context, snap) {
        final engines = snap.data ?? const <SpeechEngine>[];
        if (engines.isEmpty) {
          return Text(
            '这台手机只有一个系统合成器，音色跟着手机设置走。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('系统合成器', style: theme.textTheme.titleSmall),
              ),
              RadioGroup<String>(
                groupValue: vm.systemEngine,
                onChanged: (String? v) => vm.setSystemEngine(v),
                child: Column(
                  children: [
                    for (final e in engines)
                      RadioListTile<String>(
                        key: ValueKey<String>('tts-engine-${e.name}'),
                        value: e.name,
                        title: Text(e.label),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 吸底的试听条。
class _PreviewBar extends StatelessWidget {
  const _PreviewBar({required this.vm});

  final TtsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
            children: [
              Text(
                '试听：${ttsProviderLabel[vm.provider]} · ${vm.voiceLabel}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // 降级提示贴在这里而不是列表底部：试听条是用户点完按钮后视线
              // 还在的地方。2026-11-15 的 bug 报告就是「换了音色没变化」——
              // 其实是这一档没出声、静默退回了系统朗读，而提示在列表最下面
              // 没人看见。
              if (vm.fellBack) ...[
                const SizedBox(height: 6),
                Text(
                  vm.fallbackReason ?? '这一次用的是系统朗读（原来的档位没读出来）。',
                  key: const ValueKey<String>('tts-fallback-note'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey<String>('tts-preview'),
                onPressed: () => vm.preview(),
                icon: const Icon(Icons.play_arrow),
                label: const Text('试听一句'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
