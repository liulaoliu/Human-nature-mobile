import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/production.dart';
import '../core/production_history.dart';
import '../core/production_task.dart';
import '../core/writing.dart';
import '../viewmodels/production_view_model.dart';

/// 历史页：统计、近七天趋势、常错的地方、按题分组的逐稿记录。
///
/// 全部从 [ProductionViewModel.history] 现算（`writing_records` 是唯一事实来源），
/// 本页不存任何状态。
class ProductionHistoryView extends StatefulWidget {
  const ProductionHistoryView({super.key});

  @override
  State<ProductionHistoryView> createState() => _ProductionHistoryViewState();
}

class _ProductionHistoryViewState extends State<ProductionHistoryView> {
  ProductionMode? _modeFilter;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductionViewModel>();
    final all = productionRecords(vm.history);
    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '还没有产出记录。练几题，这里就会有统计。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    final records = _modeFilter == null
        ? all
        : all
            .where((WritingRecord r) =>
                productionTaskOf(r)?.mode == _modeFilter)
            .toList();
    final stats = productionStats(records);
    final trend = productionTrend(
      records,
      DateTime.now().toUtc().toIso8601String(),
    );
    final errors = productionTopErrors(records);
    final groups = groupProductionAttempts(records);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _ModeFilter(
          value: _modeFilter,
          onChanged: (ProductionMode? m) => setState(() => _modeFilter = m),
        ),
        const SizedBox(height: 12),
        _StatsCard(stats: stats, trend: trend),
        const SizedBox(height: 12),
        if (errors.isNotEmpty) _ErrorsCard(errors: errors),
        if (errors.isNotEmpty) const SizedBox(height: 12),
        _GroupsList(groups: groups),
      ],
    );
  }
}

/// 按吃法过滤（全脂 / 脱脂奶 / 风味酸奶）。
class _ModeFilter extends StatelessWidget {
  const _ModeFilter({required this.value, required this.onChanged});

  final ProductionMode? value;
  final ValueChanged<ProductionMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: <Widget>[
        ChoiceChip(
          label: const Text('全部'),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final m in ProductionMode.values)
          ChoiceChip(
            label: Text(productionModeLabel[m] ?? m.name),
            selected: value == m,
            onSelected: (_) => onChanged(m),
          ),
      ],
    );
  }
}

/// 总览：题数、平均分、目标块命中率、近七天。
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.trend});

  final ProductionStats stats;
  final ProductionTrend trend;

  @override
  Widget build(BuildContext context) {
    final hit = (stats.hitRate * 100).round();
    final recent = (trend.recentHitRate * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('总览', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: <Widget>[
                _Metric(label: '稿数', value: '${stats.attempts}'),
                _Metric(label: '组数', value: '${stats.sessions}'),
                _Metric(label: '重写', value: '${stats.rewrites}'),
                _Metric(
                  label: '平均分',
                  value: stats.avgScore == 0
                      ? '—'
                      : stats.avgScore.toStringAsFixed(1),
                ),
                _Metric(
                  label: '目标块命中',
                  value: stats.targetAttempts == 0 ? '—' : '$hit%',
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              '近七天：${trend.recentAttempts} 稿'
              '${trend.recentAttempts == 0 ? '' : '，命中 $recent%'}'
              '${trend.rewriteGain == 0 ? '' : '，重写提分 ${trend.rewriteGain.toStringAsFixed(1)}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (stats.modes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final entry in stats.modes.entries)
                    Chip(
                      label: Text('${_modeName(entry.key)} ${entry.value}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _modeName(String raw) {
    for (final m in ProductionMode.values) {
      if (m.name == raw) return productionModeLabel[m] ?? raw;
    }
    return raw;
  }
}

/// 一个数字 + 说明。
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// 常错的地方（按 rule + key 聚合）。
class _ErrorsCard extends StatelessWidget {
  const _ErrorsCard({required this.errors});

  final List<ProductionErrorStat> errors;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('常错的地方', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final e in errors)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(
                    '${e.count}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text(WritingRule.byId(e.rule)?.label ?? e.rule),
                subtitle: e.sample.isEmpty
                    ? null
                    : Text(e.sample, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ),
    );
  }
}

/// 按题分组：一组里第 1 稿、第 2 稿排在一起。
class _GroupsList extends StatelessWidget {
  const _GroupsList({required this.groups});

  final List<ProductionAttemptGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('逐题记录', style: Theme.of(context).textTheme.titleMedium),
            for (final g in groups) _GroupTile(group: g),
          ],
        ),
      ),
    );
  }
}

/// 一组题：标题 + 每稿一行。
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});

  final ProductionAttemptGroup group;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(group.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${group.records.length} 稿'),
      children: <Widget>[
        for (final rec in group.records)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 12),
            title: Text(writingRecordLabel(rec)),
            subtitle: Text(
              rec.feedback.max == 0
                  ? (rec.task is ProductionTask &&
                          (rec.task! as ProductionTask).skipped == true
                      ? '跳过（未提交）'
                      : '未批改')
                  : '${rec.feedback.total}/${rec.feedback.max}',
            ),
          ),
      ],
    );
  }
}
