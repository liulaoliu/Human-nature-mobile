import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// 手动批改：不叫 AI，只把批改提示词复制到剪贴板，拿去任意 AI 里跑。
  ///
  /// 对齐 Web `ProductionRunView` 的 `manualGrade()`。跑完的结果仍从
  /// 「批改这一稿」的粘回面板进 `applyFeedback`，避免两份批改入口各写一套解析。
  Future<void> _copyPrompt(ProductionSession session) async {
    final prompt = session.buildFeedbackPrompt();
    if (prompt == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('批改提示词已复制，跑完把 v2 JSON 粘回「批改这一稿」'),
      ),
    );
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
    // 三段式：上方进度吸顶、下方操作吸底，中间只有题干 / 作答 / 批改跟正文滚。
    // 上帝类门禁按文件行数算，拆成两个私有 StatelessWidget 而不是塞回本类。
    return Column(
      children: <Widget>[
        _TopBar(session: session),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: <Widget>[
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
              if (session.feedback != null) ...<Widget>[
                const SizedBox(height: 16),
                _FeedbackCard(feedback: session.feedback!),
              ],
              if (session.previousFeedback != null) ...<Widget>[
                const SizedBox(height: 12),
                _PreviousCard(feedback: session.previousFeedback!),
              ],
            ],
          ),
        ),
        _BottomBar(
          session: session,
          onFeedback: () => _feedback(session),
          onCopyPrompt: () => _copyPrompt(session),
          onSkip: () => _skip(session),
          onRewrite: () => _rewrite(session),
        ),
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

/// 上方吸顶：第几题 / 第几稿、题号跳转、上一题 / 下一题。
///
/// 不透明底色 + 放在 `Column` 里（不在 ListView 内），正文长滚动时它不动。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.session});

  final ProductionSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '第 ${session.index + 1}/${session.prompts.length} 题 · 第 ${session.round} 稿',
                  style: theme.textTheme.titleSmall,
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
      ),
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

/// 下方吸底：批改 / 手动复制提示词 / 跳过 / 重写。
///
/// 放在 `Column` 的最后（不在 ListView 内），长批改也不用滚回去点按钮。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.session,
    required this.onFeedback,
    required this.onCopyPrompt,
    required this.onSkip,
    required this.onRewrite,
  });

  final ProductionSession session;
  final VoidCallback onFeedback;
  final VoidCallback onCopyPrompt;
  final VoidCallback onSkip;
  final VoidCallback onRewrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFeedback = session.feedback != null;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            onPressed: onFeedback,
            icon: const Icon(Icons.spellcheck),
            label: Text(hasFeedback ? '再批一次' : '批改这一稿'),
          ),
          const SizedBox(height: 8),
          // 窄屏时三个次要动作自动换行，不把「复制批改提示词」挤到看不见。
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              Tooltip(
                message: '不叫 AI：复制提示词拿去任意 AI 里跑，再粘回 v2 JSON',
                child: OutlinedButton.icon(
                  onPressed: onCopyPrompt,
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text('复制批改提示词'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onRewrite,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重写'),
              ),
              OutlinedButton.icon(
                onPressed: onSkip,
                icon: const Icon(Icons.skip_next, size: 18),
                label: const Text('跳过这题'),
              ),
            ],
          ),
        ],
      ),
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
