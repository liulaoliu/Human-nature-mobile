/// 精读工作流：一篇材料从「看懂大意」到「能产出」的七步。
///
/// 对齐 Web 版 `src/reader/panels/IntensivePanel.tsx`：顶部是等级与总进度，
/// 中间是「下一步」卡（只给一个按钮，免得用户不知道先做哪个），下面是七步清单，
/// 每步带进度条和一个跳转按钮 —— 点下去真的会去那个工具页。
///
/// **仿写在这里**（第 6 步「产出（仿写）」），不再占首页一张卡：它是精读流程里的一环。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/intensive.dart';
import '../viewmodels/intensive_view_model.dart';
import '../widgets/status_bar.dart';
import 'ai_batch_page.dart';
import 'article_picker.dart';
import 'drill_page.dart';
import 'intensive_extras.dart';
import 'reader_page.dart';
import 'speed_read_page.dart';
import 'study_page.dart';
import 'writing_page.dart';

class IntensivePage extends StatefulWidget {
  const IntensivePage({super.key});

  @override
  State<IntensivePage> createState() => _IntensivePageState();
}

class _IntensivePageState extends State<IntensivePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<IntensiveViewModel>().bootstrap();
    });
  }

  Future<void> _pick() async {
    final vm = context.read<IntensiveViewModel>();
    final id = await pickArticle(
      context,
      articles: vm.currentArticle?.articles ?? const [],
      currentId: vm.articleId,
      title: '精读哪一篇',
    );
    if (id != null && mounted) await vm.openArticle(id);
  }

  /// 每个阶段的按钮点下去去哪。
  void _go(IntensiveStageKey key) {
    final page = switch (key) {
      // 通读 → 速读；标词 / 词块 / 理解 → AI 跑批补数据（Web 也是同一个跑批）
      IntensiveStageKey.skim => const SpeedReadPage(),
      IntensiveStageKey.vocab => const AiBatchPage(),
      IntensiveStageKey.chunks => const AiBatchPage(),
      IntensiveStageKey.comprehend => const ReaderPage(),
      IntensiveStageKey.recall => const StudyPage(),
      IntensiveStageKey.produce => const WritingPage(),
      IntensiveStageKey.grammar => const DrillPage(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IntensiveViewModel>();
    final plan = vm.plan;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('精读工作流'),
        actions: [
          IconButton(
            key: const ValueKey('intensive-pick'),
            tooltip: '换一篇',
            icon: const Icon(Icons.swap_horiz),
            onPressed: vm.busy ? null : _pick,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: vm.hasArticle
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        _HeadCard(plan: plan, title: vm.title),
                        const SizedBox(height: 12),
                        _NextCard(plan: plan, onGo: _go),
                        const SizedBox(height: 12),
                        _SkimTile(vm: vm),
                        const SizedBox(height: 12),
                        IntensiveOutputCard(vm: vm),
                        const SizedBox(height: 12),
                        for (final stage in plan.stages)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _StageCard(stage: stage, onGo: () => _go(stage.key)),
                          ),
                        const SizedBox(height: 4),
                        IntensiveRetellCard(vm: vm),
                        const SizedBox(height: 12),
                        IntensiveHistoryCard(vm: vm),
                        const SizedBox(height: 12),
                        Text(
                          '顺序是从上往下：先看懂大意，再把词和句子收干净，'
                          '然后才背、才写、才练语法。跳着做也不会坏，只是这一步的进度会一直空着。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                      ],
                    )
                  : _EmptyState(onPick: _pick),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeadCard extends StatelessWidget {
  const _HeadCard({required this.plan, required this.title});

  final IntensivePlan plan;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🎯', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '精读工作流',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    plan.levelLabel,
                    style: theme.textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: plan.progress / 100,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('总进度 ${plan.progress}%', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              plan.levelDesc,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.plan, required this.onGo});

  final IntensivePlan plan;
  final void Function(IntensiveStageKey) onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = plan.nextKey;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('下一步', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
              plan.nextLabel,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              plan.nextHint,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 10),
            if (key != null)
              FilledButton.icon(
                key: const ValueKey('intensive-next'),
                onPressed: () => onGo(key),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('开始这一步'),
              )
            else
              Text(
                '本篇已精读到位 🎉 隔天按到期复习即可',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _SkimTile extends StatelessWidget {
  const _SkimTile({required this.vm});

  final IntensiveViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        key: const ValueKey('intensive-skimmed'),
        value: vm.skimmed,
        onChanged: (_) => vm.toggleSkimmed(),
        title: const Text('已通读（看懂大意）'),
        subtitle: const Text('速读过一遍、能看懂大意就勾上；这是第 1 步的进度'),
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.stage, required this.onGo});

  final IntensiveStage stage;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (badgeText, badgeBg, badgeFg) = switch (stage.status) {
      IntensiveStageStatus.done => ('完成', scheme.primaryContainer, scheme.onPrimaryContainer),
      IntensiveStageStatus.doing => ('进行中', scheme.tertiaryContainer, scheme.onTertiaryContainer),
      IntensiveStageStatus.todo => ('待做', scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(stage.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    stage.label,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(10)),
                  child: Text(badgeText, style: theme.textTheme.labelSmall?.copyWith(color: badgeFg)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              stage.detail,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: stage.progress / 100, minHeight: 4),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${stage.progress}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: ValueKey('intensive-go-${stage.key.name}'),
                onPressed: stage.enabled ? onGo : null,
                child: Text(stage.action),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '还没选文章',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '精读工作流是「按篇」算的：先挑一篇，七步的进度才有分母。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('intensive-pick-empty'),
              onPressed: onPick,
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('挑一篇'),
            ),
          ],
        ),
      ),
    );
  }
}
