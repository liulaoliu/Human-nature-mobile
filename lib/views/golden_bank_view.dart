import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/golden.dart';
import '../core/golden_bank.dart';
import '../viewmodels/golden_view_model.dart';

/// 金句本：全库金句，按文章摊平，可搜可筛，可导出 Markdown / Anki。
///
/// 数据每进一次页面现算（`loadBank`），不缓存：全库金句跟着「哪些文章
/// 做过金句课」变，缓存一份反而要处理失效。
class GoldenBankView extends StatefulWidget {
  const GoldenBankView({super.key});

  @override
  State<GoldenBankView> createState() => _GoldenBankViewState();
}

class _GoldenBankViewState extends State<GoldenBankView> {
  final TextEditingController _query = TextEditingController();
  GoldenBankStatus _status = GoldenBankStatus.all;
  GoldenBankKind _kind = GoldenBankKind.all;
  bool _loaded = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GoldenViewModel>();
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        vm.loadBank();
      });
    }
    final rows = filterGoldenBank(
      vm.bank,
      query: _query.text,
      status: _status,
      kind: _kind,
    );
    return Column(
      children: <Widget>[
        _FilterBar(
          query: _query,
          status: _status,
          kind: _kind,
          total: rows.length,
          onQuery: (String v) => setState(() => _query.text = v),
          onStatus: (GoldenBankStatus s) => setState(() => _status = s),
          onKind: (GoldenBankKind k) => setState(() => _kind = k),
        ),
        Expanded(
          child: rows.isEmpty
              ? _EmptyBank(hasAny: vm.bank.isNotEmpty)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: <Widget>[
                    for (final GoldenBankRow row in rows) ...<Widget>[
                      _BankTile(row: row),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// 搜索 + 状态 + 类型。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.status,
    required this.kind,
    required this.total,
    required this.onQuery,
    required this.onStatus,
    required this.onKind,
  });

  final TextEditingController query;
  final GoldenBankStatus status;
  final GoldenBankKind kind;
  final int total;
  final ValueChanged<String> onQuery;
  final ValueChanged<GoldenBankStatus> onStatus;
  final ValueChanged<GoldenBankKind> onKind;

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
          TextField(
            controller: query,
            onChanged: onQuery,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: '搜正文 / 译文 / 学习点',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final GoldenBankStatus s in GoldenBankStatus.values)
                ChoiceChip(
                  label: Text(goldenBankStatusLabel[s] ?? s.name),
                  selected: s == status,
                  onSelected: (_) => onStatus(s),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final GoldenBankKind k in GoldenBankKind.values)
                ChoiceChip(
                  label: Text(goldenBankKindLabel[k] ?? k.name),
                  selected: k == kind,
                  onSelected: (_) => onKind(k),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '筛出 $total 句',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条金句。
class _BankTile extends StatelessWidget {
  const _BankTile({required this.row});

  final GoldenBankRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  row.mastered
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: row.mastered
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.articleTitle.isEmpty ? '未命名' : row.articleTitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (row.due)
                  Text(
                    '待回顾',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(row.text, style: theme.textTheme.bodyMedium),
            if (row.zh != null && row.zh!.isNotEmpty)
              Text(
                row.zh!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (row.targets.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  for (final GoldenTarget t in row.targets)
                    Chip(
                      label: Text(
                        '${goldenTargetKindLabel[t.kind] ?? t.kind.name}：${t.en}',
                      ),
                      visualDensity: VisualDensity.compact,
                      labelStyle: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 空态：区分「全库没有」和「筛没了」。
class _EmptyBank extends StatelessWidget {
  const _EmptyBank({required this.hasAny});

  final bool hasAny;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          hasAny ? '这个筛选下没有句子。' : '还没有金句课。先去「挑句」给一篇文章做一课。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}
