import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/production.dart';
import '../core/production_draft.dart';
import '../core/production_history.dart';
import '../core/production_prompts.dart';
import '../core/writing.dart';
import '../viewmodels/production_view_model.dart';
import 'ai_paste_sheet.dart';

/// 出题页：三种吃法的设置、选目标块、拼提示词、粘回题目、续做草稿。
///
/// 只读 [ProductionViewModel] 的「准备」那一半（设置 / 目标块池 / 草稿），
/// 不碰作答与批改（那是练习页的事）。
class ProductionSetupView extends StatefulWidget {
  const ProductionSetupView({super.key, required this.onStarted});

  /// 题目就绪（粘回成功 / 续做草稿）后跳到练习页。
  final VoidCallback onStarted;

  @override
  State<ProductionSetupView> createState() => _ProductionSetupViewState();
}

class _ProductionSetupViewState extends State<ProductionSetupView> {
  static const List<String> _topicPresets = <String>[
    '工作沟通',
    '旅行见闻',
    '表达观点',
    '生活小事',
  ];

  late final TextEditingController _topic;
  late final TextEditingController _source;
  late final TextEditingController _reference;

  @override
  void initState() {
    super.initState();
    final s = context.read<ProductionViewModel>().settings;
    _topic = TextEditingController(text: s.topic);
    _source = TextEditingController(text: s.sourceText);
    _reference = TextEditingController(text: s.referenceText);
  }

  @override
  void dispose() {
    _topic.dispose();
    _source.dispose();
    _reference.dispose();
    super.dispose();
  }

  ProductionViewModel get _vm => context.read<ProductionViewModel>();

  void _patch(ProductionSettings Function(ProductionSettings s) f) {
    final vm = _vm;
    vm.updateSettings(f(vm.settings));
  }

  /// 带上本机词块：全脂看 fullUseChunks，脱脂奶看 skimUseChunks。
  bool _useChunks(ProductionSettings s) =>
      s.mode == ProductionMode.full ? s.fullUseChunks : s.skimUseChunks;

  void _setUseChunks(bool value) {
    _patch((s) => s.mode == ProductionMode.full
        ? s.copyWith(fullUseChunks: value)
        : s.copyWith(skimUseChunks: value));
  }

  Future<void> _pickTargets() async {
    final vm = _vm;
    final n = vm.buildTargets();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(n == 0 ? '没选到目标块：换个范围或放宽类型' : '选到 $n 个目标块')),
    );
  }

  Future<void> _start() async {
    final vm = _vm;
    final s = vm.settings;
    if (s.mode == ProductionMode.yogurt) {
      final reason = vm.buildYogurt();
      if (reason != null) return;
      widget.onStarted();
      return;
    }
    if (_useChunks(s)) {
      if (vm.pool.targets.isEmpty) {
        vm.buildTargets();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('先选目标块（${vm.pool.note}）')),
        );
        return;
      }
      final prompt = vm.buildPackPrompt();
      if (prompt == null) return;
      await _openSheet(
        title: '出题（${s.promptCount} 题，每题 ${s.targetsPerPrompt} 个目标块）',
        prompt: prompt,
        hint: '粘回 AI 给的 {"prompts":[...]}，目标块 id 要对得上',
      );
      return;
    }
    await _openSheet(
      title: '出题（${s.promptCount} 题，纯主题）',
      prompt: vm.buildTopicPrompt(),
      hint: '粘回 AI 给的 {"prompts":[...]}',
    );
  }

  Future<void> _openSheet({
    required String title,
    required String prompt,
    required String hint,
  }) async {
    final vm = _vm;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiPasteSheet(
        title: title,
        prompt: prompt,
        hint: hint,
        onApply: (raw) async {
          final reason = vm.applyPack(raw);
          if (reason != null) return reason;
          widget.onStarted();
          return null;
        },
      ),
    );
  }

  Future<void> _continueDraft() async {
    _vm.resumeDraft();
    widget.onStarted();
  }

  Future<void> _previewPairs() async {
    final vm = _vm;
    final result = vm.yogurtPairs();
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('原文和参考译文都要有内容')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PairPreviewSheet(result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductionViewModel>();
    final s = vm.settings;
    final draft = vm.resumableDraft;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _ModePicker(
          value: s.mode,
          onChanged: (m) => _patch((s) => s.copyWith(mode: m)),
        ),
        const SizedBox(height: 12),
        if (draft != null)
          _DraftCard(
            draft: draft,
            onResume: _continueDraft,
            onDiscard: vm.discardDraft,
          ),
        if (s.mode == ProductionMode.yogurt)
          _yogurtCard(s)
        else
          _packCard(s, vm),
        const SizedBox(height: 16),
        _StartBar(
          mode: s.mode,
          onPickTargets: _pickTargets,
          onStart: _start,
          onPreviewPairs: _previewPairs,
        ),
        const SizedBox(height: 20),
        _RecentList(records: productionRecords(vm.history)),
      ],
    );
  }

  Widget _packCard(ProductionSettings s, ProductionViewModel vm) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              productionModeDesc[s.mode] ?? '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _topic,
              decoration: const InputDecoration(
                labelText: '主题',
                hintText: '例如：跟同事确认周五的评审',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _patch((s) => s.copyWith(topic: v)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final p in _topicPresets)
                  ActionChip(
                    label: Text(p),
                    onPressed: () {
                      _topic.text = p;
                      _patch((s) => s.copyWith(topic: p));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _useChunks(s),
              onChanged: _setUseChunks,
              title: const Text('带本机词块'),
              subtitle: Text(
                vm.pool.targets.isEmpty
                    ? '还没选目标块；关掉就是纯主题出题'
                    : '已选 ${vm.pool.targets.length} 个目标块',
              ),
            ),
            const Divider(),
            _EnumField<ProductionAngle>(
              label: '角度',
              value: s.angle,
              items: ProductionAngle.values,
              labelOf: (v) => productionAngleLabel[v] ?? v.name,
              onChanged: (v) => _patch((s) => s.copyWith(angle: v)),
            ),
            _EnumField<ProductionTone>(
              label: '语气',
              value: s.tone,
              items: ProductionTone.values,
              labelOf: (v) => productionToneLabel[v] ?? v.name,
              onChanged: (v) => _patch((s) => s.copyWith(tone: v)),
            ),
            _EnumField<ProductionLevel>(
              label: '难度',
              value: s.level,
              items: ProductionLevel.values,
              labelOf: (v) => productionLevelLabel[v] ?? v.name,
              onChanged: (v) => _patch((s) => s.copyWith(level: v)),
            ),
            _EnumField<ProductionVariant>(
              label: '题型',
              value: s.variant,
              items: ProductionVariant.values,
              labelOf: (v) => productionVariantLabel[v] ?? v.name,
              onChanged: (v) => _patch((s) => s.copyWith(variant: v)),
            ),
            _EnumField<ProductionScope>(
              label: '范围',
              value: s.scope,
              items: ProductionScope.values,
              labelOf: (v) => productionScopeLabel[v] ?? v.name,
              onChanged: (v) => _patch((s) => s.copyWith(scope: v)),
            ),
            const SizedBox(height: 8),
            const _FieldLabel('目标块类型'),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final k in ProductionTargetKind.values)
                  FilterChip(
                    label: Text(_kindLabel(k)),
                    selected: s.types.contains(k),
                    onSelected: (on) {
                      final next = <ProductionTargetKind>[...s.types];
                      if (on) {
                        if (!next.contains(k)) next.add(k);
                      } else {
                        next.remove(k);
                      }
                      if (next.isEmpty) return;
                      _patch((s) => s.copyWith(types: next));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const _FieldLabel('本轮配置'),
            _IntChips(
              label: '题数',
              values: productionPromptCounts,
              value: s.promptCount,
              onChanged: (v) => _patch((s) => s.copyWith(promptCount: v)),
            ),
            _IntChips(
              label: '每题块数',
              values: productionTargetsPerPrompt,
              value: s.targetsPerPrompt,
              onChanged: (v) => _patch((s) => s.copyWith(targetsPerPrompt: v)),
            ),
            _IntChips(
              label: '薄弱优先',
              values: productionWeakRatios,
              value: s.weakRatio,
              format: (v) => v == 0 ? '不优先' : '$v%',
              onChanged: (v) => _patch((s) => s.copyWith(weakRatio: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _yogurtCard(ProductionSettings s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              productionModeDesc[s.mode] ?? '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _EnumField<ProductionDirection>(
              label: '方向',
              value: s.yogurtDirection,
              items: ProductionDirection.values,
              labelOf: (v) => v == ProductionDirection.zhEn ? '中 → 英' : '英 → 中',
              onChanged: (v) => _patch((s) => s.copyWith(yogurtDirection: v)),
            ),
            _EnumField<YogurtSplitMode>(
              label: '拆句',
              value: s.yogurtSplit,
              items: YogurtSplitMode.values,
              labelOf: (v) => v == YogurtSplitMode.sentence ? '按句号' : '按换行',
              onChanged: (v) => _patch((s) => s.copyWith(yogurtSplit: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.yogurtParagraph,
              onChanged: (v) => _patch((s) => s.copyWith(yogurtParagraph: v)),
              title: const Text('最后加整段连写'),
            ),
            TextField(
              controller: _source,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '原文',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _patch((s) => s.copyWith(sourceText: v)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '参考译文',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _patch((s) => s.copyWith(referenceText: v)),
            ),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(ProductionTargetKind k) => switch (k) {
        ProductionTargetKind.word => '单词',
        ProductionTargetKind.phrase => '词组',
        ProductionTargetKind.idiom => '习语',
      };
}

/// 三种吃法的选择条。
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.value, required this.onChanged});

  final ProductionMode value;
  final ValueChanged<ProductionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SegmentedButton<ProductionMode>(
          segments: <ButtonSegment<ProductionMode>>[
            for (final m in ProductionMode.values)
              ButtonSegment<ProductionMode>(
                value: m,
                label: Text(productionModeLabel[m] ?? m.name),
              ),
          ],
          selected: <ProductionMode>{value},
          onSelectionChanged: (Set<ProductionMode> s) => onChanged(s.first),
        ),
      ],
    );
  }
}

/// 暂停中的草稿：接着做，或者扔掉。
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.onResume,
    required this.onDiscard,
  });

  final ProductionDraft draft;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final at = DateTime.tryParse(draft.at)?.toLocal();
    final when = at == null
        ? ''
        : '${at.month}月${at.day}日 ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '上一组还没做完：第 ${draft.index + 1}/${draft.prompts.length} 题'
                '${when.isEmpty ? '' : '（$when 暂停）'}',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            TextButton(onPressed: onDiscard, child: const Text('扔掉')),
            FilledButton(onPressed: onResume, child: const Text('接着做')),
          ],
        ),
      ),
    );
  }
}

/// 底部主按钮：选目标块 / 拆句预览 / 开始出题。
class _StartBar extends StatelessWidget {
  const _StartBar({
    required this.mode,
    required this.onPickTargets,
    required this.onStart,
    required this.onPreviewPairs,
  });

  final ProductionMode mode;
  final VoidCallback onPickTargets;
  final VoidCallback onStart;
  final VoidCallback onPreviewPairs;

  @override
  Widget build(BuildContext context) {
    if (mode == ProductionMode.yogurt) {
      return Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPreviewPairs,
              icon: const Icon(Icons.splitscreen_outlined),
              label: const Text('拆句预览'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始逐句拷打'),
            ),
          ),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPickTargets,
            icon: const Icon(Icons.filter_alt_outlined),
            label: const Text('选目标块'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('开始出题'),
          ),
        ),
      ],
    );
  }
}

/// 最近几条产出记录。
class _RecentList extends StatelessWidget {
  const _RecentList({required this.records});

  final List<WritingRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Text(
        '还没有产出记录。',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final shown = records.length > 5
        ? records.sublist(records.length - 5).reversed.toList()
        : records.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _FieldLabel('最近的产出'),
        for (final rec in shown)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(writingRecordLabel(rec)),
            subtitle: Text(
              '${rec.feedback.total}/${rec.feedback.max}'
              '${rec.text.isEmpty ? '' : ' · ${rec.text}'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

/// 一行「标签 + 下拉」。
class _EnumField<T> extends StatelessWidget {
  const _EnumField({
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            items: <DropdownMenuItem<T>>[
              for (final it in items)
                DropdownMenuItem<T>(value: it, child: Text(labelOf(it))),
            ],
            onChanged: (T? v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

/// 一行「标签 + 若干整数 chip」。
class _IntChips extends StatelessWidget {
  const _IntChips({
    required this.label,
    required this.values,
    required this.value,
    required this.onChanged,
    this.format,
  });

  final String label;
  final List<int> values;
  final int value;
  final ValueChanged<int> onChanged;
  final String Function(int value)? format;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: 72, child: Text(label)),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                for (final v in values)
                  ChoiceChip(
                    label: Text(format?.call(v) ?? '$v'),
                    selected: v == value,
                    onSelected: (_) => onChanged(v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 小节标题。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

/// 拆句预览：看看中英两边是不是一对一。
class _PairPreviewSheet extends StatelessWidget {
  const _PairPreviewSheet({required this.result});

  final YogurtPairResult result;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '拆句预览：${result.sourceCount} 句 / ${result.referenceCount} 句',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (result.warning.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                result.warning,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: result.pairs.length,
                separatorBuilder: (BuildContext context, int i) =>
                    const Divider(),
                itemBuilder: (BuildContext context, int i) {
                  final p = result.pairs[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${i + 1}. ${p.source}'),
                      if (p.reference.isNotEmpty)
                        Text(
                          p.reference,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
