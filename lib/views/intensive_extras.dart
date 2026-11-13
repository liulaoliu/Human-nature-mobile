/// 精读工作流页面的三块附属内容：产出看板 / 复述打卡 / 练习历史。
///
/// 为什么拆出来：`intensive_page.dart` 已经有七张阶段卡 + 头卡 + 下一步卡，
/// 再塞这三块会顶到 800 行门禁；而这三块彼此独立、只吃 ViewModel 的数据，
/// 拆出来正好一行 import 就能用。
///
/// 对应 Web 版 `IntensivePanel.tsx` 里的 `OutputBoard` / `iretell` / `WritingHistoryList`。
library;

import 'package:flutter/material.dart';

import '../core/output_board.dart';
import '../core/writing_record.dart' show WritingRecord, writingRecordLabel;
import '../viewmodels/intensive_view_model.dart';

/// 📊 产出看板：一行一个指标 + 色阶 + 一句下一步。
class IntensiveOutputCard extends StatelessWidget {
  const IntensiveOutputCard({super.key, required this.vm});

  final IntensiveViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final board = vm.outputBoard;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📊', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '产出看板',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${board.score} 分 · ${board.grade}',
                  key: const ValueKey('intensive-board-score'),
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final row in board.rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _BoardRow(row: row),
              ),
            const SizedBox(height: 2),
            Text(
              board.next,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.row});

  final OutputRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 达标绿、未达标灰：用 primary 而不是硬编码绿，深色/浅色两套主题都协调。
    final bar = row.good ? scheme.primary : scheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: row.good ? FontWeight.w600 : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              row.value,
              key: ValueKey('intensive-board-${row.key}'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: row.good ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: row.level / 100,
            minHeight: 3,
            color: bar,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// ✍️ 复述打卡：写一段、存一条、删一条。
class IntensiveRetellCard extends StatefulWidget {
  const IntensiveRetellCard({super.key, required this.vm});

  final IntensiveViewModel vm;

  @override
  State<IntensiveRetellCard> createState() => _IntensiveRetellCardState();
}

class _IntensiveRetellCardState extends State<IntensiveRetellCard> {
  final TextEditingController _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await widget.vm.saveRetell(_draft.text);
    if (!mounted) return;
    if (ok) {
      _draft.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已记录复述 ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = widget.vm.retells;
    final canSave = _draft.text.trim().isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('✍️', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '复述打卡',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '已记录 ${rows.length} 条',
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '用自己的话把这段讲一遍（不看原文也行）。复述是「能不能说出来」的唯一证据。',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('intensive-retell-input'),
              controller: _draft,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '用几句英文复述大意…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('intensive-retell-save'),
                onPressed: canSave ? _save : null,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('记下来'),
              ),
            ),
            if (rows.isNotEmpty) ...[
              const Divider(height: 20),
              for (final r in rows.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          r.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: ValueKey('intensive-retell-del-${r.at}'),
                        tooltip: '删除这条复述',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => widget.vm.deleteRetell(r.at),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 🕘 练习历史：本篇的仿写 / 产出记录（最近的几条）。
class IntensiveHistoryCard extends StatelessWidget {
  const IntensiveHistoryCard({super.key, required this.vm});

  final IntensiveViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = vm.writes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🕘', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '练习历史',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${rows.length} 条',
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (rows.isEmpty)
              Text(
                '这一篇还没有仿写记录。做到第 6 步「产出（仿写）」时，写完的每一稿都会落在这里。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.6,
                ),
              )
            else
              for (final rec in rows.take(5)) _HistoryRow(rec: rec),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.rec});

  final WritingRecord rec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final max = rec.feedback.max;
    final score = max > 0 ? '${rec.feedback.total}/$max' : '待批改';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  writingRecordLabel(rec),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  rec.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            score,
            style: theme.textTheme.labelSmall?.copyWith(
              color: max > 0 ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
