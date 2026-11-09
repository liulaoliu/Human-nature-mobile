import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/golden.dart';
import '../core/golden_bank.dart';
import '../core/golden_markdown.dart';
import '../core/golden_progress.dart';
import '../models/document.dart';
import '../viewmodels/golden_view_model.dart';

/// 历史：这一篇的练习记录、掌握情况，以及把整课导出成 Markdown。
///
/// 为什么按「文章」而不是按时间轴：金句课的掌握是**跟文章绑的**
/// （同一句换个学习点就是另一条记录），时间轴反而看不出「哪篇练到哪了」。
class GoldenHistoryView extends StatelessWidget {
  const GoldenHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GoldenViewModel>();
    final summary = vm.summary;
    final records = vm.records;
    final theme = Theme.of(context);
    if (vm.article == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '先挑一篇文章，才看得到它的练习记录。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        if (summary != null) ...<Widget>[
          _SummaryCard(summary: summary),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () => _copyMarkdown(context, vm),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('复制本课 Markdown'),
            ),
            OutlinedButton.icon(
              onPressed: () => _copyBankMarkdown(context, vm),
              icon: const Icon(Icons.library_books_outlined, size: 18),
              label: const Text('复制全库金句本'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('练习记录', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '「首次」只记第一次答对：之后重练不再刷首答，掌握状态也不会掉回去。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '还没有练习记录。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          for (final GoldenDrillRecord r in records.reversed)
            _RecordTile(record: r, text: vm.textOf(r.sentenceId)),
      ],
    );
  }
}

/// 掌握情况卡。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final GoldenMasterySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('这一课的掌握', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: <Widget>[
                _Metric(
                  label: '句子',
                  value:
                      '${summary.masteredSentences}/${summary.selectedSentences}',
                ),
                _Metric(
                  label: '学习点',
                  value:
                      '${summary.masteredTargets}/${summary.totalTargets}',
                ),
              ],
            ),
            if (summary.byKind.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  for (final GoldenKindCount k in summary.byKind)
                    Chip(
                      label: Text(
                        '${goldenTargetKindLabel[k.kind] ?? k.kind.name} '
                        '${k.mastered}/${k.total}',
                      ),
                      visualDensity: VisualDensity.compact,
                      labelStyle: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ],
            if (summary.bySection.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                summary.bySection
                    .map((GoldenSectionCount s) =>
                        '${goldenSectionLabel(s.role)} ${s.mastered}/${s.total}')
                    .join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 段落角色标签（导出的 Markdown 用的是同一套口径）。
String goldenSectionLabel(GoldenSectionRole role) => switch (role) {
      GoldenSectionRole.intro => '开头段',
      GoldenSectionRole.body => '主体段',
      GoldenSectionRole.conclusion => '结尾段',
    };

/// 一个数字指标。
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(value, style: theme.textTheme.titleLarge),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 一条练习记录。
class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.text});

  final GoldenDrillRecord record;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = <String>[
      if (record.fillTries > 0) '填空 ${record.fillTries} 次${_mark(record.fillFirst)}',
      if (record.assembleTries > 0)
        '拼句 ${record.assembleTries} 次${_mark(record.assembleFirst)}',
      if (record.recallTries > 0)
        '默写 ${record.recallTries} 次${_mark(record.recallFirst)}',
      if (record.summarySeen == true) '看过小结',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  record.mastered ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: record.mastered
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    text.isEmpty ? record.sentenceId : text,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              steps.isEmpty ? '还没练' : steps.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 首次答对打勾，否则留空。
  static String _mark(bool? first) => first == true ? ' ✓' : '';
}

/// 复制本课 Markdown（带掌握勾）。
Future<void> _copyMarkdown(BuildContext context, GoldenViewModel vm) async {
  final lesson = vm.lesson;
  if (lesson == null) return;
  final markdown = goldenToMarkdown(
    lesson,
    title: vm.articleTitle,
    sentences: <GoldenTextMeta>[
      for (final Sentence s in vm.sentences)
        GoldenTextMeta(id: s.id, text: s.text, translation: s.translation),
    ],
    records: vm.records,
    articleId: vm.articleId,
    includeProgress: true,
  );
  await Clipboard.setData(ClipboardData(text: markdown));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('本课 Markdown 已复制')),
  );
}

/// 复制全库金句本 Markdown（先确保金句本已加载）。
Future<void> _copyBankMarkdown(
  BuildContext context,
  GoldenViewModel vm,
) async {
  await vm.loadBank();
  if (!context.mounted) return;
  final markdown = goldenBankToMarkdown(vm.bank);
  await Clipboard.setData(ClipboardData(text: markdown));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('全库金句本已复制')),
  );
}
