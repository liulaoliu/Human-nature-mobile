import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/golden.dart';
import '../data/repositories/article_repository.dart' show ArticleRow;
import '../models/document.dart';
import '../viewmodels/golden_view_model.dart';
import 'ai_paste_sheet.dart';

/// 挑句页：选文章 → 看推荐句 → 勾选 → 调课程设置 → 开始练。
///
/// 主按钮吸底：设置项不少（去重 / 挖空单位 / 整句加练 / 小测间隔），
/// 滚到底才找得到「开始」的话，每改一项都要重新滚一趟。
class GoldenPlanView extends StatelessWidget {
  const GoldenPlanView({super.key, required this.onStarted});

  /// 开始练习（切到练习页）。
  final VoidCallback onStarted;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GoldenViewModel>();
    if (vm.article == null) {
      return _ArticlePicker(
        library: vm.library,
        onOpen: (String id) async {
          await vm.openArticle(id);
        },
      );
    }
    return Column(
      children: <Widget>[
        Expanded(child: _PlanBody(vm: vm)),
        _StartBar(
          selected: vm.ordered.length,
          onStart: () {
            final target = vm.ordered.isEmpty ? null : vm.ordered.first;
            if (target != null) vm.drill.open(target.id);
            onStarted();
          },
          onSwitch: () => vm.clearNotice(),
        ),
      ],
    );
  }
}

/// 还没选文章时的列表。
class _ArticlePicker extends StatelessWidget {
  const _ArticlePicker({required this.library, required this.onOpen});

  final List<ArticleRow> library;
  final Future<void> Function(String id) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (library.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '还没有文章。先去「精读」里粘一篇原文。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('挑一篇文章', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '金句课跟着文章走：同一篇的挑句、学习点、掌握情况都存在文章里。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final ArticleRow row in library)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.article_outlined),
              title: Text(row.title.isEmpty ? '未命名' : row.title),
              subtitle: Text(row.updatedAt),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(row.id),
            ),
          ),
      ],
    );
  }
}

/// 正文：候选句 + 已选 + 设置 + AI 挑句。
class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.vm});

  final GoldenViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lesson = vm.lesson;
    final selected = lesson == null
        ? const <String>[]
        : (lesson.selected.isEmpty
            ? lesson.sentences.map((s) => s.id).toList()
            : lesson.selected);
    final summary = vm.summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(vm.articleTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  summary == null
                      ? '${vm.sentences.length} 句'
                      : '${vm.sentences.length} 句 · 选了 ${summary.selectedSentences} 句 · '
                          '掌握 ${summary.masteredSentences} 句 / '
                          '${summary.masteredTargets} 个学习点',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () =>
                          vm.editor.setPick(GoldenPickMode.recommended),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('选推荐句'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => vm.editor.setPick(GoldenPickMode.all),
                      icon: const Icon(Icons.select_all, size: 18),
                      label: const Text('全选'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openAiSheet(context, vm),
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('让 AI 挑'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => vm.closeArticle(),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('换一篇'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsCard(vm: vm),
        const SizedBox(height: 12),
        if (vm.ordered.isNotEmpty) ...<Widget>[
          _SelectedCard(vm: vm),
          const SizedBox(height: 12),
        ],
        Text('候选句', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '按「语言点多、词块多、长度合适」打分排序，同分按原文顺序。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final GoldenCandidate c in vm.candidates) ...<Widget>[
          _CandidateTile(
            vm: vm,
            candidate: c,
            sentence: vm.sentences.firstWhere((s) => s.id == c.id),
            selected: selected.contains(c.id),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// 一门课的四项设置。
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.vm});

  final GoldenViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = vm.lesson?.options ?? const GoldenLessonOptions();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('这一课怎么练', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: options.dedupe,
              onChanged: (bool v) => vm.editor.setDedupe(v),
              title: const Text('同一个学习点只练一次'),
              subtitle: const Text('关掉就是每句各自练一遍（同一个搭配可能在多句出现）'),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: options.sentenceFill ?? true,
              onChanged: (bool v) => vm.editor.setSentenceFill(v),
              title: const Text('填空之后加练整句'),
              subtitle: const Text('关掉只练学习点，快一些'),
            ),
            const SizedBox(height: 8),
            _ChoiceRow<GoldenBlankUnit>(
              label: '挖空单位',
              values: GoldenBlankUnit.values,
              value: options.blankUnit ?? GoldenBlankUnit.word,
              labelOf: (GoldenBlankUnit v) =>
                  v == GoldenBlankUnit.target ? '整块' : '按词',
              onPick: (GoldenBlankUnit v) => vm.editor.setBlankUnit(v),
            ),
            const SizedBox(height: 8),
            _ChoiceRow<int>(
              label: '小测间隔',
              values: const <int>[0, 5, 10],
              value: options.examAfter ?? 0,
              labelOf: (int v) => v == 0 ? '不安排' : '每 $v 句',
              onPick: (int v) => vm.editor.setExamAfter(v == 0 ? null : v),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已选句子（带掌握状态，点开直接练这一句）。
class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.vm});

  final GoldenViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = vm.ordered;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('这一课练这 ${rows.length} 句', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final GoldenSentence content in rows) ...<Widget>[
              _SelectedTile(
                text: vm.textOf(content.id),
                targets: content.targets,
                mastered: vm.masteredFor(content.id),
                onTap: () {
                  vm.drill.open(content.id);
                  vm.clearNotice();
                },
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一句已选：点一下直接开练这一句。
class _SelectedTile extends StatelessWidget {
  const _SelectedTile({
    required this.text,
    required this.targets,
    required this.mastered,
    required this.onTap,
  });

  final String text;
  final List<GoldenTarget> targets;
  final bool mastered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  mastered ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: mastered
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(text, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
            if (targets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  targets
                      .map((GoldenTarget t) =>
                          '${goldenTargetKindLabel[t.kind] ?? t.kind.name}：${t.en}')
                      .join(' · '),
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

/// 一条候选句：分数 + 为什么 + 勾选 + 加练语言点。
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.vm,
    required this.candidate,
    required this.sentence,
    required this.selected,
  });

  final GoldenViewModel vm;
  final GoldenCandidate candidate;
  final Sentence sentence;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extras = vm.editor.extraPointsFor(sentence.id);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Checkbox(
                  value: selected,
                  onChanged: (_) => vm.editor.toggleSentence(sentence.id),
                ),
                Expanded(
                  child: Text(sentence.text, style: theme.textTheme.bodyMedium),
                ),
                Text(
                  '${candidate.score}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (candidate.reasons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 4),
                child: Text(
                  candidate.reasons.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  for (final GoldenExtraPoint p in extras)
                    Chip(
                      label: Text(p.en),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () =>
                          vm.editor.removeExtraPoint(p.sentenceId, p.en),
                    ),
                  TextButton.icon(
                    onPressed: () => _addExtraPoint(context, vm, sentence.id),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('加语言点'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主按钮吸底。
class _StartBar extends StatelessWidget {
  const _StartBar({
    required this.selected,
    required this.onStart,
    required this.onSwitch,
  });

  final int selected;
  final VoidCallback onStart;
  final VoidCallback onSwitch;

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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              onPressed: selected == 0 ? null : onStart,
              icon: const Icon(Icons.play_arrow),
              label: Text(selected == 0 ? '先选句子' : '开始第 1 句（共 $selected 句）'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onSwitch,
            icon: const Icon(Icons.refresh),
            tooltip: '收起提示',
          ),
        ],
      ),
    );
  }
}

/// 一行选项（用 ChoiceChip，比下拉在手机上更好点）。
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.values,
    required this.value,
    required this.labelOf,
    required this.onPick,
  });

  final String label;
  final List<T> values;
  final T value;
  final String Function(T value) labelOf;
  final void Function(T value) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final T v in values)
              ChoiceChip(
                label: Text(labelOf(v)),
                selected: v == value,
                onSelected: (_) => onPick(v),
              ),
          ],
        ),
      ],
    );
  }
}

/// 「让 AI 挑句」：打开粘回面板。
void _openAiSheet(BuildContext context, GoldenViewModel vm) {
  final prompt = vm.buildPrompt();
  if (prompt == null) return;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AiPasteSheet(
      title: '让 AI 挑金句',
      prompt: prompt,
      hint: '粘回 AI 给的课程 JSON（句 id 要对得上原文）',
      onApply: (String raw) async {
        final reason = await vm.applyAi(raw);
        return reason;
      },
    ),
  );
}

/// 手动给某一句加一条加练语言点。
Future<void> _addExtraPoint(
  BuildContext context,
  GoldenViewModel vm,
  String sentenceId,
) async {
  final controller = TextEditingController();
  final zhController = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('加一条语言点'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '英文（要在这句里逐字出现）',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: zhController,
            decoration: const InputDecoration(labelText: '中文（可空）'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('加上'),
        ),
      ],
    ),
  );
  final en = controller.text;
  final zh = zhController.text;
  controller.dispose();
  zhController.dispose();
  if (ok ?? false) {
    await vm.editor.addExtraPoint(sentenceId, en, zh: zh);
  }
}
