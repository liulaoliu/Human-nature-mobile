/// 背单词页：开轮入口 → 单词卡 / 选释义 / 锤炼 / 组末拼写 → 小结。
///
/// 界面只做三件事：把状态画出来、把点击翻译成方法、决定「现在该显示哪一张」。
/// 所有判定都在 core 里（`study_session` / `study_card_flow` / `study_drill`），
/// 这里不许再算一遍。
///
/// **设置项不在这里**：范围 / 牌组 / 每组词数 / 每天新词 / 锤炼阈值都搬到
/// `settings_page.dart`（从首页侧边栏进）。这一页只管练。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/drill_sentence.dart';
import '../core/entry_kind.dart' show StudyDeck;
import '../core/study_session.dart';
import '../core/vocab/meaning_options.dart';
import '../core/vocab/review.dart';
import '../core/vocab/word.dart' show displayMeaning;
import '../models/vocab.dart';
import '../viewmodels/study_card_flow.dart';
import '../viewmodels/study_view_model.dart';
import '../widgets/status_bar.dart';
import 'drill_sentence_page.dart';
import 'study_actions.dart';
import 'study_card_view.dart';
import 'study_drill_view.dart';

/// 背单词页。
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with WidgetsBindingObserver {
  StudyCardFlow? _flow;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<StudyViewModel>();
      vm.bootstrap();
      if (mounted) {
        setState(() => _flow = StudyCardFlow(vm));
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _flow?.tick());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flow?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 合并写意味着最后一次评分可能还只在内存里。切后台时先把盘补完，
    // 免得进程被系统杀掉丢一次评分。界面不等它（见 flushWrites 注释）。
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      context.read<StudyViewModel>().flushWrites();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyViewModel>();
    final flow = _flow;
    return Scaffold(
      appBar: AppBar(
        title: const Text('背单词'),
        actions: [
          if (vm.started)
            TextButton(
              onPressed: () {
                vm.endRound();
                vm.flushLedger();
              },
              child: const Text('结束本轮'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.saveError != null) StatusBar.error(message: vm.saveError!),
            if (vm.busy) const LinearProgressIndicator(),
            Expanded(
              child: vm.started && flow != null
                  ? ListenableBuilder(
                      listenable: flow,
                      builder: (_, _) => _SessionBody(flow: flow),
                    )
                  : _SetupBody(onStart: _start, onStudiedToday: _startStudiedToday),
            ),
          ],
        ),
      ),
    );
  }

  void _start(StudyMode mode) {
    final vm = context.read<StudyViewModel>();
    final n = vm.startRound(mode: mode);
    if (n == 0) {
      final message = vm.error ?? (mode == StudyMode.learn ? '没有新词' : '没有到期的词');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _startStudiedToday() {
    final vm = context.read<StudyViewModel>();
    final n = vm.startStudiedTodayRound();
    if (n == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vm.error ?? '今天还没背过词')),
      );
    }
  }
}

/// 开轮之前的入口（设置项在设置页）。
class _SetupBody extends StatelessWidget {
  const _SetupBody({required this.onStart, required this.onStudiedToday});

  final void Function(StudyMode mode) onStart;

  /// 「今天背过的再过一遍」。
  final VoidCallback onStudiedToday;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyViewModel>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = vm.poolCounts;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('候选 ${counts.total} 个', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    Text(
                      '每组 ${vm.effectiveGroupSize}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '该复习 ${counts.due} · 没学过 ${counts.fresh}'
                  '${vm.newLimit > 0 ? ' · 今天新词 ${vm.newToday}/${vm.newLimit}' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: counts.fresh == 0 ? null : () => onStart(StudyMode.learn),
          icon: const Icon(Icons.school_outlined),
          label: const Text('学新词'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: counts.due == 0 ? null : () => onStart(StudyMode.review),
          icon: const Icon(Icons.replay_outlined),
          label: const Text('复习到期的'),
        ),
        const SizedBox(height: 16),
        Text(
          '今天已背 ${vm.studiedToday} 个',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (vm.studiedToday > 0) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => onStudiedToday(),
            icon: const Icon(Icons.history_outlined),
            label: Text('今天背过的再过一遍（${vm.studiedToday}）'),
          ),
          const SizedBox(height: 4),
          Text(
            '这些词的复习时间已经排到明天以后，正常队列当天不会再出现；'
            '想当天复看就点上面这个。',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '范围和牌组在首页「背单词」那一行的小按键里改；每组词数、新词上限在「设置」里。',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 一轮之内的几种界面。
class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.flow});

  final StudyCardFlow flow;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyViewModel>();
    final s = vm.session;
    if (s == null) return const SizedBox.shrink();

    final spelling = s.spelling;
    if (spelling != null && spelling.active) {
      return _SpellingBody(round: spelling);
    }

    // 锤炼优先：没过完就不给评分
    final drill = flow.drill;
    if (drill != null) {
      return StudyDrillPanel(
        drill: drill,
        onSpell: flow.submitDrillSpell,
        onPick: flow.pickDrillMeaning,
        onUsage: flow.submitDrillUsage,
        onTyped: flow.setDrillTyped,
      );
    }

    final view = s.view;
    if (view.card == null) return _SummaryBody(session: s);

    // 超时 / 重学补考：进面板之前先拦一下
    final reason = flow.drillReasonNow;
    if (reason != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (flow.drill == null) flow.startDrill(reason);
      });
    }

    if (view.meaningGate) {
      return _MeaningBody(flow: flow, options: s.options);
    }

    return _CardBody(flow: flow, session: s);
  }
}

/// 进度条上的「第几张 / 共几张」。
class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total, this.label});

  final int done;
  final int total;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Column(
      children: [
        LinearProgressIndicator(value: pct),
        const SizedBox(height: 6),
        Row(children: [Text(label ?? '$done / $total'), const Spacer()]),
      ],
    );
  }
}

/// 「选中文释义」这一步（学习模式的门禁）。
class _MeaningBody extends StatelessWidget {
  const _MeaningBody({required this.flow, required this.options});

  final StudyCardFlow flow;
  final List<MeaningOption> options;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<StudyViewModel>();
    final s = vm.session;
    final card = s?.card;
    if (card == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Progress(
          done: s!.index,
          total: s.roundTotal,
          label: '第 ${s.index + 1} / ${s.roundTotal} 个 · 先选释义',
        ),
        const SizedBox(height: 24),
        MeaningQuizPanel(
          word: card.word,
          options: [for (final o in options) o.text],
          correctIndex: options.indexWhere((o) => o.correct),
          onPick: (i) => flow.pickMeaning(i, options[i].correct),
          onReveal: flow.revealAnswer,
        ),
      ],
    );
  }
}

/// 单词卡：热度边框 + 翻面 + 评分。
class _CardBody extends StatelessWidget {
  const _CardBody({required this.flow, required this.session});

  final StudyCardFlow flow;
  final StudySession session;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<StudyViewModel>();
    final theme = Theme.of(context);
    final extra = session.view.isExtraCard ? ' · 加练' : '';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    '第 ${session.index + 1} / ${session.roundTotal} 个$extra',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  StudyTimerChip(flow: flow),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: session.roundTotal <= 0
                    ? 0
                    : (session.index / session.roundTotal).clamp(0.0, 1.0),
              ),
              if (vm.lastOutcome != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${vm.lastOutcome!.label} · 下次复习：${fmtInterval(vm.lastOutcome!.interval)}',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              StudyCardPanel(
                flow: flow,
                onSpeak: () => flow.speak(),
                onMarkUnknown: () => flow.markUnknown(),
              ),
            ],
          ),
        ),
        // 长内容吸底：动作区不跟着滚走
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: SafeArea(
            top: false,
            child: StudyActions(
              flow: flow,
              onNext: vm.forward,
              onShowMeaning: flow.reveal,
            ),
          ),
        ),
      ],
    );
  }
}

/// 组末拼写：本组学了多少就拼多少；拼错显示原文，照着重打一遍。
class _SpellingBody extends StatefulWidget {
  const _SpellingBody({required this.round});

  final SpellingRound round;

  @override
  State<_SpellingBody> createState() => _SpellingBodyState();
}

class _SpellingBodyState extends State<_SpellingBody> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyViewModel>();
    final round = widget.round;
    final word = round.card;
    if (word == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final miss = round.miss;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Progress(
          done: round.index,
          total: round.total,
          label: '⏱ 组末拼写 · 第 ${round.index + 1} / ${round.total} 个',
        ),
        const SizedBox(height: 8),
        Text(
          '本组全部过一遍，认识且拼对才算记住',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          displayMeaning(partOfSpeech: word.partOfSpeech, meaning: word.meaning),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (miss != null) ...[
          const SizedBox(height: 12),
          Text(
            '✘ 拼写错误：你写的是「${miss.typed}」',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
          if (_input.text.isEmpty)
            Text(
              miss.word,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '已判为「不认识」。照着再拼一遍加深印象——一开始输入，原文就会消失',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _input,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '拼写',
            hintText: miss == null ? '拼出这个英文单词，回车检查' : '凭记忆再拼一遍，回车检查',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _check(vm),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => _check(vm), child: const Text('检查')),
      ],
    );
  }

  Future<void> _check(StudyViewModel vm) async {
    final text = _input.text;
    await vm.checkSpelling(text);
    _input.clear();
  }
}

/// 小结：认识 / 模糊 / 忘记 各多少，能重练忘记的。
class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.session});

  final StudySession session;

  /// 结算页的「用这一轮的词造句」：本轮队列就是素材，牌组决定拷打种类。
  Future<void> _openDrill(
    BuildContext context,
    StudyViewModel vm,
    StudySession s,
  ) async {
    final kind = vm.deck == StudyDeck.collocation
        ? DrillSentenceKind.chunk
        : DrillSentenceKind.memory;
    final results = <({String? id, String itemId})>[
      for (final VocabItem it in s.queue) (id: null, itemId: it.id),
    ];
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DrillSentencePage(
          items: s.queue,
          results: results,
          kind: kind,
          articleId: vm.articleId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<StudyViewModel>();
    final theme = Theme.of(context);
    final c = session.counts;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 24),
        Text('这一轮结束了', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '认识 ${c.know} · 模糊 ${c.fuzzy} · 忘记了 ${c.forgot}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (session.forgotIds.isNotEmpty && session.canRetryForgot)
          FilledButton(
            onPressed: () => vm.retryForgot(),
            child: Text('重练忘记的 ${session.forgotIds.length} 个'),
          )
        else
          Text(
            '本轮已重练过一次，先按当前评分排期',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => _openDrill(context, vm, session),
          icon: const Icon(Icons.edit_note_outlined),
          label: const Text('用这一轮的词造句'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            vm.endRound();
            vm.flushLedger();
          },
          child: const Text('回到开轮'),
        ),
        const SizedBox(height: 16),
        Text(
          '今天已背 ${vm.studiedToday} 个',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
