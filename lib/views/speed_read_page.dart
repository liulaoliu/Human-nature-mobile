/// 速读页：一句一句读，超时就地拷打。
///
/// 三层分工和别处一致：
///   - 目标时长、挖空、判分、结算都在 `core/speed_read.dart`（纯函数，已测）；
///   - 状态编排在 `viewmodels/speed_read_view_model.dart`；
///   - 本文件只管「摆」和「点」。
///
/// 布局按项目约定吸顶 + 吸底：顶部是进度与读秒，底部是当前阶段的主按钮，
/// 中间正文自己滚 —— 长句子在小屏上也不会把按钮顶出屏幕。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/speed_read.dart';
import '../models/document.dart';
import '../viewmodels/speed_read_view_model.dart';
import '../widgets/status_bar.dart';
import 'sentence_extras.dart';

/// 速读页。
class SpeedReadPage extends StatefulWidget {
  const SpeedReadPage({super.key});

  @override
  State<SpeedReadPage> createState() => _SpeedReadPageState();
}

class _SpeedReadPageState extends State<SpeedReadPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SpeedReadViewModel>().bootstrap();
    });
    // 250ms 只为刷新读秒；读秒本身由 ViewModel 现算，掉帧不会算错时间。
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      context.read<SpeedReadViewModel>().tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SpeedReadViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: Text(vm.hasArticle ? '速读 · 第 ${vm.index + 1} 句' : '速读'),
        actions: [
          if (vm.hasArticle) ...[
            IconButton(
              tooltip: '重来',
              icon: const Icon(Icons.restart_alt),
              onPressed: vm.restart,
            ),
            IconButton(
              tooltip: '换一篇',
              icon: const Icon(Icons.library_books_outlined),
              onPressed: () => vm.openArticle(null),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: vm.hasArticle ? _Reader(vm: vm) : _Picker(vm: vm),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选文章 + 调语速。
class _Picker extends StatelessWidget {
  const _Picker({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsCard(vm: vm),
        const SizedBox(height: 16),
        Text('挑一篇来读', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (vm.library.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              children: [
                Icon(Icons.article_outlined, size: 48, color: dim),
                const SizedBox(height: 12),
                Text('还没有文章', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '先去「精读」粘贴一篇英文，再回来速读。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: dim),
                ),
              ],
            ),
          )
        else
          for (final row in vm.library)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${row.sentenceCount} 句',
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => vm.openArticle(row.id),
            ),
      ],
    );
  }
}

/// 语速与自动拷打。
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('语速', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text('${vm.wpm} 词/分钟', style: theme.textTheme.bodySmall?.copyWith(color: dim)),
              ],
            ),
            Slider(
              value: vm.wpm.toDouble(),
              min: minWpm.toDouble(),
              max: maxWpm.toDouble(),
              divisions: (maxWpm - minWpm) ~/ 10,
              label: '${vm.wpm}',
              onChanged: (v) => vm.setWpm(v.round()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: vm.autoDrill,
              title: const Text('超时就拷打'),
              subtitle: Text(
                '读超目标时长的句子，读完要选词填空；关掉就只标「慢」。',
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
              onChanged: vm.setAutoDrill,
            ),
          ],
        ),
      ),
    );
  }
}

/// 逐句读界面：顶栏吸顶、底栏吸底、正文自己滚。
class _Reader extends StatelessWidget {
  const _Reader({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.sentence;
    if (s == null) return _DoneView(vm: vm);
    return Column(
      children: [
        _TopBar(vm: vm),
        Expanded(child: _Body(vm: vm, sentence: s)),
        _BottomBar(vm: vm),
      ],
    );
  }
}

/// 吸顶：第几句、读秒、进度条。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final target = vm.target;
    final elapsed = vm.elapsedMs;
    final progress = target <= 0 ? 0.0 : (elapsed / target).clamp(0.0, 1.0);
    final over = elapsed > target;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '第 ${vm.index + 1} / ${vm.total} 句',
                style: theme.textTheme.labelLarge,
              ),
              const Spacer(),
              Text(
                _seconds(elapsed),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: over ? theme.colorScheme.error : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                ' / ${_seconds(target)}',
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              color: over ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 正文：原文 / 拷打题 / 揭晓后的译文与语言点。
class _Body extends StatelessWidget {
  const _Body({required this.vm, required this.sentence});

  final SpeedReadViewModel vm;
  final Sentence sentence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final phase = vm.phase;
    final drill = vm.drill;
    final showBlank = (phase == SpeedReadPhase.drill || phase == SpeedReadPhase.drillAnswer) && drill != null;
    final text = showBlank ? drill.prompt : sentence.text;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            text,
            style: theme.textTheme.headlineSmall?.copyWith(height: 1.55),
          ),
          const SizedBox(height: 16),
          if (phase == SpeedReadPhase.reveal || phase == SpeedReadPhase.drillAnswer) _TimingChip(vm: vm),
          if (phase == SpeedReadPhase.reveal) ...[
            const SizedBox(height: 12),
            SentenceExtras(sentence: sentence),
          ],
          if (phase == SpeedReadPhase.drill && drill != null) ...[
            const SizedBox(height: 8),
            Text(
              '超时了。把空里的词选回来：',
              style: theme.textTheme.bodyMedium?.copyWith(color: dim),
            ),
            const SizedBox(height: 8),
            for (final option in drill.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: () => vm.chooseDrill(option),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text(option),
                ),
              ),
          ],
          if (phase == SpeedReadPhase.drillAnswer && drill != null) _DrillResult(vm: vm, drill: drill),
        ],
      ),
    );
  }
}

/// 用时与目标。
class _TimingChip extends StatelessWidget {
  const _TimingChip({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final slow = vm.slow;
    return Row(
      children: [
        Icon(
          slow ? Icons.hourglass_bottom : Icons.check_circle_outline,
          size: 16,
          color: slow ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          slow ? '慢于目标：${_seconds(vm.readMs)}' : '达标：${_seconds(vm.readMs)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: slow ? theme.colorScheme.error : dim,
          ),
        ),
      ],
    );
  }
}

/// 拷打对错。
class _DrillResult extends StatelessWidget {
  const _DrillResult({required this.vm, required this.drill});

  final SpeedReadViewModel vm;
  final SpeedReadDrill drill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = vm.drillOk == true;
    final color = ok ? theme.colorScheme.primary : theme.colorScheme.error;
    return Row(
      children: [
        Icon(ok ? Icons.check_circle : Icons.cancel, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ok ? '对：${drill.answer}' : '应该是：${drill.answer}',
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// 吸底：当前阶段的主按钮。
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final phase = vm.phase;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (vm.rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _summaryOf(vm),
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
            ),
          Row(
            children: [
              if (phase == SpeedReadPhase.read) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: vm.advance,
                    child: const Text('读完了'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => vm.go(1),
                  child: const Text('跳过'),
                ),
              ] else if (phase == SpeedReadPhase.reveal)
                Expanded(
                  child: FilledButton(
                    onPressed: vm.advance,
                    child: Text(vm.slow && vm.autoDrill && vm.drill != null ? '拷打' : '下一句'),
                  ),
                )
              else if (phase == SpeedReadPhase.drill)
                Expanded(
                  child: Text(
                    '选一个词填回去',
                    style: theme.textTheme.bodySmall?.copyWith(color: dim),
                  ),
                )
              else
                Expanded(
                  child: FilledButton(
                    onPressed: vm.advance,
                    child: const Text('继续'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 读完一篇的结算。
class _DoneView extends StatelessWidget {
  const _DoneView({required this.vm});

  final SpeedReadViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final sum = summarize(vm.rows);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.celebration_outlined, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Center(child: Text('这一篇读完了', style: theme.textTheme.titleLarge)),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Metric(label: '句数', value: '${sum.count}'),
                _Metric(label: '平均语速', value: sum.avgWpm > 0 ? '${sum.avgWpm} 词/分钟' : '—'),
                _Metric(label: '慢于目标', value: '${sum.slow} 句'),
                _Metric(
                  label: '拷打',
                  value: sum.drillTotal > 0 ? '${sum.drillCorrect} / ${sum.drillTotal} 对' : '没触发',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: vm.restart, child: const Text('再读一遍')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => vm.openArticle(null),
          child: Text('换一篇', style: TextStyle(color: dim)),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )),
          const Spacer(),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// `1234ms` → `1.2s`。
String _seconds(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';

String _summaryOf(SpeedReadViewModel vm) {
  final sum = summarize(vm.rows);
  final parts = <String>['已读 ${sum.count} 句'];
  if (sum.avgWpm > 0) parts.add('${sum.avgWpm} 词/分');
  if (sum.slow > 0) parts.add('慢 ${sum.slow}');
  if (sum.drillTotal > 0) parts.add('拷打 ${sum.drillCorrect}/${sum.drillTotal}');
  return parts.join(' · ');
}
