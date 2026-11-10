/// 词库浏览页：筛选（范围 / 类型 / 状态 / 入库日 / 搜索）→ 列表。
///
/// 筛选与计数全部走 `core/vocab_browse.dart`（有 17 例兜着），这里只画控件、
/// 把点击翻译成 ViewModel 的方法。排序在 ViewModel 里做（`BrowseSort`）。
library;

import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

import '../core/vocab/word.dart' show displayMeaning;
import '../core/vocab_browse.dart';
import '../models/vocab.dart';
import '../viewmodels/vocab_browse_view_model.dart';

/// 词库浏览页。
class VocabBrowsePage extends StatefulWidget {
  const VocabBrowsePage({super.key});

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
    return Scaffold(
      appBar: AppBar(
        title: Text('词库（${items.length}）'),
        actions: [
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
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            _Filters(vm: vm),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? const _Empty()
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _ItemTile(item: items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.vm});

  final VocabBrowseViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: '搜单词 / 释义 / 笔记',
              border: OutlineInputBorder(),
            ),
            onChanged: vm.setQuery,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in BrowseScope.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(browseScopeLabel[s]!),
                      selected: vm.scope == s,
                      onSelected: (_) => vm.setScope(s),
                    ),
                  ),
                const SizedBox(width: 8),
                for (final k in BrowseKind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(browseKindLabel[k]!),
                      selected: vm.kind == k,
                      onSelected: (_) => vm.setKind(k),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in BrowseStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(browseStatusLabel[s]!),
                      selected: vm.status == s,
                      onSelected: (_) => vm.setStatus(s),
                    ),
                  ),
                if (vm.status != BrowseStatus.mastered)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: FilterChip(
                      label: const Text('含已掌握'),
                      selected: vm.includeMastered,
                      onSelected: vm.setIncludeMastered,
                    ),
                  ),
              ],
            ),
          ),
          if (vm.scope == BrowseScope.picked && vm.articles.isNotEmpty) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final a in vm.articles)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('${a.title} ${vm.articleCounts[a.id] ?? 0}'),
                        selected: vm.pickedArticleIds.contains(a.id),
                        onSelected: (_) => vm.togglePicked(a.id),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (vm.dayOptions.isNotEmpty) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final d in vm.dayOptions.take(8))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('${d.day} ${d.count}'),
                        selected: vm.days.contains(d.day),
                        onSelected: (_) => vm.toggleDay(d.day),
                      ),
                    ),
                  if (vm.days.isNotEmpty)
                    TextButton(
                      onPressed: vm.clearDays,
                      child: const Text('清空日期'),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '共 ${vm.scopeCount} 条，筛出 ${vm.items.length} 条',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final VocabItem item;

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
      title: Text(item.word),
      subtitle: Text(
        sub.isEmpty ? '（还没释义）' : sub.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: item.phonetic == null
          ? null
          : Text(item.phonetic!, style: theme.textTheme.bodySmall),
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

