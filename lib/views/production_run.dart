import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/production_task.dart';
import '../core/writing.dart';
import '../viewmodels/production_session.dart';
import '../viewmodels/production_view_model.dart';
import 'ai_paste_sheet.dart';

/// 练习页：一题一屏 —— 题干、作答、批改、跳过 / 重写 / 换题。
///
/// 只读 [ProductionSession]（一道题的生命周期），不碰设置与落库。
class ProductionRunView extends StatefulWidget {
  const ProductionRunView({super.key, required this.onGoSetup});

  /// 没题时把用户送回出题页。
  final VoidCallback onGoSetup;

  @override
  State<ProductionRunView> createState() => _ProductionRunViewState();
}

class _ProductionRunViewState extends State<ProductionRunView> {
  late final TextEditingController _answer;

  @override
  void initState() {
    super.initState();
    _answer = TextEditingController(
      text: context.read<ProductionViewModel>().session.answer,
    );
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _feedback(ProductionSession session) async {
    final prompt = session.buildFeedbackPrompt();
    if (prompt == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiPasteSheet(
        title: '批改第 ${session.round} 稿',
        prompt: prompt,
        hint: '粘回 AI 给的 v2 批改 JSON',
        onApply: session.applyFeedback,
      ),
    );
  }

  Future<void> _skip(ProductionSession session) async {
    final ok = await session.skipCurrent();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '这题记为跳过' : '跳过没记上')),
    );
    if (ok) session.nextPrompt();
    _syncAnswer(session);
  }

  void _rewrite(ProductionSession session) {
    session.startRewrite();
    _syncAnswer(session);
  }

  void _syncAnswer(ProductionSession session) {
    if (_answer.text == session.answer) return;
    _answer.text = session.answer;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductionViewModel>();
    final session = vm.session;
    if (!session.hasPrompts) {
      return _EmptyRun(onGoSetup: widget.onGoSetup);
    }
    _syncAnswer(session);
    final task = session.task;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _ProgressBar(session: session),
        const SizedBox(height: 12),
        if (task != null) _TaskCard(task: task),
        const SizedBox(height: 12),
        TextField(
          controller: _answer,
          minLines: 6,
          maxLines: 14,
          decoration: const InputDecoration(
            labelText: '你的作答',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          onChanged: session.setAnswer,
        ),
        const SizedBox(height: 12),
        _ActionRow(
          session: session,
          onFeedback: () => _feedback(session),
          onSkip: () => _skip(session),
          onRewrite: () => _rewrite(session),
        ),
        if (session.feedback != null) ...<Widget>[
          const SizedBox(height: 16),
          _FeedbackCard(feedback: session.feedback!),
        ],
        if (session.previousFeedback != null) ...<Widget>[
          const SizedBox(height: 12),
          _PreviousCard(feedback: session.previousFeedback!),
        ],
      ],
    );
  }
}

/// 没题时的空态：回出题页。
class _EmptyRun extends StatelessWidget {
  const _EmptyRun({required this.onGoSetup});

  final VoidCallback onGoSetup;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('这一组还没出题。', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onGoSetup, child: const Text('去出题')),
          ],
        ),
      ),
    );
  }
}

/// 进度：第几题 / 第几稿，以及题号跳转。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.session});

  final ProductionSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '第 ${session.index + 1}/${session.prompts.length} 题 · 第 ${session.round} 稿',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              onPressed: session.index <= 0 ? null : session.prevPrompt,
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一题',
            ),
            IconButton(
              onPressed: session.index + 1 >= session.prompts.length
                  ? null
                  : session.nextPrompt,
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一题',
            ),
          ],
        ),
        LinearProgressIndicator(
          value: session.prompts.isEmpty
              ? 0
              : (session.index + 1) / session.prompts.length,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: <Widget>[
            for (int i = 0; i < session.prompts.length; i++)
              ChoiceChip(
                label: Text('${i + 1}'),
                selected: i == session.index,
                onSelected: (_) => session.openPrompt(i),
              ),
          ],
        ),
      ],
    );
  }
}

/// 题干：中文提示 + 目标 + 参考句（风味酸奶才有）。
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final ProductionTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SelectableText(
              task.task,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (task.goal.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(task.goal, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (task.mustUse.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('必须用上', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  for (final t in task.targets)
                    Tooltip(
                      message: t.meaning,
                      child: Chip(
                        label: Text(t.text),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ],
            if (task.reference != null && task.reference!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('参考句', style: Theme.of(context).textTheme.labelLarge),
              SelectableText(
                task.reference!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 主操作：批改 / 跳过 / 重写。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.session,
    required this.onFeedback,
    required this.onSkip,
    required this.onRewrite,
  });

  final ProductionSession session;
  final VoidCallback onFeedback;
  final VoidCallback onSkip;
  final VoidCallback onRewrite;

  @override
  Widget build(BuildContext context) {
    final hasFeedback = session.feedback != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: onFeedback,
          icon: const Icon(Icons.spellcheck),
          label: Text(hasFeedback ? '再批一次' : '批改这一稿'),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRewrite,
                icon: const Icon(Icons.refresh),
                label: const Text('重写'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onSkip,
                icon: const Icon(Icons.skip_next),
                label: const Text('跳过这题'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 批改结果：分数、错因、润色稿、小结。
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback});

  final WritingFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '批改：${feedback.total}/${feedback.max}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (feedback.scores.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final s in feedback.scores)
                    Chip(
                      label: Text('${s.dimension} ${s.score}/${s.max}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (feedback.issues.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text('要改的地方', style: Theme.of(context).textTheme.labelLarge),
              for (final issue in feedback.issues) _IssueTile(issue: issue),
            ],
            if (feedback.recommendations.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text('可以收进本课', style: Theme.of(context).textTheme.labelLarge),
              for (final rec in feedback.recommendations)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${rec.kindLabel} · ${rec.point}'),
                  subtitle: Text(rec.zh ?? ''),
                ),
            ],
            if (feedback.polished != null && feedback.polished!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('润色稿', style: Theme.of(context).textTheme.labelLarge),
              SelectableText(feedback.polished!),
            ],
            if (feedback.summary != null && feedback.summary!.isNotEmpty) ...[
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

/// 一条错因。
class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue});

  final WritingIssue issue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${writingTypeLabel(issue.type)} · ${issue.rule.label}',
            style: TextStyle(
              color: scheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text('原句：${issue.original}'),
          Text('改成：${issue.suggestion}'),
          if (issue.reason != null && issue.reason!.isNotEmpty)
            Text(
              issue.reason!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

/// 上一稿的批改（重写时对照）。
class _PreviousCard extends StatelessWidget {
  const _PreviousCard({required this.feedback});

  final WritingFeedback feedback;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('上一稿：${feedback.total}/${feedback.max}'),
      children: <Widget>[
        for (final issue in feedback.issues)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(issue.original),
            subtitle: Text('→ ${issue.suggestion}'),
          ),
      ],
    );
  }
}
