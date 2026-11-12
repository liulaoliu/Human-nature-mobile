import 'package:dlaoshi_app/core/shadowing_prefs.dart';
import 'package:dlaoshi_app/core/shadowing_take.dart';
import 'package:dlaoshi_app/viewmodels/shadowing_view_model.dart';
import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

/// 跟读页：选文章 → 一句一句「听 → 读 → 判」。
///
/// 三段式（吸顶 / 滚动 / 吸底）：上面是文章与进度，中间滚原文，下面是三个动作。
/// 录音只在当场判「有没有开口、读完没」，**不存音频**（见 `core/ports.dart`）。
class ShadowingPage extends StatefulWidget {
  const ShadowingPage({super.key});

  @override
  State<ShadowingPage> createState() => _ShadowingPageState();
}

class _ShadowingPageState extends State<ShadowingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ShadowingViewModel>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ShadowingViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('跟读'),
        actions: <Widget>[
          if (vm.hasArticle)
            TextButton(
              onPressed: () => vm.openArticle(null),
              child: const Text('换文章'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            if (vm.notice.isNotEmpty)
              StatusBar.notice(message: vm.notice, onClose: vm.clearNotice),
            if (!vm.hasArticle)
              Expanded(child: _ArticlePicker(vm: vm))
            else ...<Widget>[
              _TopBar(vm: vm),
              Expanded(child: _ScriptBody(vm: vm)),
              _BottomBar(vm: vm),
            ],
          ],
        ),
      ),
    );
  }
}

/// 还没选文章时：列出文章。
class _ArticlePicker extends StatelessWidget {
  const _ArticlePicker({required this.vm});

  final ShadowingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (vm.library.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '还没有文章。先去「精读」粘一篇原文，再回来跟读。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text('挑一篇来跟读', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final row in vm.library)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(row.title),
              subtitle: Text(row.updatedAt),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => vm.openArticle(row.id),
            ),
          ),
      ],
    );
  }
}

/// 吸顶：第几句 / 共几句 + 语速 / 静音时长。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.vm});

  final ShadowingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '第 ${vm.index + 1}/${vm.sentences.length} 句 · 约 ${vm.estimatedSec.toStringAsFixed(1)} 秒',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: '上一句',
            onPressed: vm.hasPrev ? vm.prev : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: '下一句',
            onPressed: vm.hasNext ? vm.next : null,
            icon: const Icon(Icons.chevron_right),
          ),
          PopupMenuButton<String>(
            tooltip: '显示方式',
            icon: const Icon(Icons.tune),
            onSelected: (String v) {
              final mode = ShadowingViewMode.byId(v);
              if (mode != null) vm.setViewMode(mode);
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              for (final m in shadowingViewModes)
                PopupMenuItem<String>(
                  value: m.id,
                  child: Text('显示：${_modeLabel(m)}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _modeLabel(ShadowingViewMode mode) => switch (mode) {
      ShadowingViewMode.full => '整篇',
      ShadowingViewMode.focus => '聚焦',
      ShadowingViewMode.block => '单块',
    };

/// 中间滚动区：按显示模式画原文。
class _ScriptBody extends StatelessWidget {
  const _ScriptBody({required this.vm});

  final ShadowingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sentences = vm.sentences;
    final current = vm.index;

    if (vm.prefs.viewMode == ShadowingViewMode.block) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          Text(
            vm.text,
            style: theme.textTheme.headlineSmall?.copyWith(height: 1.5),
          ),
          if (vm.sentence?.translation != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              vm.sentence!.translation!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          _VerdictCard(vm: vm),
        ],
      );
    }

    final focus = vm.prefs.viewMode == ShadowingViewMode.focus;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        for (var i = 0; i < sentences.length; i++)
          GestureDetector(
            onTap: () => vm.select(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                sentences[i].text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.5,
                  // 聚焦模式：只把当前句提亮，其余压暗；整篇模式一样亮。
                  color: !focus || i == current
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.45,
                        ),
                  fontWeight: i == current ? FontWeight.w600 : null,
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        _VerdictCard(vm: vm),
      ],
    );
  }
}

/// 上一次的判定 + 时长 + 电平条。
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.vm});

  final ShadowingViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdict = vm.verdict;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              vm.recording ? '正在录…' : (verdict == null ? '点下面的「读这一句」' : takeVerdictLabel(verdict)),
              style: theme.textTheme.titleMedium?.copyWith(
                color: verdict == null || verdict == TakeVerdict.ok
                    ? null
                    : theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            if (vm.recording || vm.elapsedMs > 0)
              Text(
                '录了 ${(vm.elapsedMs / 1000).toStringAsFixed(1)} 秒'
                '（参考 ${vm.estimatedSec.toStringAsFixed(1)} 秒）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (vm.recording) ...<Widget>[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: vm.level.clamp(0.0, 1.0)),
            ],
            // 录完才给「听自己读的」：读之前这个按钮没有任何东西可放。
            if (vm.hasTake && !vm.recording) ...<Widget>[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: vm.playingBack ? vm.stopPlayback : vm.playTake,
                  icon: Icon(
                    vm.playingBack ? Icons.stop_circle_outlined : Icons.hearing,
                  ),
                  label: Text(vm.playingBack ? '停下' : '听自己读的'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 吸底：听 / 读 / 停。
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.vm});

  final ShadowingViewModel vm;

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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: vm.playing ? null : vm.play,
              icon: const Icon(Icons.volume_up),
              label: Text(vm.playing ? '正在读…' : '听标准音'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: vm.recording ? vm.stopRecording : vm.startRecording,
              icon: Icon(vm.recording ? Icons.stop : Icons.mic),
              label: Text(vm.recording ? '停（现在判）' : '读这一句'),
            ),
          ),
        ],
      ),
    );
  }
}


