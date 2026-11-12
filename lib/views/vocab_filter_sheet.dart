/// 词库的筛选面板：**平时收着**，点 AppBar 的漏斗才滑出来。
///
/// 为什么不把条件平铺在列表上方：四组条件（来源 / 类型 / 状态 / 日期）
/// 加上每篇的勾选，一行 chip 根本放不下，横向滚动又是「看不见就等于没有」。
/// 面板里从上到下分块摆，一屏看不完还能滚。
///
/// 条件本身全在 `VocabBrowseViewModel` 里（并落 `shared_preferences`），
/// 这里只画控件、把点击翻译成 setter —— 别在这儿再存一份状态。
library;

import 'package:flutter/material.dart';

import '../core/vocab_browse.dart';
import '../core/vocab_browse_prefs.dart';
import '../data/repositories/article_repository.dart' show ArticleRow;
import '../viewmodels/vocab_browse_view_model.dart';
import 'article_picker.dart' show pickArticle;

/// 打开筛选面板。
Future<void> showVocabFilters(
  BuildContext context, {
  required VocabBrowseViewModel vm,
}) {
  final active = vocabFilterSummary(vm);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(vm: vm, summary: active),
  );
}

/// 当前条件的短标签，给面板标题和页面上的入口用。
///
/// 例：「本篇 · 单词 · 复习」「全部 · 语言点 · 全部 · 2026-11-01」。
String vocabFilterSummary(VocabBrowseViewModel vm) {
  final parts = <String>[
    if (vm.scope == BrowseScope.article)
      // 本篇就是全局当前文章，标题直接带上，省得用户去猜「哪一篇」。
      '本篇${vm.currentArticleTitle == null ? '' : '·${vm.currentArticleTitle}'}'
    else if (vm.scope == BrowseScope.picked)
      '选篇${_pickedTitle(vm) == null ? '' : '·${_pickedTitle(vm)}'}'
    else
      '全部',
    browseKindLabel[vm.kind]!,
    browseStatusLabel[vm.status]!,
  ];
  if (vm.days.length == 1) parts.add(vm.days.first);
  if (vm.days.length > 1) parts.add('${vm.days.length} 天');
  return parts.join(' · ');
}

/// 「选篇」选的那篇的标题（没选 / 已删返回 null）。
String? _pickedTitle(VocabBrowseViewModel vm) {
  final id = vm.pickedArticleId;
  if (id == null) return null;
  for (final a in vm.articles) {
    if (a.id == id) return a.title;
  }
  return null;
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.vm, required this.summary});

  final VocabBrowseViewModel vm;
  final String summary;

  @override
  Widget build(BuildContext context) {
    // 面板开着的时候点条件要立刻重画，所以要听 vm（页面那边的 watch 管不到这里）。
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final theme = Theme.of(context);
        final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('筛选', style: theme.textTheme.titleMedium),
                          Text(
                            '当前：$summary',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: vm.scope == BrowseScope.all &&
                              vm.kind == BrowseKind.all &&
                              vm.status == BrowseStatus.all &&
                              vm.days.isEmpty &&
                              !vm.includeMastered &&
                              vm.pickedArticleId == null
                          ? null
                          : _resetAll(vm),
                      child: const Text('重置'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  children: [
                    _sourceSection(context),
                    _kindSection(context),
                    _statusSection(context),
                    _daySection(context),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '共 ${vm.scopeCount} 条，筛出 ${vm.items.length} 条',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 「重置」：四组条件回默认（本篇 / 单词 / 复习 / 不限日期）。
  VoidCallback _resetAll(VocabBrowseViewModel vm) => () {
        const fresh = VocabBrowsePrefs();
        vm.setScope(fresh.scope);
        vm.setKind(fresh.kind);
        vm.setStatus(fresh.status);
        vm.setIncludeMastered(fresh.includeMastered);
        vm.setDays(const <String>{});
        vm.setPickedArticle(null);
      };

  Widget _sourceSection(BuildContext context) {
    final articles = vm.articles;
    return _Section(
      title: '来源',
      children: [
        for (final s in const [
          BrowseScope.article,
          BrowseScope.picked,
          BrowseScope.all,
        ])
          _ChoiceTile(
            key: ValueKey('filter-scope-${s.name}'),
            label: browseScopeLabel[s]!,
            selected: vm.scope == s,
            onTap: () => vm.setScope(s),
            note: switch (s) {
              // 本篇不再给「哪一篇」选择器：它就是精读页选的那一篇。
              BrowseScope.article => vm.currentArticleTitle == null
                  ? '精读页还没选文章'
                  : '当前：${vm.currentArticleTitle}',
              BrowseScope.picked => '临时挑另一篇看',
              BrowseScope.all => '整本词库',
            },
          ),
        // 只有「选篇」才给挑篇（本篇跟随全局，全部不需要）。
        if (vm.scope == BrowseScope.picked)
          if (articles.isEmpty)
            const _Hint('还没有保存过文章。')
          else
            _PickedPicker(
              key: const ValueKey('filter-picked'),
              articles: articles,
              activeId: vm.pickedArticleId,
              onTap: vm.setPickedArticle,
            ),
      ],
    );
  }

  Widget _kindSection(BuildContext context) => _Section(
        title: '类型',
        children: [
          for (final k in const [BrowseKind.word, BrowseKind.lang, BrowseKind.all])
            _ChoiceTile(
              key: ValueKey('filter-kind-${k.name}'),
              label: browseKindLabel[k]!,
              selected: vm.kind == k,
              onTap: () => vm.setKind(k),
            ),
        ],
      );

  Widget _statusSection(BuildContext context) => _Section(
        title: '学习状态',
        children: [
          for (final s in const [
            BrowseStatus.due,
            BrowseStatus.fresh,
            BrowseStatus.lapsed,
            BrowseStatus.mastered,
            BrowseStatus.all,
          ])
            _ChoiceTile(
              key: ValueKey('filter-status-${s.name}'),
              label: browseStatusLabel[s]!,
              selected: vm.status == s,
              onTap: () => vm.setStatus(s),
            ),
          SwitchListTile(
            key: const ValueKey('filter-include-mastered'),
            dense: true,
            value: vm.includeMastered,
            onChanged: vm.setIncludeMastered,
            title: const Text('含已掌握'),
            subtitle: const Text('关掉时，别的状态里不会混进已掌握的词'),
          ),
        ],
      );

  /// 按日期：一个**可搜索的下拉**，不是一排 chip。
  Widget _daySection(BuildContext context) {
    final options = vm.dayOptions;
    final selected = vm.days.length == 1 ? vm.days.first : null;
    final has = options.any((d) => d.day == selected);
    return _Section(
      title: '按日期（入库日）',
      children: [
        if (options.isEmpty)
          const _Hint('这批词还没有入库日期。')
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: DropdownMenu<String?>(
              key: const ValueKey('filter-day-menu'),
              initialSelection: has ? selected : null,
              requestFocusOnTap: true,
              enableFilter: true,
              expandedInsets: EdgeInsets.zero,
              label: const Text('入库日'),
              hintText: '全部日期',
              helperText: '输入日期就能搜，例如 2026-11',
              menuHeight: 320,
              onSelected: (day) => vm.setDays(
                day == null ? const <String>{} : <String>{day},
              ),
              dropdownMenuEntries: <DropdownMenuEntry<String?>>[
                const DropdownMenuEntry<String?>(
                  value: null,
                  label: '全部日期',
                ),
                for (final d in options)
                  DropdownMenuEntry<String?>(
                    value: d.day,
                    label: '${d.day} · ${d.count} 条',
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ...children,
        const Divider(height: 16),
      ],
    );
  }
}

/// 一行可选条件：**不用 chip / button**，用带勾的列表行。
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.note,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 20,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        label,
        style: selected
            ? TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      subtitle: note == null ? null : Text(note!),
    );
  }
}

/// 「选篇」挑一篇：**可搜索的下拉列表**，不是一排勾选框。
///
/// 用户（2026-11-12）要求「勾选几篇一起看」砍掉 —— 词库一次只看一篇，
/// 想换就换，不需要多篇并集。
class _PickedPicker extends StatelessWidget {
  const _PickedPicker({
    super.key,
    required this.articles,
    required this.activeId,
    required this.onTap,
  });

  final List<BrowseArticleRef> articles;
  final String? activeId;
  final void Function(String? id) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = articles.where((a) => a.id == activeId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(52, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('filter-picked-open'),
            onTap: () async {
              final picked = await _pick(context);
              if (picked != null) onTap(picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                isDense: true,
                labelText: '看哪一篇',
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.arrow_drop_down),
                helperText: active == null ? '还没选' : null,
              ),
              child: Text(
                active?.title ?? '点这里挑一篇',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (active != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onTap(null),
                child: const Text('不选了'),
              ),
            ),
          Text(
            '共 ${articles.length} 篇，点开可以搜标题',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pick(BuildContext context) async {
    final rows = [
      for (final a in articles)
        ArticleRow(
          id: a.id,
          title: a.title,
          book: '',
          updatedAt: '',
          createdAt: '',
          sentenceCount: 0,
          wordCount: 0,
        ),
    ];
    return pickArticle(
      context,
      articles: rows,
      currentId: activeId,
      title: '选一篇看词',
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
