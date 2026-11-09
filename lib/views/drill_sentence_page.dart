/// 小课堂 · 拷打造句：一轮背完 → 每个考到的词 / 词块各出一道造句题。
///
/// 上方「进度 + 题号」与下方「批改 / 重写」不跟着正文滚（吸顶 / 吸底）：
/// 题目、作答框、批改结果在中间滚动区里。这样长作答 + 长批改都不用滚回顶部换题，
/// 也不用滚到底才能点批改。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/drill_sentence.dart';
import '../core/drill_sentence_draft.dart';
import '../core/writing.dart';
import '../models/vocab.dart';
import '../viewmodels/drill_sentence_view_model.dart';
import 'ai_paste_sheet.dart';
import 'drill_sentence_feedback.dart';

/// 由背单词结算页推入；材料（本轮考到的词条）从结算页带过来。
class DrillSentencePage extends StatefulWidget {
  const DrillSentencePage({
    super.key,
    required this.items,
    required this.results,
    required this.kind,
    this.articleId,
    this.articleTitle = '',
  });

  /// 本轮考到的词条（用 `session.queue`）。
  final List<VocabItem> items;

  /// 一条判分结果 = 一个内容 = 一道题。
  final List<({String? id, String itemId})> results;

  /// 记忆拷打 / 词块拷打（由背词牌组决定）。
  final DrillSentenceKind kind;

  final String? articleId;
  final String articleTitle;

  @override
  State<DrillSentencePage> createState() => _DrillSentencePageState();
}

class _DrillSentencePageState extends State<DrillSentencePage> {
  late final TextEditingController _answer;

  @override
  void initState() {
    super.initState();
    _answer = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final vm = context.read<DrillSentenceViewModel>();
      await vm.bootstrap();
      if (!mounted) return;
      // 先读草稿、再认领本轮：草稿按 batchId 认领，不会串到别的批次。
      vm.startBatch(
        widget.items,
        widget.results,
        widget.kind,
        articleId: widget.articleId,
        articleTitle: widget.articleTitle,
      );
      _syncAnswer(vm);
    });
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _syncAnswer(DrillSentenceViewModel vm) {
    if (_answer.text == vm.answer) return;
    _answer.text = vm.answer;
    _answer.selection = TextSelection.fromPosition(
      TextPosition(offset: _answer.text.length),
    );
  }

  Future<void> _feedback(DrillSentenceViewModel vm) async {
    final prompt = vm.buildFeedbackPrompt();
    if (prompt == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiPasteSheet(
        title: '批改第 ${vm.round} 稿',
        prompt: prompt,
        hint: '粘回 AI 给的 v2 批改 JSON',
        onApply: vm.applyFeedback,
      ),
    );
  }

  Future<void> _clear(DrillSentenceViewModel vm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空这一轮造句草稿？'),
        content: const Text('各题的作答和批改都会清掉，已经记进历史的稿不会删。'),
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
    if (ok != true || !mounted) return;
    await vm.clearDraft();
    _syncAnswer(vm);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DrillSentenceViewModel>();
    _syncAnswer(vm);
    final task = vm.task;
    return Scaffold(
      appBar: AppBar(
        title: Text('${drillSentenceKindLabel(widget.kind)} · 造句'),
        actions: <Widget>[
          IconButton(
            onPressed: vm.hasTasks ? () => _clear(vm) : null,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空这一轮草稿',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (vm.error != null) _ErrorBar(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            if (vm.notice.isNotEmpty)
              _NoticeBar(message: vm.notice, onClose: vm.clearNotice),
            // 上方功能区：吸顶，不跟着正文滚。
            _TopBar(vm: vm),
            Expanded(
              child: task == null
                  ? const _EmptyBody()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      children: <Widget>[
                        _TaskCard(task: task),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _answer,
                          minLines: 6,
                          maxLines: 14,
                          decoration: const InputDecoration(
                            labelText: '你的句子',
                            hintText: '换主语或场景，别照抄例句',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          onChanged: vm.setAnswer,
                        ),
                        if (vm.feedback != null) ...<Widget>[
                          const SizedBox(height: 16),
                          DrillFeedbackCard(feedback: vm.feedback!),
                        ],
                      ],
                    ),
            ),
            // 下方功能区：吸底，长批改也不用滚回去点按钮。
            _BottomBar(
              vm: vm,
              onFeedback: () => _feedback(vm),
            ),
          ],
        ),
      ),
    );
  }
}

/// 上方吸顶：第几题 / 第几稿、题号切换、上一题 / 下一题。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.vm});

  final DrillSentenceViewModel vm;

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
                  vm.hasTasks
                      ? '第 ${vm.index + 1}/${vm.tasks.length} 题 · 第 ${vm.round} 稿'
                      : '这一轮没有题目',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                onPressed: vm.index <= 0 ? null : () => vm.openTask(vm.index - 1),
                icon: const Icon(Icons.chevron_left),
                tooltip: '上一题',
              ),
              IconButton(
                onPressed: vm.index + 1 >= vm.tasks.length
                    ? null
                    : () => vm.openTask(vm.index + 1),
                icon: const Icon(Icons.chevron_right),
                tooltip: '下一题',
              ),
            ],
          ),
          LinearProgressIndicator(
            value: vm.tasks.isEmpty ? 0 : (vm.index + 1) / vm.tasks.length,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (int i = 0; i < vm.tasks.length; i++)
                _TaskChip(vm: vm, index: i),
            ],
          ),
        ],
      ),
    );
  }
}

/// 题号：写过的题带一个小圆点（照 Web `DrillSentenceStage` 的口径）。
class _TaskChip extends StatelessWidget {
  const _TaskChip({required this.vm, required this.index});

  final DrillSentenceViewModel vm;
  final int index;

  @override
  Widget build(BuildContext context) {
    final task = vm.tasks[index];
    final label = task.mustUse.isEmpty ? '${index + 1}' : task.mustUse.first;
    final written = !vm.draft.answerOf(drillTaskIdOf(task)).isEmpty;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (written)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          Text(label, overflow: TextOverflow.ellipsis),
        ],
      ),
      selected: index == vm.index,
      onSelected: (_) => vm.openTask(index),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// 题干：只练这一个词 / 词块。
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
            SelectableText(task.task, style: theme.textTheme.titleMedium),
            if (task.mustUse.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('必须用上', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  for (final String w in task.mustUse)
                    Chip(label: Text(w), visualDensity: VisualDensity.compact),
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

/// 没题时的空态。
class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '这一轮没有可造句的词。\n先去背一轮，或者换个牌组试试。',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// 下方吸底：批改 / 重写。
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.vm, required this.onFeedback});

  final DrillSentenceViewModel vm;
  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              onPressed: vm.hasTasks ? onFeedback : null,
              icon: const Icon(Icons.spellcheck),
              label: Text(vm.feedback == null ? '批改这一稿' : '再批一次'),
            ),
          ),
          if (vm.canRewrite) ...<Widget>[
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: vm.rewrite,
                icon: const Icon(Icons.refresh),
                label: const Text('重写一稿'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
            tooltip: '知道了',
          ),
        ],
      ),
    );
  }
}
