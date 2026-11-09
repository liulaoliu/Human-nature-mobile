import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/writing.dart';
import '../core/writing_history.dart';
import '../viewmodels/writing_view_model.dart';

/// 仿写历史：按来源 / 范围筛选，点开一条载入回看，可清空当前范围。
///
/// 全部从 [WritingViewModel.history] 现算（`writing_records` 是唯一事实来源）。
class WritingHistoryView extends StatelessWidget {
  const WritingHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WritingViewModel>();
    final rows = vm.filteredHistory;
    // 筛选器吸顶：记录一多（上限 5000 条）就得一边滚一边切来源/范围，
    // 筛选器跟着滚走等于每切一次都要滚回顶部。
    return Column(
      children: <Widget>[
        _FilterBar(
          source: vm.filter.source,
          counts: vm.historyCounts,
          scope: vm.filter.scope,
          onSource: (WritingHistorySource s) =>
              vm.setFilter(vm.filter.copyWith(source: s)),
          onScope: (WritingHistoryScope s) => vm.setFilter(
            vm.filter.copyWith(
              scope: s,
              articleId: s == WritingHistoryScope.article ? vm.articleId : '',
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    '这个范围内还没有记录。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else ...<Widget>[
                for (final WritingRecord rec in rows)
                  _RecordTile(
                    record: rec,
                    onOpen: () => vm.loadRecord(rec),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _confirmClear(context, vm),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清空当前范围'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    WritingViewModel vm,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空当前范围？'),
        content: Text(
          '将删掉「${writingHistorySourceLabel[vm.filter.source]} · '
          '${vm.filter.scope == WritingHistoryScope.article ? '本篇' : '全库'}」'
          '里的全部记录，删了不能恢复。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok ?? false) await vm.clearHistory();
  }
}

/// 吸顶筛选条：来源（带条数）+ 本篇 / 全库。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.source,
    required this.counts,
    required this.scope,
    required this.onSource,
    required this.onScope,
  });

  final WritingHistorySource source;
  final Map<WritingHistorySource, int> counts;
  final WritingHistoryScope scope;
  final ValueChanged<WritingHistorySource> onSource;
  final ValueChanged<WritingHistoryScope> onScope;

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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SourceFilter(value: source, counts: counts, onChanged: onSource),
          const SizedBox(height: 8),
          _ScopeFilter(value: scope, onChanged: onScope),
        ],
      ),
    );
  }
}

/// 来源筛选（带条数）。
class _SourceFilter extends StatelessWidget {
  const _SourceFilter({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  final WritingHistorySource value;
  final Map<WritingHistorySource, int> counts;
  final ValueChanged<WritingHistorySource> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: <Widget>[
        for (final WritingHistorySource s in WritingHistorySource.values)
          ChoiceChip(
            label: Text('${writingHistorySourceLabel[s] ?? s.name}'
                '（${counts[s] ?? 0}）'),
            selected: value == s,
            onSelected: (_) => onChanged(s),
          ),
      ],
    );
  }
}

/// 范围筛选：本篇 / 全库。
class _ScopeFilter extends StatelessWidget {
  const _ScopeFilter({required this.value, required this.onChanged});

  final WritingHistoryScope value;
  final ValueChanged<WritingHistoryScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<WritingHistoryScope>(
      segments: const <ButtonSegment<WritingHistoryScope>>[
        ButtonSegment<WritingHistoryScope>(
          value: WritingHistoryScope.article,
          label: Text('本篇'),
        ),
        ButtonSegment<WritingHistoryScope>(
          value: WritingHistoryScope.all,
          label: Text('全库'),
        ),
      ],
      selected: <WritingHistoryScope>{value},
      onSelectionChanged: (Set<WritingHistoryScope> s) => onChanged(s.first),
    );
  }
}

/// 一条历史：来源标签、时间、总分、点开回看。
class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.onOpen});

  final WritingRecord record;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fb = record.feedback;
    final score = fb.max <= 0 ? '' : ' · ${fb.total}/${fb.max}';
    final at = record.at.length >= 16
        ? record.at.substring(0, 16).replaceFirst('T', ' ')
        : record.at;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          writingRecordLabel(record),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$at$score · ${record.text.length} 字符',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}
