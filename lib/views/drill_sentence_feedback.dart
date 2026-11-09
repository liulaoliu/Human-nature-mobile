/// 拷打造句的批改结果卡（公开组件，单独成文件给造句页复用）。
///
/// 与 `writing_panel.dart` 的 `_FeedbackCard` 口径一致：分数 → 各维度 → 错因 →
/// 可收进本课的语言点 → 润色稿 → 小结。分成独立文件是因为私有类跨文件用不了，
/// 而 `tool/check_god_class.dart` 又不允许把这一坨塞回页面壳里。
library;

import 'package:flutter/material.dart';

import '../core/writing.dart';

/// 一份 v2 批改结果。
class DrillFeedbackCard extends StatelessWidget {
  const DrillFeedbackCard({super.key, required this.feedback});

  final WritingFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '批改：${feedback.total}/${feedback.max}',
              style: theme.textTheme.titleMedium,
            ),
            if (feedback.scores.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final WritingScore s in feedback.scores)
                    Chip(
                      label: Text('${s.dimension} ${s.score}/${s.max}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (feedback.issues.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text('要改的地方', style: theme.textTheme.labelLarge),
              for (final WritingIssue issue in feedback.issues)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: DrillIssueTile(issue: issue),
                ),
            ],
            if (feedback.recommendations.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text('可以收进本课', style: theme.textTheme.labelLarge),
              for (final rec in feedback.recommendations)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${rec.kindLabel} · ${rec.point}'),
                  subtitle: Text(rec.zh ?? ''),
                ),
            ],
            if (feedback.polished != null &&
                feedback.polished!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text('润色稿', style: theme.textTheme.labelLarge),
              SelectableText(
                feedback.polished!,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (feedback.summary != null &&
                feedback.summary!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: scheme.secondaryContainer,
                child: Text(
                  feedback.summary!,
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一条错因：原句 → 改成 + 大类 / 规则 / 原因。
class DrillIssueTile extends StatelessWidget {
  const DrillIssueTile({super.key, required this.issue});

  final WritingIssue issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final improvement = issue.isImprovement;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: improvement
            ? scheme.secondaryContainer
            : scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: <Widget>[
              Text(
                issue.original.isEmpty ? '（缺词）' : issue.original,
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const Icon(Icons.arrow_forward, size: 14),
              Text(issue.suggestion, style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${writingTypeLabel(issue.type)} · ${issue.rule.label}'
            '${issue.reason == null || issue.reason!.isEmpty ? '' : '：${issue.reason}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
