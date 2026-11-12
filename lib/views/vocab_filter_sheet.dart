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
import '../viewmodels/vocab_browse_view_model.dart';

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
      '本篇'
    else if (vm.scope == BrowseScope.picked)
      '选篇 ${vm.pickedArticleIds.length} 篇'
    else
      '全部',
    browseKindLabel[vm.kind]!,
    browseStatusLabel[vm.status]!,
  ];
  if (vm.days.length == 1) parts.add(vm.days.first);
  if (vm.days.length > 1) parts.add('${vm.days.length} 天');
  return parts.join(' · ');
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
                              vm.pickedArticleIds.isEmpty
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
        for (final id in vm.pickedArticleIds.toList()) {
          vm.togglePicked(id);
        }
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
              BrowseScope.article => '只看当前这一篇',
              BrowseScope.picked => '勾几篇一起看',
              BrowseScope.all => '整本词库',
            },
          ),
        // 选了「本篇」才给挑哪一篇；选了「选篇」才给勾篇。
        if (vm.scope == BrowseScope.article && articles.isNotEmpty)
          _ArticlePicker(
            key: const ValueKey('filter-article'),
            articles: articles,
            activeId: vm.currentArticleId,
            isChecked: (id) => vm.currentArticleId == id,
            onTap: vm.setCurrentArticle,
          ),
        if (vm.scope == BrowseScope.picked)
          if (articles.isEmpty)
            const _Hint('还没有保存过文章。')
          else
            for (final a in articles)
              CheckboxListTile(
                key: ValueKey('filter-picked-${a.id}'),
                dense: true,
                value: vm.pickedArticleIds.contains(a.id),
                onChanged: (_) => vm.togglePicked(a.id),
                title: Text(
                  '${a.title} ${vm.articleCounts[a.id] ?? 0}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

/// 「本篇」指向哪一篇：也是一行一行的单选。
class _ArticlePicker extends StatelessWidget {
  const _ArticlePicker({
    super.key,
    required this.articles,
    required this.activeId,
    required this.isChecked,
    required this.onTap,
  });

  final List<BrowseArticleRef> articles;
  final String? activeId;
  final bool Function(String id) isChecked;
  final void Function(String id) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '哪一篇',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final a in articles)
            ListTile(
              key: ValueKey('filter-current-${a.id}'),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 4),
              onTap: () => onTap(a.id),
              leading: Icon(
                isChecked(a.id)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
              ),
              title: Text(
                a.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
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
