/// 强制锤炼面板：拼写 → 选义 → 写搭配，三步走完才解锁评分。
///
/// 对应 Web 版 `StudyDrill.tsx`。**为什么要有这一屏**：卡停太久说明这一张卡没进脑子，
/// 光翻面看一眼不算过；逼着拼一次、选一次、用一次，才允许打分。
library;

import 'package:flutter/material.dart';

import '../core/vocab/drill_step.dart';
import '../core/vocab/meaning_options.dart';
import '../core/vocab/study_drill.dart';
import 'study_card_view.dart' show MeaningQuizPanel;

/// 锤炼面板。
class StudyDrillPanel extends StatefulWidget {
  const StudyDrillPanel({
    super.key,
    required this.drill,
    required this.onSpell,
    required this.onPick,
    required this.onUsage,
    required this.onTyped,
  });

  final StudyDrill drill;
  final DrillVerdict Function(String input) onSpell;
  final DrillVerdict Function(int index) onPick;
  final DrillVerdict Function(String input) onUsage;
  final void Function(String value) onTyped;

  @override
  State<StudyDrillPanel> createState() => _StudyDrillPanelState();
}

class _StudyDrillPanelState extends State<StudyDrillPanel> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = widget.drill;
    final head = d.head;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(head.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          head.hint,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: d.steps.isEmpty ? 0 : d.stepIndex / d.steps.length,
        ),
        const SizedBox(height: 4),
        Text(
          '第 ${d.stepIndex + 1} / ${d.steps.length} 步',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Text(d.prompt, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        switch (d.step) {
          DrillStep.spell => _spellBody(theme, d),
          DrillStep.meaning => _meaningBody(d),
          DrillStep.usage => _usageBody(theme, d),
          null => Text('过完了，可以评分了', style: theme.textTheme.bodyMedium),
        },
      ],
    );
  }

  Widget _spellBody(ThemeData theme, StudyDrill d) {
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          d.card.word,
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if ((d.card.phonetic ?? '').isNotEmpty)
          Text(
            d.card.phonetic!,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _input,
          autofocus: true,
          enabled: !d.spellMiss,
          decoration: const InputDecoration(
            labelText: '拼一遍',
            hintText: '拼错就直接判「不认识」',
            border: OutlineInputBorder(),
          ),
          onChanged: widget.onTyped,
          onSubmitted: (_) => _submitSpell(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: d.spellMiss ? null : _submitSpell,
          child: const Text('检查'),
        ),
        if (d.spellMiss) ...[
          const SizedBox(height: 8),
          Text(
            '拼错了 · 已判「不认识」',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
      ],
    );
  }

  Widget _meaningBody(StudyDrill d) {
    final options = d.options.map((MeaningOption o) => o.text).toList();
    final correct = d.options.indexWhere((o) => o.correct);
    return MeaningQuizPanel(
      word: d.card.word,
      options: options,
      correctIndex: correct,
      picked: d.picked,
      wrongPick: d.wrongPick,
      onPick: (i) => widget.onPick(i),
    );
  }

  Widget _usageBody(ThemeData theme, StudyDrill d) {
    final scheme = theme.colorScheme;
    final colls = collocationsOf(d.card);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '提示：${colls.first}',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '写一个搭配 / 半句话',
            border: OutlineInputBorder(),
          ),
          onChanged: widget.onTyped,
          onSubmitted: (_) => _submitUsage(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submitUsage,
          child: const Text('检查'),
        ),
      ],
    );
  }

  void _submitSpell() {
    final verdict = widget.onSpell(_input.text);
    if (verdict != DrillVerdict.retry) _input.clear();
  }

  void _submitUsage() {
    final verdict = widget.onUsage(_input.text);
    if (verdict != DrillVerdict.retry) _input.clear();
  }
}
