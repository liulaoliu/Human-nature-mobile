import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/golden.dart';
import '../core/golden_drill.dart';
import '../viewmodels/golden_drill_session.dart';
import '../viewmodels/golden_view_model.dart';

/// 练习页：一句一句地练 —— 填空（多轮）→ 拼句 → 小结。
///
/// 三段式（上吸顶 / 中间滚 / 下吸底）是刻意的：填空轮次多，
/// 每次交卷都要点底部按钮，按钮跟着滚走等于每轮多滚一趟。
///
/// 输入框由本组件持有（不是 session）：输入框文本属于界面，
/// 判分后的「保留原作答」和「换轮要清空」都在这里处理。
class GoldenDrillView extends StatefulWidget {
  const GoldenDrillView({super.key, required this.onGoPlan});

  /// 回挑句页（换一句 / 改设置）。
  final VoidCallback onGoPlan;

  @override
  State<GoldenDrillView> createState() => _GoldenDrillViewState();
}

class _GoldenDrillViewState extends State<GoldenDrillView> {
  List<TextEditingController> _controllers = <TextEditingController>[];
  String _roundKey = '';

  /// 第一个空的光标：一轮开始时自动聚焦，省得用户先点一下输入框。
  final FocusNode _firstBlankFocus = FocusNode();

  @override
  void dispose() {
    _disposeControllers();
    _firstBlankFocus.dispose();
    super.dispose();
  }

  void _disposeControllers() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    _controllers = <TextEditingController>[];
  }

  /// 换句 / 换轮 / 空位数变了才重建输入框。
  void _syncControllers(GoldenDrillSession session) {
    final cloze = session.round;
    final count = cloze?.blanks.length ?? 0;
    final key = '${session.sentenceId}|${session.roundIndex}|$count|'
        '${session.roundScored}';
    if (key == _roundKey) return;
    _roundKey = key;
    // 判分之后不重建：让用户看着自己填的答案对照正确答案。
    if (session.roundScored && _controllers.length == count) return;
    _disposeControllers();
    _controllers = <TextEditingController>[
      for (var i = 0; i < count; i++) TextEditingController(),
    ];
    // 新一轮的输入框刚建出来，等这一帧画完再要焦点 —— 在 build 里直接
    // `requestFocus()` 会撞「build 期间改状态」。
    if (count > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_controllers.isEmpty) return;
        _firstBlankFocus.requestFocus();
      });
    }
  }

  void _submitFill(GoldenDrillSession session) {
    session.submitFill(<String>[
      for (final TextEditingController c in _controllers) c.text,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GoldenViewModel>();
    final session = vm.drill;
    if (session.sentenceId.isEmpty) {
      return _EmptyDrill(onGoPlan: widget.onGoPlan);
    }
    _syncControllers(session);
    return Column(
      children: <Widget>[
        _TopBar(vm: vm, session: session),
        Expanded(
          child: switch (session.phase) {
            GoldenDrillPhase.fill => _FillBody(
                session: session,
                controllers: _controllers,
                firstBlankFocus: _firstBlankFocus,
              ),
            GoldenDrillPhase.assemble => _AssembleBody(session: session),
            GoldenDrillPhase.summary => _SummaryBody(vm: vm, session: session),
          },
        ),
        _BottomBar(
          vm: vm,
          session: session,
          onGoPlan: widget.onGoPlan,
          onSubmitFill: () => _submitFill(session),
        ),
      ],
    );
  }
}

/// 还没挑句子。
class _EmptyDrill extends StatelessWidget {
  const _EmptyDrill({required this.onGoPlan});

  final VoidCallback onGoPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('还没开始练。', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '先去挑句页选一句，再回来练。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onGoPlan,
              icon: const Icon(Icons.list_alt),
              label: const Text('去挑句'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 吸顶：这一句 + 到哪一步了。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.vm, required this.session});

  final GoldenViewModel vm;
  final GoldenDrillSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = vm.ordered.length;
    final at = vm.ordered.indexWhere((GoldenSentence c) => c.id == session.sentenceId);
    final progress = switch (session.phase) {
      GoldenDrillPhase.fill => session.roundCount == 0
          ? '填空'
          : '填空 ${session.roundIndex + 1}/${session.roundCount}',
      GoldenDrillPhase.assemble => '拼句',
      GoldenDrillPhase.summary => '小结',
    };
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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  total == 0
                      ? progress
                      : '第 ${at < 0 ? 1 : at + 1}/$total 句 · $progress',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (session.targets.isNotEmpty)
                Text(
                  '${session.targets.length} 个学习点',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(session.text, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 填空正文。
class _FillBody extends StatelessWidget {
  const _FillBody({
    required this.session,
    required this.controllers,
    this.firstBlankFocus,
  });

  final GoldenDrillSession session;
  final List<TextEditingController> controllers;

  /// 第一个空拿这个焦点，进页面就能直接打字。
  final FocusNode? firstBlankFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloze = session.round;
    if (cloze == null) {
      return Center(
        child: Text('这一句没有可以挖空的学习点。', style: theme.textTheme.bodyMedium),
      );
    }
    var blankIndex = 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text(
          '按顺序把空填上（这一轮有 ${cloze.blanks.length} 个空）。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final GoldenClozePart part in cloze.parts)
              if (!part.blank)
                Text(part.text, style: theme.textTheme.bodyLarge)
              else ...<Widget>[
                _BlankField(
                  controller: blankIndex < controllers.length
                      ? controllers[blankIndex]
                      : TextEditingController(),
                  answer: cloze.blanks[blankIndex].answer,
                  hint: cloze.blanks[blankIndex].hint,
                  scored: session.roundScored,
                  ok: blankIndex < session.roundResults.length
                      ? session.roundResults[blankIndex]
                      : null,
                  focusNode: blankIndex == 0 ? firstBlankFocus : null,
                ),
                if (++blankIndex >= controllers.length) const SizedBox(),
              ],
          ],
        ),
        if (session.roundScored) ...<Widget>[
          const SizedBox(height: 16),
          _RoundVerdict(results: session.roundResults),
        ],
      ],
    );
  }
}

/// 一个空：判分后能看见对错与正确答案。
class _BlankField extends StatelessWidget {
  const _BlankField({
    required this.controller,
    required this.answer,
    required this.hint,
    required this.scored,
    required this.ok,
    this.focusNode,
  });

  final TextEditingController controller;
  final String answer;
  final String? hint;
  final bool scored;
  final bool? ok;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = scored
        ? (ok ?? false)
            ? theme.colorScheme.primary
            : theme.colorScheme.error
        : theme.colorScheme.outline;
    return SizedBox(
      width: hint == null ? 132 : 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: !scored,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              isDense: true,
              labelText: hint,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: border),
              ),
            ),
            style: theme.textTheme.bodyMedium,
          ),
          if (scored && ok == false)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                answer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 这一轮的对错汇总。
class _RoundVerdict extends StatelessWidget {
  const _RoundVerdict({required this.results});

  final List<bool> results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allOk = goldenFillAllCorrect(results);
    final wrong = results.where((bool r) => !r).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: allOk
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        allOk ? '这一轮全对。' : '有 $wrong 个空不对，看一眼正确答案再重试。',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: allOk
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

/// 拼句正文。
class _AssembleBody extends StatelessWidget {
  const _AssembleBody({required this.session});

  final GoldenDrillSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assembly = session.assembly;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text(
          '按正确顺序点出这句话（点错可以撤销）。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: session.order.isEmpty
              ? Text(
                  '（还没点）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final String w in session.order)
                      Chip(label: Text(w), visualDensity: VisualDensity.compact),
                  ],
                ),
        ),
        if (assembly != null) ...<Widget>[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String w in assembly.bank)
                ActionChip(
                  label: Text(w),
                  onPressed:
                      session.assembleScored ? null : () => session.pick(w),
                ),
            ],
          ),
        ],
        if (session.assembleScored) ...<Widget>[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: session.assembleOk
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              session.assembleOk
                  ? '顺序对了。'
                  : '顺序不对（顺序是：${session.targets.map((t) => t.en).join(' → ')}）。',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

/// 小结正文。
class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.vm, required this.session});

  final GoldenViewModel vm;
  final GoldenDrillSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = vm.recordFor(session.sentenceId);
    final mastered = record?.mastered ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      mastered ? Icons.emoji_events : Icons.school_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      mastered ? '这一句已掌握' : '这一句练过一轮',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  mastered
                      ? '填空、拼句、默写都一次做对，也看过小结了。'
                      : '三步首次都做对，再看一次小结，就算掌握。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(session.text, style: theme.textTheme.bodyLarge),
                if (session.targets.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    session.targets
                        .map((GoldenTarget t) =>
                            '${goldenTargetKindLabel[t.kind] ?? t.kind.name}：${t.en}'
                            '${t.zh == null ? '' : ' — ${t.zh}'}')
                        .join('\n'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '记忆课：先把学习点抄一遍，再不看原文默写整句。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final text = session.targets.isEmpty
                ? session.text
                : '${session.text}\n'
                    '${session.targets.map((GoldenTarget t) => t.en).join(' / ')}';
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制这一句')),
            );
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('复制这一句'),
        ),
      ],
    );
  }
}

/// 吸底：动作条。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.vm,
    required this.session,
    required this.onGoPlan,
    required this.onSubmitFill,
  });

  final GoldenViewModel vm;
  final GoldenDrillSession session;
  final VoidCallback onGoPlan;
  final VoidCallback onSubmitFill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = switch (session.phase) {
      GoldenDrillPhase.fill => session.roundScored
          ? FilledButton.icon(
              onPressed: session.roundOk ? session.nextRound : session.retryRound,
              icon: Icon(
                session.roundOk ? Icons.arrow_forward : Icons.refresh,
              ),
              label: Text(session.roundOk ? '下一轮' : '重试这一轮'),
            )
          : FilledButton.icon(
              onPressed: onSubmitFill,
              icon: const Icon(Icons.check),
              label: const Text('交这一轮'),
            ),
      GoldenDrillPhase.assemble => session.assembleScored
          ? FilledButton.icon(
              onPressed:
                  session.assembleOk ? session.finish : session.retryAssembly,
              icon: Icon(session.assembleOk ? Icons.flag : Icons.refresh),
              label: Text(session.assembleOk ? '看小结' : '重新拼'),
            )
          : FilledButton.icon(
              onPressed:
                  session.order.isEmpty ? null : () => session.submitAssembly(),
              icon: const Icon(Icons.check),
              label: const Text('交拼句'),
            ),
      GoldenDrillPhase.summary => FilledButton.icon(
          onPressed: () => _nextSentence(vm, session, onGoPlan),
          icon: const Icon(Icons.skip_next),
          label: const Text('下一句'),
        ),
    };
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(child: action),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onGoPlan,
            icon: const Icon(Icons.list_alt, size: 18),
            label: const Text('挑句'),
          ),
        ],
      ),
    );
  }
}

/// 下一句：按课程顺序往下走；到末尾就回挑句页。
void _nextSentence(
  GoldenViewModel vm,
  GoldenDrillSession session,
  VoidCallback onGoPlan,
) {
  final rows = vm.ordered;
  final at = rows.indexWhere((GoldenSentence c) => c.id == session.sentenceId);
  if (at >= 0 && at + 1 < rows.length) {
    vm.drill.open(rows[at + 1].id);
    vm.goIndex(at + 1);
    return;
  }
  onGoPlan();
}
