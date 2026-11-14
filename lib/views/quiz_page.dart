/// 整卷考试页：设置 → 作答 → 交卷报告。
///
/// 与「快速拷打」的区别：自选题型 / 范围 / 题量，交卷写一条 `practice_records`；
/// 文章卷不写 SRS / 错题本（判分口径在 `DrillPrep.record`）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/quiz.dart' show QuizKind, QuizQuestion, quizKindLabel;
import '../core/quiz_pool.dart'
    show
        QuizMode,
        QuizScope,
        quizLimitLabel,
        quizLimitOptions,
        quizModeLabel,
        quizScopeLabel;
import '../viewmodels/quiz_view_model.dart';
import '../widgets/status_bar.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<QuizViewModel>();
      if (!vm.busy) vm.bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QuizViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('考试')),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            Expanded(
              child: !vm.hasQueue
                  ? _SetupView(vm: vm)
                  : vm.finished
                      ? _ReportView(vm: vm)
                      : _RunView(vm: vm),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 设置

class _SetupView extends StatelessWidget {
  const _SetupView({required this.vm});

  final QuizViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('整卷考试', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '自选题型、范围和题量，一次性抽 N 题；交卷后看正确率、用时和错题。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _Label('考试模式'),
              const SizedBox(height: 6),
              SegmentedButton<QuizMode>(
                segments: [
                  for (final m in QuizMode.values)
                    ButtonSegment(value: m, label: Text(quizModeLabel[m]!)),
                ],
                selected: {vm.mode},
                onSelectionChanged: (s) => vm.setMode(s.first),
              ),
              const SizedBox(height: 16),
              if (vm.mode == QuizMode.vocab) ...[
                _Label('范围'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in QuizScope.values)
                      ChoiceChip(
                        key: ValueKey('quiz-scope-${s.name}'),
                        label: Text(quizScopeLabel[s]!),
                        selected: vm.scope == s,
                        onSelected: (_) => vm.setScope(s),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (vm.needsArticle)
                _ArticlePicker(vm: vm)
              else
                Text(
                  '按全库出题：不限定某一篇。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 16),
              _Label('题型（至少选一个）'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in vm.availableKinds)
                    FilterChip(
                      key: ValueKey('quiz-kind-${k.name}'),
                      label: Text(quizKindLabel[k] ?? k.name),
                      selected: vm.kinds.contains(k),
                      onSelected: (_) => vm.toggleKind(k),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _Label('题量'),
              const SizedBox(height: 6),
              DropdownButton<int>(
                key: const ValueKey('quiz-limit'),
                value: vm.limit,
                isExpanded: true,
                onChanged: (v) {
                  if (v != null) vm.setLimit(v);
                },
                items: [
                  for (final n in quizLimitOptions)
                    DropdownMenuItem(value: n, child: Text(quizLimitLabel(n))),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                vm.mode == QuizMode.article
                    ? '文章卷考理解与结构：需要这一篇有译文 / 语言点，数据不足时可能出不满。'
                    : '词级卷考词：拼写 / 例句 / 搭配等，词库缺释义或例句的卡出不了题。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('quiz-start'),
                onPressed: vm.busy || (vm.needsArticle && vm.articleId == null)
                    ? null
                    : () => vm.start(),
                child: const Text('开始考试'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArticlePicker extends StatelessWidget {
  const _ArticlePicker({required this.vm});

  final QuizViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (vm.articles.isEmpty) {
      return Text(
        '还没有文章：先去导入 / 精读一篇，文章卷才有题可出。',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label('文章'),
        const SizedBox(height: 6),
        DropdownButton<String>(
          key: const ValueKey('quiz-article'),
          value: vm.articleId,
          isExpanded: true,
          hint: const Text('选一篇'),
          onChanged: vm.setArticleId,
          items: [
            for (final a in vm.articles)
              DropdownMenuItem(
                value: a.id,
                child: Text(a.title, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ---------------------------------------------------------------- 作答

class _RunView extends StatelessWidget {
  const _RunView({required this.vm});

  final QuizViewModel vm;

  @override
  Widget build(BuildContext context) {
    final q = vm.question!;
    return Column(
      children: [
        _Progress(vm: vm),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _QuestionCard(vm: vm, q: q),
              const SizedBox(height: 12),
              if (q.options != null)
                _Options(vm: vm, q: q)
              else
                TextField(
                  key: ValueKey('quiz-input-${q.id}'),
                  enabled: vm.result == null,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '答案',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: vm.setInput,
                ),
              if (vm.result != null) ...[
                const SizedBox(height: 12),
                _Verdict(vm: vm),
              ],
            ],
          ),
        ),
        _RunBar(vm: vm),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.vm});

  final QuizViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '第 ${vm.index + 1}/${vm.total} 题 · 对 ${vm.correctCount}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                '${quizModeLabel[vm.mode]!} · ${vm.limit <= 0 ? '不限' : '${vm.limit} 题'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: vm.total == 0 ? 0 : vm.index / vm.total,
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.vm, required this.q});

  final QuizViewModel vm;
  final QuizQuestion q;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSpeak = q.kind == QuizKind.listen || q.kind == QuizKind.ear;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              quizKindLabel[q.kind] ?? q.kind.name,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            if (q.prompt.isNotEmpty)
              Text(q.prompt, style: theme.textTheme.titleLarge),
            if (q.prompt.isEmpty && (q.phonetic ?? '').isNotEmpty)
              Text(q.phonetic!, style: theme.textTheme.titleLarge),
            if (showSpeak && vm.speech != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.tonalIcon(
                  key: const ValueKey('quiz-speak'),
                  onPressed: vm.speakQuestion,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('播放'),
                ),
              ),
            if ((q.meaning ?? '').isNotEmpty && q.kind != QuizKind.choice)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '释义：${q.meaning}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if ((q.context ?? '').isNotEmpty &&
                (q.kind == QuizKind.mark || q.kind == QuizKind.prep))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  q.context!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({required this.vm, required this.q});

  final QuizViewModel vm;
  final QuizQuestion q;

  @override
  Widget build(BuildContext context) {
    final result = vm.result;
    return Column(
      children: [
        for (final opt in q.options!)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: ValueKey('quiz-option-$opt'),
                onPressed: result == null ? () => vm.submit(opt) : null,
                child: Text(opt, textAlign: TextAlign.left),
              ),
            ),
          ),
      ],
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.vm});

  final QuizViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = vm.result!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: r.correct
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.correct ? '对了' : '错了：${r.answer}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: r.correct
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onErrorContainer,
            ),
          ),
          if (!r.correct && r.input.isNotEmpty)
            Text(
              '你写的是「${r.input}」',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
        ],
      ),
    );
  }
}

class _RunBar extends StatelessWidget {
  const _RunBar({required this.vm});

  final QuizViewModel vm;

  @override
  Widget build(BuildContext context) {
    final hasResult = vm.result != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            TextButton(
              key: const ValueKey('quiz-quit'),
              onPressed: vm.reset,
              child: const Text('交卷/退出'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: ValueKey(hasResult ? 'quiz-next' : 'quiz-submit'),
                onPressed: hasResult
                    ? vm.next
                    : (vm.question?.options == null ? vm.submit : null),
                child: Text(
                  hasResult
                      ? (vm.index + 1 < vm.total ? '下一题' : '看结果')
                      : (vm.question?.options == null ? '交答案' : '选一个'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 报告

class _ReportView extends StatelessWidget {
  const _ReportView({required this.vm});

  final QuizViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = vm.results.length;
    final right = vm.correctCount;
    final wrong = vm.wrongQuestions.length;
    final tallies = _kindTallies(vm);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('考试完成', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('$total 题 · 对 $right · 错 $wrong',
            style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          '正确率 ${vm.results.isEmpty ? 0 : (vm.correctCount * 100 / vm.results.length).round()}% · 用时 ${vm.elapsedSeconds} 秒'
          '${vm.recorded ? ' · 成绩已记录' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (tallies.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Label('按题型'),
          const SizedBox(height: 6),
          for (final e in tallies.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${quizKindLabel[e.key] ?? e.key.name}：${e.value.correct}/${e.value.total}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
        if (vm.wrongQuestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Label('错题'),
          const SizedBox(height: 6),
          for (final q in vm.wrongQuestions)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                title: Text(
                  q.word.isNotEmpty ? q.word : (quizKindLabel[q.kind] ?? q.kind.name),
                ),
                subtitle: Text(
                  [
                    if (q.prompt.isNotEmpty) q.prompt,
                    '答案：${q.answer}',
                  ].join('\n'),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        if (wrong > 0)
          FilledButton.icon(
            key: const ValueKey('quiz-retry-wrong'),
            onPressed: () => vm.retryWrong(),
            icon: const Icon(Icons.replay),
            label: Text('错的 $wrong 题再练一遍'),
          ),
        if (wrong > 0) const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('quiz-again'),
          onPressed: () => vm.restart(),
          child: const Text('再考一轮'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('quiz-back-setup'),
          onPressed: vm.reset,
          child: const Text('改设置'),
        ),
      ],
    );
  }
}

/// 按题型汇总本轮对错（报告页用；不放进 ViewModel，省得它再多一个 getter）。
Map<QuizKind, ({int total, int correct})> _kindTallies(QuizViewModel vm) {
  final out = <QuizKind, ({int total, int correct})>{};
  for (final r in vm.results) {
    final cur = out[r.question.kind] ?? (total: 0, correct: 0);
    out[r.question.kind] =
        (total: cur.total + 1, correct: cur.correct + (r.correct ? 1 : 0));
  }
  return out;
}
