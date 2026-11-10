/// 精读入口：文章列表 + 粘贴新建。
///
/// 只做两件事：把 [ReaderViewModel] 的状态摆出来、把用户动作转成 ViewModel 调用。
/// 列表项、空态、错误提示都在这里；正文渲染在 `reader_page.dart`。
library;

import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

import '../data/repositories/article_repository.dart';
import '../viewmodels/reader_view_model.dart';
import 'reader_page.dart';

/// 文章列表页。
class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  @override
  void initState() {
    super.initState();
    // 首屏拉列表；`mounted` 判断放在 ViewModel 里没必要，这里只防 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReaderViewModel>().loadArticles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReaderViewModel>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('精读')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPasteSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('粘贴新建'),
      ),
      body: Column(
        children: [
          if (vm.error != null) StatusBar.error(message: vm.error!),
          if (vm.busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: vm.articles.isEmpty
                ? _EmptyState(textTheme: theme.textTheme)
                : ListView.builder(
                    itemCount: vm.articles.length,
                    itemBuilder: (context, i) => _ArticleTile(
                      row: vm.articles[i],
                      onOpen: () => _open(context, vm.articles[i].id),
                      onRemove: () => vm.removeArticle(vm.articles[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, String id) async {
    final vm = context.read<ReaderViewModel>();
    await vm.openArticle(id);
    if (!context.mounted) return;
    if (vm.current == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReaderPage()),
    );
  }

  Future<void> _openPasteSheet(BuildContext context) async {
    final vm = context.read<ReaderViewModel>();
    final result = await showModalBottomSheet<({String title, String text})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PasteSheet(),
    );
    if (result == null) return;
    final created =
        await vm.createFromPaste(raw: result.text, title: result.title);
    if (created == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReaderPage()),
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
  });

  final ArticleRow row;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
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
