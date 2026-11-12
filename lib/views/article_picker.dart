/// 可搜索的文章选择器：搜索栏 + 正常滚动列表。
///
/// 为什么不用 `DropdownMenu(enableFilter: true)`：它是输入框形态，菜单高度受
/// `menuHeight` 限制，文章一多就只能在小窗口里滚；而这里要的是「搜索框固定在顶上、
/// 下面一个能正常滚的列表」。用户（2026-11-12）也明确说：Flutter 没有现成的
/// 「搜索 + 下拉」就拆成「搜索栏 + 滚动列表」，并希望这个组件以后能复用
/// （他在 patrol_helper 里用过类似的东西，效果好）。
///
/// 复用方式：
///   - [articleSearchMatches] 是纯函数（标题模糊匹配），可以单独测；
///   - [pickArticle] 弹出选择面板，返回选中的 id（取消返回 null）；
///   - [ArticleSearchField] 只管输入框本身，列表由调用方摆。
library;

import 'package:flutter/material.dart';

import '../data/repositories/article_repository.dart';

/// 按标题模糊匹配文章。
///
/// 规则刻意简单（用户要的是「输入文字，列表显示匹配到的标题」）：
///   - 关键词为空 / 全空白 → 原样返回全部（默认展示所有文章标题）；
///   - 大小写不敏感；
///   - 空格分隔的多个关键词要**全部命中**（`the growth` 能匹配「The Growth Story」）；
///   - 顺带匹配 `book`（书名），因为列表副标题里有它，用户会照着副标题去搜。
List<ArticleRow> articleSearchMatches(List<ArticleRow> rows, String query) {
  final keys = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((k) => k.isNotEmpty)
      .toList(growable: false);
  if (keys.isEmpty) return List<ArticleRow>.of(rows);
  bool hit(ArticleRow row) {
    final hay = '${row.title}\n${row.book ?? ''}'.toLowerCase();
    for (final key in keys) {
      if (!hay.contains(key)) return false;
    }
    return true;
  }

  return [
    for (final row in rows)
      if (hit(row)) row,
  ];
}

/// 弹一个可搜索的文章选择面板；选中返回 id，取消返回 null。
///
/// [currentId] 会高亮成「当前」，方便用户确认自己现在读的是哪篇。
Future<String?> pickArticle(
  BuildContext context, {
  required List<ArticleRow> articles,
  String? currentId,
  String title = '换一篇文章',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ArticlePickerSheet(
      articles: articles,
      currentId: currentId,
      title: title,
    ),
  );
}

/// 选择面板本体（也单独暴露，方便直接塞进别处）。
class ArticlePickerSheet extends StatefulWidget {
  const ArticlePickerSheet({
    super.key,
    required this.articles,
    this.currentId,
    this.title = '换一篇文章',
    this.emptyHint = '还没有文章。点右下角「粘贴新建」，把一段英文贴进来就能开始精读。',
  });

  final List<ArticleRow> articles;
  final String? currentId;
  final String title;
  final String emptyHint;

  @override
  State<ArticlePickerSheet> createState() => _ArticlePickerSheetState();
}

class _ArticlePickerSheetState extends State<ArticlePickerSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matched = articleSearchMatches(widget.articles, _query.text);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleMedium),
                ),
                Text(
                  '共 ${widget.articles.length} 篇',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ArticleSearchField(
              controller: _query,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: matched.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.articles.isEmpty
                          ? widget.emptyHint
                          : '没有标题匹配「${_query.text.trim()}」。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: matched.length,
                    itemBuilder: (context, i) {
                      final row = matched[i];
                      final current = row.id == widget.currentId;
                      return ListTile(
                        key: ValueKey('pick-article-${row.id}'),
                        dense: true,
                        selected: current,
                        leading: Icon(
                          current
                              ? Icons.radio_button_checked
                              : Icons.article_outlined,
                          size: 20,
                        ),
                        title: Text(
                          row.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _subtitleOf(row),
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: current
                            ? const Text('当前')
                            : const Icon(Icons.chevron_right, size: 18),
                        onTap: () => Navigator.of(context).pop(row.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _subtitleOf(ArticleRow row) {
    final parts = <String>[];
    if (row.book != null && row.book!.isNotEmpty) parts.add(row.book!);
    parts.add('${row.sentenceCount} 句');
    parts.add('${row.wordCount} 个生词');
    return parts.join(' · ');
  }
}

/// 搜索输入框（固定样式，列表由调用方摆）。
class ArticleSearchField extends StatelessWidget {
  const ArticleSearchField({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = '搜文章标题',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        hintText: hintText,
        border: const OutlineInputBorder(),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
              ),
      ),
    );
  }
}
