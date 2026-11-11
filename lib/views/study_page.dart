/// 背单词页：设置 → 单词卡 / 选释义 / 组末拼写 → 小结。
///
/// 界面只做三件事：把 ViewModel 的状态画出来、把点击翻译成 ViewModel 的方法、
/// 决定「现在该显示哪一张」。所有判定（要不要先选释义、判哪一档、什么时候停下拼写）
/// 都在 `core/study_session.dart` 里，这里不许再算一遍。
library;

import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

import '../core/drill_sentence.dart';
import '../core/entry_kind.dart';
import '../core/study_pool.dart';
import '../core/study_session.dart';
import '../core/vocab/learn_step.dart';
import '../core/vocab/meaning_options.dart';
import '../core/vocab/review.dart';
import '../core/vocab/word.dart' show displayMeaning;
import '../models/vocab.dart';
import '../viewmodels/study_view_model.dart';
import 'drill_sentence_page.dart';

/// 背单词页。
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudyViewModel>().bootstrap();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 合并写意味着最后一次评分可能还只在内存里。切后台时先把盘补完，
    // 免得进程被系统杀掉丢一次评分。界面不等它（见 flushWrites 注释）。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      context.read<StudyViewModel>().flushWrites();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: Text(vm.started ? '背单词' : '背单词'),
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
              child: vm.started ? const _SessionBody() : const _SetupBody(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 开轮之前的设置面板。
class _SetupBody extends StatelessWidget {
  const _SetupBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyViewModel>();
    final theme = Theme.of(context);
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
                Text('范围', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final scope in StudyScope.values)
                      ChoiceChip(
                        label: Text(studyScopeLabel[scope] ?? scope.name),
                        selected: vm.scope == scope,
                        onSelected: (_) => vm.settings.setScope(scope),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('牌组', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<StudyDeck>(
                  segments: const [
                    ButtonSegment(value: StudyDeck.word, label: Text('单词')),
                    ButtonSegment(value: StudyDeck.collocation, label: Text('搭配')),
                  ],
                  selected: {vm.deck},
                  onSelectionChanged: (s) => vm.settings.setDeck(s.first),
                ),
                const SizedBox(height: 16),
                Text('每组词数', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final n in const [0, 10, 20, 30])
                      ChoiceChip(
                        label: Text(n == 0 ? '跟范围' : '$n'),
                        selected: vm.groupSize == n,
                        onSelected: (_) => vm.settings.setGroupSize(n),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('每天新词上限', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final n in const [0, 10, 20, 30, 50])
                      ChoiceChip(
                        label: Text(n == 0 ? '不限' : '$n'),
                        selected: vm.newLimit == n,
                        onSelected: (_) => vm.settings.setNewLimit(n),
                      ),
                  ],
                ),
                if (vm.newLimit > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '今天已引入 ${vm.newToday}/${vm.newLimit}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text('候选 ${counts.total} 个'),
            subtitle: Text('该复习 ${counts.due} · 没学过 ${counts.fresh}'),
            trailing: Text('每组 ${vm.effectiveGroupSize}'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: counts.fresh == 0
              ? null
              : () => _start(context, vm, StudyMode.learn),
          icon: const Icon(Icons.school_outlined),
          label: const Text('学新词'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: counts.due == 0
              ? null
              : () => _start(context, vm, StudyMode.review),
          icon: const Icon(Icons.replay_outlined),
          label: const Text('复习到期的'),
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

  void _start(BuildContext context, StudyViewModel vm, StudyMode mode) {
    final n = vm.startRound(mode: mode);
    if (n == 0) {
      // ViewModel 可能已经给了更具体的原因（比如额度用完），优先显示它。
      final message = vm.error ??
          (mode == StudyMode.learn ? '没有新词' : '没有到期的词');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}

/// 一轮之内的三种界面：组末拼写 / 选释义 / 单词卡（+ 小结）。
class _SessionBody extends StatelessWidget {
  const _SessionBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StudyViewModel>();
    final s = vm.session;
    if (s == null) return const SizedBox.shrink();
    final spelling = s.spelling;
    if (spelling != null && spelling.active) {
      return _SpellingBody(round: spelling);
    }
    final view = s.view;
    if (view.card == null) return _SummaryBody(session: s);
    if (view.meaningGate) return _MeaningBody(options: s.options);
    return _CardBody(card: view.card!, session: s);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          LinearProgressIndicator(value: pct),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(label ?? '$done / $total'),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }
}

/// 「选中文释义」这一步。
class _MeaningBody extends StatelessWidget {
  const _MeaningBody({required this.options});

  final List<MeaningOption> options;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<StudyViewModel>();
    final s = vm.session;
    final card = s?.card;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (s != null)
          _Progress(
            done: s.index,
            total: s.roundTotal,
            label: '第 ${s.index + 1} / ${s.roundTotal} 个 · 先选释义',
          ),
        const SizedBox(height: 8),
        if (card != null)
          Text(
            card.word,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 16),
        for (final (i, o) in options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => _pick(vm, i, o.correct, options),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${'ABCD'[i]}. ${o.text}'),
              ),
            ),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            await vm.learnStep(LearnAction.reveal);
            await Future<void>.delayed(learnRevealHold);
            vm.clearLastOutcome();
            await vm.grade(ReviewGrade.again, learnPass: false);
          },
          child: const Text('不认识，看答案'),
        ),
      ],
    );
  }

  Future<void> _pick(
    StudyViewModel vm,
    int index,
    bool correct,
    List<MeaningOption> options,
  ) async {
    final step = await vm.learnStep(
      correct ? LearnAction.correct : LearnAction.wrong,
    );
    if (step == null) return;
    if (step.kind == LearnStepKind.card) return;
    // 选错：先停一下把正确项亮出来，再按「不认识」落库
    await Future<void>.delayed(learnRevealHold);
    await vm.grade(step.grade ?? ReviewGrade.again, learnPass: step.pass);
  }
}

/// 单词卡：词 + 音标 + 释义 + 三档评分。
class _CardBody extends StatelessWidget {
  const _CardBody({required this.card, required this.session});

  final VocabItem card;
  final StudySession session;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<StudyViewModel>();
    final theme = Theme.of(context);
    final meaning = displayMeaning(
      partOfSpeech: card.partOfSpeech,
      meaning: card.meaning,
    );
    final example = card.examples.isEmpty ? null : card.examples.first;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Progress(
          done: session.index,
          total: session.roundTotal,
          label: '第 ${session.index + 1} / ${session.roundTotal} 个'
              '${session.view.isExtraCard ? ' · 加练' : ''}',
        ),
        const SizedBox(height: 8),
        if (vm.lastOutcome != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${vm.lastOutcome!.label} · 下次复习：${fmtInterval(vm.lastOutcome!.interval)}',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
        Text(
          card.word,
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        if ((card.phonetic ?? '').isNotEmpty)
          Text(
            card.phonetic!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (meaning.isNotEmpty) Text(meaning),
                if ((card.definition ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    card.definition!,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (example != null) ...[
                  const SizedBox(height: 12),
                  Text(example.text, style: theme.textTheme.bodySmall),
                  if ((example.translation ?? '').isNotEmpty)
                    Text(
                      example.translation!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
                if (card.usage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(card.usage.join('；'), style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => vm.grade(ReviewGrade.again),
                child: const Text('忘记'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => vm.grade(ReviewGrade.hard),
                child: const Text('模糊'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => vm.grade(ReviewGrade.good),
                child: const Text('认识'),
              ),
            ),
          ],
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
    return ListView(      padding: const EdgeInsets.all(16),
      children: [
        _Progress(
          done: round.index,
          total: round.total,
          label: '本组验收 · 第 ${round.index + 1} / ${round.total} 个',
        ),
        const SizedBox(height: 16),
        if (miss == null)
          Text(
            displayMeaning(
              partOfSpeech: word.partOfSpeech,
              meaning: word.meaning,
            ),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          )
        else
          Column(
            children: [
              Text(
                miss.word,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 4),
              Text(miss.meaning, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                '刚才写的是「${miss.typed}」，照着上面的词再打一遍',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        const SizedBox(height: 24),
        TextField(
          controller: _input,
          autofocus: true,
          enabled: miss == null,
          decoration: const InputDecoration(
            labelText: '拼写',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _check(vm),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _check(vm),
          child: Text(miss == null ? '检查' : '再打一遍'),
        ),
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
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: '认识', value: c.know),
                _Stat(label: '模糊', value: c.fuzzy),
                _Stat(label: '忘记', value: c.forgot),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (session.forgotIds.isNotEmpty && session.canRetryForgot)
          FilledButton(
            onPressed: () => vm.retryForgot(),
            child: Text('重练忘记的 ${session.forgotIds.length} 个'),
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
          child: const Text('回到设置'),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('$value', style: theme.textTheme.headlineMedium),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

