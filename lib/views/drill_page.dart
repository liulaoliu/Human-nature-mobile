/// 快速拷打页：选一档 → 出卷 → 一题一题判 → 结算。
///
/// 和「背单词」的区别：那边是 SRS 卡片（记得/模糊/忘了），这边是**题**
/// —— 拼写、选义、搭配填空，答完立刻判对错。题库与判分规则在
/// `core/quiz.dart`（早就有、有测试，以前没人用它出卷）。
///
/// 「本篇」跟着全局当前文章走（`CurrentArticleViewModel`），页内不换文章：
/// 想换去精读页挑，这是 `docs/TODO.md` 第十一件定下的口径。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/quiz.dart';
import '../core/quiz_drill.dart';
import '../viewmodels/current_article_view_model.dart';
import '../viewmodels/drill_view_model.dart';
import '../widgets/status_bar.dart';
import 'drill_warmup_view.dart';

class DrillPage extends StatefulWidget {
  const DrillPage({super.key, this.initialKind});

  /// 进来就选好这一档（比如精读工作流的「语法专项」直接进 grammar）。
  ///
  /// 不传就沿用 ViewModel 里上次选的档；传了且和当前不一致时，会先把上一轮
  /// 清掉再选 —— 否则从别的页跳进来会打断一半的题，落在错的档上。
  final QuizDrillKind? initialKind;

  @override
  State<DrillPage> createState() => _DrillPageState();
}

class _DrillPageState extends State<DrillPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<DrillViewModel>();
      final want = widget.initialKind;
      if (want != null && (vm.kind != want || vm.hasQueue)) {
        vm.reset();
        vm.setKind(want);
      }
      if (!vm.busy) vm.bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DrillViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('拷打')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            Expanded(
              child: vm.warmup
                  ? DrillWarmupView(vm: vm)
                  : !vm.hasQueue
                      ? _SetupView(vm: vm)
                      : vm.finished
                          ? _DoneView(vm: vm)
                          : _RunView(vm: vm),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选档（上面滚动）+ 题量 / 开始（下面吸底）。
class _SetupView extends StatelessWidget {
  const _SetupView({required this.vm});

  final DrillViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = context.watch<CurrentArticleViewModel?>();
    final article = current?.articleId == null ? null : current?.article;
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('拷打哪一批？', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                article == null
                    ? '还没在精读页选文章，先按全库考；选一篇之后就只考那一篇的词。'
                    : '按「${article.title}」这一篇的词考。要换一篇，去精读页挑。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final kind in QuizDrillKind.values) ...<Widget>[
                _KindTile(
                  kind: kind,
                  selected: vm.kind == kind,
                  ready: quizDrillImplemented(kind),
                  onTap: () => vm.setKind(kind),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              Text(
                '答对按「认识」记进复习排期，答错按「忘记」记一次 lapse，同时进错题本；'
                '「错题包围战」就是拿错题本里的词再打一遍。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _SetupBar(vm: vm),
      ],
    );
  }
}

/// 底部功能区吸底：这一轮多少题 + 题数选项 + 开始。
///
/// 不透明底 + 上边框，选档列表滚动时它不动（用户 m32285）。
class _SetupBar extends StatelessWidget {
  const _SetupBar({required this.vm});

  final DrillViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('这一轮多少题', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final n in drillLimitOptions)
                    ChoiceChip(
                      key: ValueKey<String>('drill-limit-$n'),
                      label: Text('$n'),
                      selected: vm.limit == n,
                      onSelected: (_) => vm.setLimit(n),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey<String>('drill-start'),
                onPressed: () async {
                  final n = await vm.launch();
                  if (n == 0) return;
                },
                icon: const Icon(Icons.play_arrow),
                label: Text('开始（${quizDrillLabel[vm.kind] ?? ''}）'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一档的入口（没做的档位也显示，标「待开」）。
class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.kind,
    required this.selected,
    required this.ready,
    required this.onTap,
  });

  final QuizDrillKind kind;
  final bool selected;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: selected ? scheme.secondaryContainer : null,
      child: ListTile(
        key: ValueKey<String>('drill-kind-${kind.name}'),
        enabled: ready,
        selected: selected,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 20,
          color: ready ? scheme.primary : scheme.outline,
        ),
        title: Text(quizDrillLabel[kind] ?? kind.name),
        subtitle: Text(quizDrillHint[kind] ?? ''),
        trailing: ready ? null : const Text('待开'),
        onTap: ready ? onTap : null,
      ),
    );
  }
}

/// 一题一屏。
///
/// 填空题自动聚焦答案框：开始拷打 / 换到下一题后，光标直接落在输入框里，
/// 不用用户先点一下（用户 m32314）。判分后输入框禁用、焦点自然释放；
/// 用「题号 / 题目 id」作 token，避免同一题重复 requestFocus。
class _RunView extends StatefulWidget {
  const _RunView({required this.vm});

  final DrillViewModel vm;

  @override
  State<_RunView> createState() => _RunViewState();
}

class _RunViewState extends State<_RunView> {
  final FocusNode _answerFocus = FocusNode();
  String? _focusedToken;

  @override
  void dispose() {
    _answerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final q = vm.question;
    if (q == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    // 只有「还没判分的填空题」才抢焦点：选项题靠点按钮，判分后输入框禁用。
    final wantsFocus = q.options == null && vm.result == null;
    final token = '${vm.index}/${q.id}';
    if (wantsFocus) {
      if (_focusedToken != token) {
        _focusedToken = token;
        // 必须在 build 之后：这一帧里 TextField 才刚把 focusNode 挂进树。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _answerFocus.requestFocus();
        });
      }
    } else {
      _focusedToken = null;
    }

    return Column(
      children: <Widget>[
        // 进度条吸顶：不透明底 + 下边框，题目区滚动时它不动。
        Container(
          width: double.infinity,
          color: theme.colorScheme.surface,
          child: Column(
            children: <Widget>[
              _ProgressBar(vm: vm),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _QuestionCard(
                question: q,
                onSpeak: vm.speech != null && (q.audioText ?? '').isNotEmpty
                    ? () {
                        vm.speakQuestion();
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              if (q.options == null)
                TextField(
                  key: const ValueKey<String>('drill-input'),
                  focusNode: _answerFocus,
                  enabled: vm.result == null,
                  onChanged: vm.setInput,
                  decoration: const InputDecoration(
                    labelText: '答案',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => vm.submit(v),
                )
              else
                _OptionList(vm: vm),
              if (vm.result != null) ...<Widget>[
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

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.vm});

  final DrillViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = vm.results.length;
    final total = vm.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '第 ${vm.index + 1}/$total 题 · 对了 $done 中的 ${vm.correctCount}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                '${quizDrillLabel[vm.kind] ?? ''} · $total 题',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: total == 0 ? 0 : vm.index / total,
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, this.onSpeak});

  final QuizQuestion question;

  /// 听音填空：题干是空的，只给一个播放按钮（没注入朗读器时为 null）。
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = question;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              quizKindLabel[q.kind] ?? q.kind.name,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            if (q.prompt.isNotEmpty)
              Text(q.prompt, style: theme.textTheme.titleLarge),
            // 听力 / 听音拼词：题干是空的，只给音标提示。
            if (q.prompt.isEmpty && (q.phonetic ?? '').isNotEmpty)
              Text(q.phonetic!, style: theme.textTheme.titleLarge),
            if (onSpeak != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.tonalIcon(
                  key: const ValueKey<String>('drill-speak'),
                  onPressed: onSpeak,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('播放句子'),
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
          ],
        ),
      ),
    );
  }
}

/// 选项题：四个按钮，点了就是交卷。
class _OptionList extends StatelessWidget {
  const _OptionList({required this.vm});

  final DrillViewModel vm;

  @override
  Widget build(BuildContext context) {
    final q = vm.question!;
    final result = vm.result;
    return Column(
      children: <Widget>[
        for (final opt in q.options!) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: ValueKey<String>('drill-option-$opt'),
                onPressed: result == null ? () => vm.submit(opt) : null,
                child: Text(opt, textAlign: TextAlign.left),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.vm});

  final DrillViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = vm.result!;
    final ok = r.correct;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            ok ? '对了' : '错了：${r.answer}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: ok
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onErrorContainer,
            ),
          ),
          if (!ok && r.input.isNotEmpty)
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

/// 底栏：下一题 / 收工（吸底）。
class _RunBar extends StatelessWidget {
  const _RunBar({required this.vm});

  final DrillViewModel vm;

  @override
  Widget build(BuildContext context) {
    final hasResult = vm.result != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: <Widget>[
            TextButton(
              onPressed: vm.reset,
              child: const Text('收工'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const ValueKey<String>('drill-next'),
                onPressed: hasResult ? vm.next : vm.submit,
                child: Text(
                  hasResult
                      ? (vm.hasNext ? '下一题' : '看结果')
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

/// 结算。
class _DoneView extends StatelessWidget {
  const _DoneView({required this.vm});

  final DrillViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = vm.results.length;
    final right = vm.correctCount;
    final wrong = vm.wrongQuestions.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('这一轮做完了', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '$total 题，对 $right，错 $wrong。',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        if (wrong > 0)
          FilledButton.icon(
            key: const ValueKey<String>('drill-retry-wrong'),
            onPressed: () => vm.retryWrong(),
            icon: const Icon(Icons.replay),
            label: Text('错的 $wrong 题再来一遍'),
          ),
        if (wrong > 0) const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey<String>('drill-again'),
          onPressed: () async {
            vm.reset();
            await vm.launch();
          },
          child: const Text('再打一轮'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey<String>('drill-back-setup'),
          onPressed: vm.reset,
          child: const Text('换一档'),
        ),
      ],
    );
  }
}
