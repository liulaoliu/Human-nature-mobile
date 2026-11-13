/// 「AI-Batch Work」面板：阅读页顶栏那条默认收起的横条 + 展开后的进度 / 清单。
///
/// 为什么不做成独立页面：跑批是「读这篇文章时顺手把这篇的生词补齐」，
/// 离开这篇文章就没有意义了。所以它挂在阅读页最上方，收起时只占一行，
/// 展开才有进度条、按钮和任务清单 —— 不打断阅读，也不占一个首页入口。
///
/// 连接设置（地址 / key / 模型）搬去了「设置 → AI-deepseek 设置」
/// （`ai_settings_page.dart`）：一次配好，文章页只管点开始。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/ai_jobs.dart' show AiJob;
import '../theme/app_skin.dart' show SkinColors;
import '../viewmodels/ai_batch_view_model.dart';

/// 阅读页顶部的跑批横条：收起时一行摘要，展开是进度 + 任务清单。
class AiBatchBar extends StatefulWidget {
  const AiBatchBar({super.key, required this.articleId});

  /// 当前文章的 id：换了文章要重新算待办（待办只属于这一篇）。
  final String articleId;

  @override
  State<AiBatchBar> createState() => _AiBatchBarState();
}

class _AiBatchBarState extends State<AiBatchBar> {
  bool _expanded = false;

  /// 上一次算待办用的文章 id（换篇要重算）。
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncArticle();
    });
  }

  @override
  void didUpdateWidget(covariant AiBatchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.articleId != widget.articleId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncArticle();
      });
    }
  }

  /// 把 VM 的「要跑的篇」对齐到这一篇，然后重算待办。
  void _syncArticle() {
    final vm = context.read<AiBatchViewModel>();
    if (_loadedFor == widget.articleId && vm.articleId == widget.articleId) {
      return;
    }
    _loadedFor = widget.articleId;
    if (vm.articleId != widget.articleId) {
      vm.setArticle(widget.articleId);
    } else {
      vm.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AiBatchViewModel>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = vm.outcome;
    final summary = vm.jobs.isEmpty
        ? '没有待查的词'
        : '第 ${(vm.index + 1).clamp(1, vm.jobs.length)}/${vm.jobs.length} 块'
            ' · 完成 ${o.doneCount} · 失败 ${o.failedCount}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 收起时就是这一行：点它展开 / 收起。
          InkWell(
            key: const ValueKey('ai-batch-toggle'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: Row(
                children: [
                  Icon(
                    vm.running ? Icons.sync : Icons.smart_toy_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI-Batch Work · $summary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (vm.busy || vm.running)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (vm.error != null) ...[
                    Text(
                      vm.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (vm.notice.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vm.notice,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '知道了',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: vm.clearNotice,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  LinearProgressIndicator(
                    value: vm.jobs.isEmpty ? 0 : o.doneCount / vm.jobs.length,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    vm.jobs.isEmpty
                        ? '这一篇没有待查的词（有释义的不会再跑）。'
                        : '共 ${o.total} 块 · 完成 ${o.doneCount} · 失败 ${o.failedCount}'
                            ' · 还剩 ${o.remaining}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ActionRow(vm: vm),
                  if (vm.jobs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _JobsList(vm: vm),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 开始 / 继续 / 暂停 / 跳过失败。
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.vm});

  final AiBatchViewModel vm;

  @override
  Widget build(BuildContext context) {
    final canStart = !vm.busy && !vm.running && vm.jobs.isNotEmpty;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: const ValueKey('ai-batch-run'),
          onPressed: canStart ? vm.run : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始跑批'),
        ),
        if (vm.paused || vm.outcome.failedCount > 0)
          FilledButton.tonalIcon(
            key: const ValueKey('ai-batch-resume'),
            onPressed: vm.busy ? null : vm.resume,
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('继续'),
          ),
        if (vm.running)
          OutlinedButton.icon(
            key: const ValueKey('ai-batch-pause'),
            onPressed: vm.pause,
            icon: const Icon(Icons.pause),
            label: const Text('暂停'),
          ),
        if (vm.outcome.failedCount > 0)
          OutlinedButton.icon(
            onPressed: vm.skipFailed,
            icon: const Icon(Icons.skip_next),
            label: const Text('跳过失败的'),
          ),
      ],
    );
  }
}

/// 任务清单（展开后才显示）。
class _JobsList extends StatelessWidget {
  const _JobsList({required this.vm});

  final AiBatchViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('任务清单', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        for (var i = 0; i < vm.jobs.length; i++) ...[
          _JobTile(
            job: vm.jobs[i],
            done: vm.doneIds.contains(vm.jobs[i].id),
            failed: vm.failedIds[vm.jobs[i].id],
            active: i == vm.index && vm.running,
          ),
          if (i != vm.jobs.length - 1) const Divider(height: 12),
        ],
      ],
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({
    required this.job,
    required this.done,
    required this.failed,
    required this.active,
  });

  final AiJob job;
  final bool done;
  final String? failed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    IconData icon;
    Color color;
    if (done) {
      icon = Icons.check_circle;
      color = SkinColors.of(context).success;
    } else if (failed != null) {
      icon = Icons.error_outline;
      color = theme.colorScheme.error;
    } else if (active) {
      icon = Icons.play_arrow;
      color = theme.colorScheme.primary;
    } else {
      icon = Icons.radio_button_unchecked;
      color = theme.colorScheme.onSurfaceVariant;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.label, style: theme.textTheme.bodySmall),
              Text(
                '${job.words.length} 个词',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (failed != null)
                Text(
                  failed!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
