/// 精读入口：当前文章标题 + 可展开的搜索栏 + 文章列表 + 粘贴新建。
///
/// 只做两件事：把 ViewModel 的状态摆出来、把用户动作转成 ViewModel 调用。
///
/// 为什么这里要读 [CurrentArticleViewModel]（用户 2026-11-12 的要求）：
/// 「哪一篇是当前文章」原来只是精读页自己的临时状态，别的模块拿不到。
/// 现在它是一份全局状态，这一页既是它的**唯一写入方**（选文章 / 新建 / 删篇回落），
/// 也是它的显示方：标题栏写着「精读 · 当前那篇」，用户一眼知道别的模块会跟哪篇走。
library;

import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

import '../data/repositories/article_repository.dart';
import '../viewmodels/current_article_view_model.dart';
import '../viewmodels/reader_view_model.dart';
import 'article_picker.dart'
    show ArticleSearchField, articleSearchMatches, pickArticle;
import 'reader_page.dart';

/// 文章列表页。
class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  final TextEditingController _query = TextEditingController();

  /// 搜索栏默认收着（用户要求「点开默认关闭的下拉列表」）。
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // 首屏拉列表；`mounted` 判断放在 ViewModel 里没必要，这里只防 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReaderViewModel>().loadArticles();
      context.read<CurrentArticleViewModel>().bootstrap();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReaderViewModel>();
    final cur = context.watch<CurrentArticleViewModel>();
    final theme = Theme.of(context);
    final rows = articleSearchMatches(vm.articles, _query.text);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('精读'),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // 「精读 · 当前那篇」—— 这一篇决定别的模块用哪篇文章的数据。
                '· ${cur.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('articles-search-toggle'),
            tooltip: _searching ? '收起搜索' : '搜文章标题',
            isSelected: _searching,
            icon: Icon(_searching ? Icons.search_off : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query.clear();
            }),
          ),
          IconButton(
            key: const ValueKey('articles-pick'),
            tooltip: '选文章',
            icon: const Icon(Icons.expand_more),
            onPressed: vm.articles.isEmpty ? null : () => _pick(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPasteSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('粘贴新建'),
      ),
      body: Column(
        children: [
          if (vm.error != null) StatusBar.error(message: vm.error!),
          if (cur.error != null) StatusBar.error(message: cur.error!),
          if (vm.busy || cur.busy) const LinearProgressIndicator(minHeight: 2),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ArticleSearchField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
          Expanded(
            child: vm.articles.isEmpty
                ? _EmptyState(textTheme: theme.textTheme)
                : rows.isEmpty
                    ? _NoMatch(query: _query.text.trim())
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) => _ArticleTile(
                          row: rows[i],
                          current: rows[i].id == cur.articleId,
                          onOpen: () => _open(context, rows[i].id),
                          onRemove: () => _remove(context, rows[i].id),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// 选一篇：先写全局（别的模块立刻跟着换），再开阅读页。
  Future<void> _open(BuildContext context, String id) async {
    await _select(context, id);
  }

  Future<void> _select(BuildContext context, String id) async {
    final cur = context.read<CurrentArticleViewModel>();
    final vm = context.read<ReaderViewModel>();
    await cur.select(id);
    await vm.openArticle(id);
    if (!context.mounted) return;
    if (vm.current == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReaderPage()),
    );
    // 从阅读页回来：列表可能变了（新建 / 改名），刷新一遍。
    if (!context.mounted) return;
    await cur.refresh();
    await vm.loadArticles();
  }

  Future<void> _pick(BuildContext context) async {
    final cur = context.read<CurrentArticleViewModel>();
    final vm = context.read<ReaderViewModel>();
    final id = await pickArticle(
      context,
      articles: vm.articles,
      currentId: cur.articleId,
    );
    if (id == null || !context.mounted) return;
    if (id == cur.articleId) {
      // 已经是当前那篇：直接进阅读页，不重复写盘。
      await vm.openArticle(id);
      if (!context.mounted || vm.current == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ReaderPage()),
      );
      return;
    }
    await _select(context, id);
  }

  Future<void> _remove(BuildContext context, String id) async {
    final vm = context.read<ReaderViewModel>();
    final cur = context.read<CurrentArticleViewModel>();
    await vm.removeArticle(id);
    // 删掉的正好是当前那篇：全局回落成「没选」，不自动换第一篇。
    await cur.refresh();
  }

  Future<void> _openPasteSheet(BuildContext context) async {
    final vm = context.read<ReaderViewModel>();
    final cur = context.read<CurrentArticleViewModel>();
    final result = await showModalBottomSheet<({String title, String text})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PasteSheet(),
    );
    if (result == null || !context.mounted) return;
    final created =
        await vm.createFromPaste(raw: result.text, title: result.title);
    if (created == null || !context.mounted) return;
    // 新建的那篇直接成为全局当前文章 —— 用户刚贴完就是要读它。
    await cur.refresh();
    await cur.select(created.id);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReaderPage()),
    );
    if (!context.mounted) return;
    await cur.refresh();
    await vm.loadArticles();
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          '没有标题匹配「$query」。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('还没有文章', style: textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '点右下角「粘贴新建」，把一段英文贴进来就能开始精读。',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleTile extends StatelessWidget {
  const _ArticleTile({
    required this.row,
    required this.onOpen,
    required this.onRemove,
    this.current = false,
  });

  final ArticleRow row;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  /// 是不是全局「当前文章」—— 打勾，让用户知道别的模块会跟哪篇走。
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: current,
      leading: current
          ? Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary)
          : null,
      title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _subtitleOf(row),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onOpen,
      onLongPress: () => _confirmRemove(context),
    );
  }

  String _subtitleOf(ArticleRow row) {
    final parts = <String>[];
    if (row.book != null && row.book!.isNotEmpty) parts.add(row.book!);
    parts.add('${row.sentenceCount} 句');
    parts.add('${row.wordCount} 个生词');
    return parts.join(' · ');
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删掉这篇文章？'),
        content: Text('「${row.title}」会被删除，词库里已收的生词不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) onRemove();
  }
}

/// 粘贴新建：标题可选，正文必填。
class _PasteSheet extends StatefulWidget {
  const _PasteSheet();

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('粘贴新建', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '标题（可空，空则「未命名」）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '英文正文',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final text = _text.text;
              if (text.trim().isEmpty) return;
              Navigator.of(context).pop((title: _title.text, text: text));
            },
            child: const Text('新建并开始读'),
          ),
        ],
      ),
    );
  }
}
