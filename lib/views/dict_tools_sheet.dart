/// 「⚡ 一键处理」面板：五步清单 + 单独跑 / 一键跑 + 每步结果。
///
/// 状态在 `viewmodels/dict_tools_view_model.dart`，动作在
/// `services/dict_tools_service.dart`；这里只画。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auto_vocab.dart' show autoVocabLevelLabel;
import '../core/dict_tools.dart';
import '../core/ecdict.dart' show EcdictLevel;
import '../services/dict_tools_service.dart' show DictStepOutcome, DictStepStatus;
import '../viewmodels/current_article_view_model.dart';
import '../viewmodels/dict_tools_view_model.dart';

/// 一键处理底部面板。打开时自动加载离线词典（已加载则直接可用）。
class DictToolsSheet extends StatefulWidget {
  const DictToolsSheet({super.key});

  @override
  State<DictToolsSheet> createState() => _DictToolsSheetState();
}

class _DictToolsSheetState extends State<DictToolsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DictToolsViewModel>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DictToolsViewModel>();
    final articleId = context.watch<CurrentArticleViewModel>().articleId;
    final theme = Theme.of(context);
    final blocker = dictToolsBlocker(
      dictionaryReady: vm.dictionaryReady,
      examplesReady: vm.examplesReady,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('⚡ 一键处理', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              '五步都在本机跑，不联网；每步可以单独重跑。顺序：挑词 → 补齐 → 例句 → 原形 → 混淆。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.school_outlined, size: 18),
                const SizedBox(width: 8),
                const Text('挑词水平'),
                const Spacer(),
                DropdownButton<EcdictLevel>(
                  key: const ValueKey('dict-tools-level'),
                  value: vm.level,
                  isDense: true,
                  onChanged: vm.busy
                      ? null
                      : (v) {
                          if (v != null) vm.setLevel(v);
                        },
                  items: [
                    for (final level in EcdictLevel.values)
                      DropdownMenuItem(
                        value: level,
                        child: Text(autoVocabLevelLabel[level] ?? level.name),
                      ),
                  ],
                ),
              ],
            ),
            if (articleId == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '没选文章：挑词那步会跳过；其余四步照常。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (vm.loadingDictionary) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text('正在加载离线词典…', style: theme.textTheme.bodySmall),
            ],
            const Divider(height: 20),
            for (final step in dictToolSteps)
              _StepTile(
                step: step,
                outcome: vm.outcomeOf(step.id),
                running: vm.runningStep == step.id,
                enabled: vm.enabled(step.id, hasArticle: articleId != null),
                onRun: () => vm.runStep(step.id, articleId: articleId),
              ),
            if (vm.error != null) ...[
              const SizedBox(height: 4),
              Text(
                vm.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (vm.notice.isNotEmpty && vm.error == null) ...[
              const SizedBox(height: 4),
              Text(
                vm.notice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (blocker.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(blocker, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('dict-tools-run-all'),
                onPressed: vm.busy || !vm.dictionaryReady
                    ? null
                    : () => vm.runAll(articleId: articleId),
                child: Text(vm.busy ? '处理中…' : '一键跑完五步'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.outcome,
    required this.running,
    required this.enabled,
    required this.onRun,
  });

  final DictToolStep step;
  final DictStepOutcome? outcome;
  final bool running;
  final bool enabled;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (outcome?.status) {
      DictStepStatus.failed => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: _leading(theme),
      title: Text(step.label),
      subtitle: Text(
        outcome == null ? step.hint : '${step.hint}\n${outcome!.message}',
        key: ValueKey('dict-tools-outcome-${step.id}'),
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
      trailing: TextButton(
        key: ValueKey('dict-tools-run-${step.id}'),
        onPressed: enabled ? onRun : null,
        child: Text(running ? '…' : '跑'),
      ),
    );
  }

  Widget _leading(ThemeData theme) {
    if (running) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return switch (outcome?.status) {
      DictStepStatus.ok => Icon(
          Icons.check_circle,
          size: 18,
          color: theme.colorScheme.primary,
        ),
      DictStepStatus.skipped => const Icon(Icons.skip_next, size: 18),
      DictStepStatus.failed => Icon(
          Icons.error_outline,
          size: 18,
          color: theme.colorScheme.error,
        ),
      null => Icon(
          Icons.radio_button_unchecked,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
    };
  }
}
