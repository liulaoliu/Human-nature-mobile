import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/writing.dart';
import '../viewmodels/writing_view_model.dart';
import 'ai_paste_sheet.dart';

/// 仿写训练：范句 → ① 生成任务 → 我写 → ② 批改 → 结果。
///
/// 只读 [WritingViewModel] 的草稿那一半；历史在另一页。
class WritingPanel extends StatefulWidget {
  const WritingPanel({super.key});

  @override
  State<WritingPanel> createState() => _WritingPanelState();
}

class _WritingPanelState extends State<WritingPanel> {
  late final TextEditingController _model;
  late final TextEditingController _text;
  late final TextEditingController _mustUse;

  @override
  void initState() {
    super.initState();
    final vm = context.read<WritingViewModel>();
    _model = TextEditingController(text: vm.model);
    _text = TextEditingController(text: vm.text);
    _mustUse = TextEditingController(text: vm.mustUse.join('、'));
  }

  @override
  void dispose() {
    _model.dispose();
    _text.dispose();
    _mustUse.dispose();
    super.dispose();
  }

  /// 把界面上的三个框同步回 ViewModel（粘回结果后 ViewModel 会改草稿）。
  ///
  /// 词块框**不能按 `join('、')` 比**：用户刚敲下的分隔符会被 [_parseMustUse]
  /// 切掉（`'run、'` → `['run']`），拿 join 拼回去就是把顿号吞掉、光标顶到末尾，
  /// 实际效果是「打不出第二个词块，只能用粘贴」。所以这里只比**语义**
  /// （切出来的词表是否一致），一致就一个字都不动。
  void _sync(WritingViewModel vm) {
    if (_model.text != vm.model) _model.text = vm.model;
    if (_text.text != vm.text) _text.text = vm.text;
    if (!_sameWords(_parseMustUse(_mustUse.text), vm.mustUse)) {
      _mustUse.text = vm.mustUse.join('、');
    }
  }

  static bool _sameWords(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<String> _parseMustUse(String raw) => raw
      .split(RegExp(r'[、,，;；\n]'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  Future<void> _makeTask(WritingViewModel vm) async {
    final prompt = vm.buildTaskPrompt();
    if (prompt == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiPasteSheet(
        title: '生成仿写任务',
        prompt: prompt,
        hint: '粘回 AI 给的 {"task":...} 那个 JSON 对象',
        onApply: (String raw) async => vm.applyTask(raw),
      ),
    );
  }

  Future<void> _makeFeedback(WritingViewModel vm) async {
    final prompt = vm.buildFeedbackPrompt();
    if (prompt == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiPasteSheet(
        title: '批改这一稿',
        prompt: prompt,
        hint: '粘回 AI 给的 v2 批改 JSON',
        onApply: vm.applyFeedback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WritingViewModel>();
    _sync(vm);
    final task = vm.task;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          controller: _model,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: '范句',
            hintText: '从文章里挑一句想模仿的英文',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          onChanged: vm.setModel,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mustUse,
          decoration: const InputDecoration(
            labelText: '必须用上的词块',
            hintText: '用「、」或逗号隔开，可以留空',
            border: OutlineInputBorder(),
          ),
          onChanged: (String raw) => vm.setMustUse(_parseMustUse(raw)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _makeTask(vm),
          icon: const Icon(Icons.auto_awesome),
          label: Text(task == null ? '① 生成任务' : '① 重新生成任务'),
        ),
        if (task != null) ...<Widget>[
          const SizedBox(height: 16),
          _TaskCard(task: task),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '我的仿写',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            onChanged: vm.setText,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _makeFeedback(vm),
            icon: const Icon(Icons.spellcheck),
            label: Text(vm.feedback == null ? '② 批改' : '② 再批一次'),
          ),
        ],
        if (vm.feedback != null) ...<Widget>[
          const SizedBox(height: 16),
          _FeedbackCard(feedback: vm.feedback!),
        ],
      ],
    );
  }
}

/// 任务卡：题干、结构、必须用上的词、评分维度。
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final ImitationTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('任务', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(task.task, style: theme.textTheme.titleMedium),
            if (task.model.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('范句', style: theme.textTheme.labelLarge),
              SelectableText(task.model, style: theme.textTheme.bodyMedium),
            ],
            if (task.structure != null && task.structure!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('结构', style: theme.textTheme.labelLarge),
              Text(task.structure!, style: theme.textTheme.bodyMedium),
            ],
            if (task.mustUse.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('必须用上', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  for (final String word in task.mustUse)
                    Chip(
                      label: Text(word),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (task.rubric.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('评分维度', style: theme.textTheme.labelLarge),
              for (final RubricItem r in task.rubric)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '· ${r.dimension}（${r.weight} 分）'
                    '${r.description == null ? '' : '：${r.description}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 批改结果：总分、各维度、错因、润色稿、小结。
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback});

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
            const SizedBox(height: 8),
            for (final WritingScore s in feedback.scores)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '· ${s.dimension}：${s.score}/${s.max}'
                  '${s.comment == null ? '' : ' — ${s.comment}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (feedback.issues.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('要改的地方', style: theme.textTheme.labelLarge),
              for (final WritingIssue issue in feedback.issues)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _IssueTile(issue: issue),
                ),
            ],
            if (feedback.polished != null && feedback.polished!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('润色稿', style: theme.textTheme.labelLarge),
              SelectableText(
                feedback.polished!,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (feedback.summary != null && feedback.summary!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                feedback.summary!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一条错因：错的地方 → 应该怎么写 + 为什么 + 大类。
class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue});

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
            '${issue.reason == null ? '' : '：${issue.reason}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
