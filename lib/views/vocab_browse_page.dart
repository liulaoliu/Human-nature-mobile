/// 词库浏览页：筛选（范围 / 类型 / 状态 / 入库日 / 搜索）→ 列表。
///
/// 筛选与计数全部走 `core/vocab_browse.dart`（有 17 例兜着），这里只画控件、
/// 把点击翻译成 ViewModel 的方法。排序在 ViewModel 里做（`BrowseSort`）。
library;

import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

import '../core/ports.dart' show SpeechPort;
import '../core/vocab/word.dart' show displayMeaning;
import '../models/vocab.dart';
import '../viewmodels/tts_view_model.dart';
import '../viewmodels/vocab_browse_view_model.dart';
import 'dict_tools_sheet.dart' show DictToolsSheet;
import 'vocab_filter_sheet.dart' show showVocabFilters, vocabFilterSummary;

/// 词库浏览页。
class VocabBrowsePage extends StatefulWidget {
  const VocabBrowsePage({super.key, this.speech});

  /// 朗读端口；不传就用全局朗读设置（测试里注入假实现）。
  final SpeechPort? speech;

  @override
  State<VocabBrowsePage> createState() => _VocabBrowsePageState();
}

class _VocabBrowsePageState extends State<VocabBrowsePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VocabBrowseViewModel>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VocabBrowseViewModel>();
    final items = vm.items;
    // 点词即读（用户 2026-11-17 要求）：跟朗读设置共用同一个 PickSpeech，
    // 单句走内存合成，不落音频文件（见 docs/TTS-PITFALLS.md）。
    final speech = widget.speech ?? context.read<TtsViewModel?>()?.speech;
    return Scaffold(
      appBar: AppBar(
        title: Text('词库（${items.length}）'),
        actions: [
          // 四组筛选条件收在面板里（日常是关着的），这里只留一个入口。
          IconButton(
            key: const ValueKey('vocab-filter-open'),
            tooltip: '筛选',
            icon: const Icon(Icons.tune),
            onPressed: () => showVocabFilters(context, vm: vm),
          ),
          PopupMenuButton<BrowseSort>(
            tooltip: '排序',
            icon: const Icon(Icons.sort),
            initialValue: vm.sort,
            onSelected: vm.setSort,
            itemBuilder: (_) => [
              for (final s in BrowseSort.values)
                PopupMenuItem<BrowseSort>(
                  value: s,
                  child: Text(browseSortLabel[s]!),
                ),
            ],
          ),
          // 一键处理：五步都在本机跑（ECDICT + Tatoeba）。
          IconButton(
            key: const ValueKey('vocab-dict-tools'),
            tooltip: '一键处理',
            icon: const Icon(Icons.bolt_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const DictToolsSheet(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            _SearchBar(vm: vm),
            _FilterBar(vm: vm),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? const _Empty()
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _ItemTile(
                        item: items[i],
                        onSpeak: speech == null
                            ? null
                            : () => speech.speak(items[i].word),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索框（唯一常驻的控件 —— 打字比点条件频繁得多）。
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.vm});

  final VocabBrowseViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18),
          hintText: '搜单词 / 释义 / 笔记',
          border: OutlineInputBorder(),
        ),
        onChanged: vm.setQuery,
      ),
    );
  }
}

/// 一行「筛选：…」——点它打开面板。条件全在面板里，这儿只做摘要和入口。
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.vm});

  final VocabBrowseViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => showVocabFilters(context, vm: vm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
        child: Row(
          children: [
            Icon(
              Icons.filter_list,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '筛选：${vocabFilterSummary(vm)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '共 ${vm.scopeCount} 条，筛出 ${vm.items.length} 条',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, this.onSpeak});

  final VocabItem item;

  /// 点词 / 点喇叭读一遍；没接上朗读时为 null（列表仍然可浏览）。
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gloss = displayMeaning(
      partOfSpeech: item.partOfSpeech,
      meaning: item.meaning,
    );
    final sub = <String>[
      if (gloss.isNotEmpty) gloss,
      if (item.status == VocabStatus.mastered) '已掌握',
      if (item.reviewState.due != null)
        '下次 ${item.reviewState.due!.split('T').first}',
      if (item.reviewState.lapses > 0) '忘过 ${item.reviewState.lapses}',
    ];
    return ListTile(
      dense: true,
      onTap: onSpeak,
      title: Text(item.word),
      subtitle: Text(
        sub.isEmpty ? '（还没释义）' : sub.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.phonetic != null)
            Text(item.phonetic!, style: theme.textTheme.bodySmall),
          if (onSpeak != null)
            IconButton(
              onPressed: onSpeak,
              icon: const Icon(Icons.volume_up_outlined),
              tooltip: '读一遍',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '这个筛选下没有词。换个范围或清掉日期试试。',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
