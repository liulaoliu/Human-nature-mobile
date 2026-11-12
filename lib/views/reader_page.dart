/// 阅读页：逐句正文 + 选词模式 + 本篇词表。
///
/// 交互按 `docs/ARCHITECTURE.md` 的「Web 语义 → Flutter」对照表：
/// Web 的鼠标划词 → 手机上的「选词模式 + 点词」（`PickModeViewModel`，与速读共用）；
/// 不选词时点句子 → 仍打开老的单句取词面板（见 `reader_sentence_sheet.dart`）；
/// 悬浮详情（Web 的 hover）→ 长按列表项。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../core/article_vocab.dart' show ArticleEntryView;
import '../core/language.dart' show buildLanguagePrompt;
import '../core/production.dart' show productionDocLemmas;
import '../core/vocab_stats.dart' show PickSession;
import '../core/learning.dart' show LearningSection;
import '../data/repositories/learning_repository.dart'
    show LearningRepository;
import '../models/document.dart' show SavedArticle;
import '../models/vocab.dart' show VocabItem;
import '../viewmodels/pick_mode_view_model.dart';
import '../viewmodels/reader_view_model.dart';
import '../viewmodels/study_view_model.dart' show StudyViewModel;
import 'ai_paste_sheet.dart';
import 'reader_body.dart';
import 'reader_sentence_sheet.dart' show showSentenceSheet;

/// 阅读页。
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  /// 译文默认开：Web 版默认关，但用户明确抱怨过「翻译不显示」。
  bool _showTranslation = true;

  /// 语言点默认开，同上。
  bool _showLanguage = true;

  /// 词表侧栏要从 AppBar 按钮打开，得拿得到 Scaffold 状态。
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 上一次同步给背单词的文章 id。
  ///
  /// 记下来是因为 `build` 会反复跑，而 `setArticleContext` 会 `notifyListeners`：
  /// 不判重的话每次重画都通知一遍，背单词页跟着重算候选池。
  String? _syncedArticleId;

  /// 上一次同步给选词模式的文章 id（换文章要清空选中）。
  String? _pickedArticleId;

  /// 把「当前读的是哪一篇」告诉背单词。
  ///
  /// 没有这一步，「本篇」范围永远拿不到 articleId，候选池恒为空 —— 用户选「本篇」
  /// 只能看到「候选 0 个」。正文词集合用 `productionDocLemmas`（正文词 + 语言点词），
  /// 这样以前在别处标过、但词形确实出现在本文里的词也算本篇生词。
  void _syncStudyArticle(SavedArticle article) {
    if (_syncedArticleId == article.id) return;
    _syncedArticleId = article.id;
    final study = context.read<StudyViewModel?>();
    study?.setArticleContext(
      article.id,
      docLemmas: productionDocLemmas(article.sentences),
    );
  }

  /// 换文章时清掉上一轮的选中（不然会把上一篇的词加到这一篇上）。
  void _syncPickArticle(SavedArticle article) {
    if (_pickedArticleId == article.id) return;
    _pickedArticleId = article.id;
    context.read<PickModeViewModel?>()?.clear();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReaderViewModel>();
    final pick = context.watch<PickModeViewModel?>();
    final article = vm.current;
    if (article == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('没有打开的文章')),
      );
    }
    // 渲染期只读，写状态放到帧后（否则 build 里 notifyListeners 会报错）。
    final needsSync = _syncedArticleId != article.id;
    final needsPickSync = _pickedArticleId != article.id;
    if (needsSync || needsPickSync) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncStudyArticle(article);
        _syncPickArticle(article);
      });
    }
    final picking = pick != null && pick.enabled;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(article.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (pick != null)
            IconButton(
              tooltip: picking ? '关闭选词模式' : '选词模式',
              isSelected: picking,
              icon: Icon(
                picking ? Icons.pan_tool : Icons.pan_tool_outlined,
              ),
              onPressed: () {
                pick.toggleEnabled();
                // 关掉时把这一轮记进「选词会话」统计（Web 口径）。
                if (!pick.enabled) _flushPickSession(pick);
              },
            ),
          IconButton(
            tooltip: _showTranslation ? '隐藏译文' : '显示译文',
            icon: Icon(
              _showTranslation ? Icons.subtitles : Icons.subtitles_off,
            ),
            onPressed: () =>
                setState(() => _showTranslation = !_showTranslation),
          ),
          IconButton(
            tooltip: _showLanguage ? '隐藏语言点' : '显示语言点',
            icon: Icon(
              _showLanguage ? Icons.notes : Icons.notes_outlined,
            ),
            onPressed: () => setState(() => _showLanguage = !_showLanguage),
          ),
          IconButton(
            tooltip: '语言点（整篇）',
            icon: const Icon(Icons.translate),
            onPressed: () => _openLanguageSheet(context, vm, article),
          ),
          IconButton(
            tooltip: '本篇词表',
            icon: Badge(
              label: Text('${vm.currentEntries.length}'),
              isLabelVisible: vm.currentEntries.isNotEmpty,
              child: const Icon(Icons.list_alt),
            ),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      // 词表放右侧抽屉：从右边缘往左滑也能拉出来（`endDrawerEnableOpenDragGesture`）。
      endDrawer: const _VocabDrawer(),
      endDrawerEnableOpenDragGesture: true,
      body: Column(
        children: [
          if (vm.error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                vm.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          Expanded(
            child: ReaderBody(
              article: article,
              selected: vm.selectedSentenceId,
              showTranslation: _showTranslation,
              showLanguage: _showLanguage,
              pick: pick,
              pickedLemmas: {
                for (final v in vm.currentEntries) v.item.lemma,
              },
              onTapSentence: (s) => showSentenceSheet(
                context,
                sentence: s,
                articleId: article.id,
                fileName: article.book,
              ),
              onTapWord: (s, index, word) {
                final handled = pick?.toggle(s.id, index, word) ?? false;
                if (!handled) {
                  // 选词模式其实关着（理论上进不来），退回老面板。
                  showSentenceSheet(
                    context,
                    sentence: s,
                    articleId: article.id,
                    fileName: article.book,
                  );
                }
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: picking
          ? PickBar(
              pick: pick,
              busy: vm.busy,
              articleEntries: vm.currentEntries,
              onCommit: (words) => _commitPicks(vm, article, words),
            )
          : _BottomBar(vm: vm),
    );
  }

  /// 选中的词（含合成词组）一次性加进本篇。
  Future<void> _commitPicks(
    ReaderViewModel vm,
    SavedArticle article,
    List<String> words,
  ) async {
    var added = 0;
    for (final word in words) {
      final saved = await vm.markCurrentWord(
        word,
        sentenceText: null,
        kind: null,
      );
      if (saved != null) added++;
    }
    if (!mounted) return;
    context.read<PickModeViewModel?>()?.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added == 0 ? '没加进去（可能已收过）' : '已收录 $added 个')),
    );
  }

  /// 把这一轮选词记进「选词会话」（`learning.sessions`）。
  ///
  /// 失败不弹错：这是个统计，丢一条不值得打断阅读。
  void _flushPickSession(PickModeViewModel pick) {
    final session = pick.takeSession();
    if (session == null) return;
    final learning = context.read<LearningRepository?>();
    if (learning == null) return;
    unawaited(_writePickSession(learning, session));
  }

  Future<void> _writePickSession(
    LearningRepository learning,
    PickSession session,
  ) async {
    try {
      final data = await learning.load();
      final next = [...data.sessions, session];
      // 上限 500 条，与 Web 一致：只留最近的。
      data.sessions = next.length > 500
          ? next.sublist(next.length - 500)
          : next;
      await learning.writeSection(data, LearningSection.sessions);
    } catch (_) {
      // 统计写不进去不影响阅读。
    }
  }

  /// 整篇语言点：拼提示词 → 粘回 JSON → `parseLanguage` / `applyLanguage` 落盘。
  Future<void> _openLanguageSheet(
    BuildContext context,
    ReaderViewModel vm,
    SavedArticle article,
  ) async {
    // 一次最多带 40 句，太长 AI 会偷懒只答前几句。
    final batch = article.sentences.take(40).toList();
    if (batch.isEmpty) return;
    final prompt = buildLanguagePrompt([
      for (final s in batch) (id: s.id, text: s.text),
    ]);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiPasteSheet(
        title: '语言点分析（${batch.length} 句）',
        prompt: prompt,
        hint: '粘回 AI 给的 JSON，句 id 要对得上',
        onApply: (raw) async {
          final n = await vm.applyLanguageText(raw);
          if (n == 0) return vm.error ?? '没落到句子上';
          if (!context.mounted) return null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已写入 $n 句的语言点')),
          );
          return null;
        },
      ),
    );
  }
}

/// 底部条：本篇词数 + 打开词表。
///
/// 用户明确说过不要「点任意一句取词 · 本篇已收 N 个」那句提示：
/// 现在取词靠选词模式（点词选中），这句话既过时又占地方。
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.vm});

  final ReaderViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = vm.currentEntries.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.list_alt,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '本篇已收 $n 个',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (vm.busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

/// 本篇词表（右侧抽屉）。
///
/// 从右边缘滑入，也可以用 AppBar 的按钮打开；每个词右边有复制按钮
/// （复制单词本身，方便拿去别处查）。
///
/// 复制成功用「图标变成对勾」反馈，不用 SnackBar —— 抽屉盖住了页面底部，
/// SnackBar 会弹在抽屉下面，用户根本看不见。
class _VocabDrawer extends StatefulWidget {
  const _VocabDrawer();

  @override
  State<_VocabDrawer> createState() => _VocabDrawerState();
}

class _VocabDrawerState extends State<_VocabDrawer> {
  /// 刚复制过的那条（显示 1.2 秒对勾）。
  String? _copied;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(VocabItem item) async {
    await Clipboard.setData(ClipboardData(text: item.word));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copied = item.id);
    _copiedTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReaderViewModel>();
    final entries = vm.currentEntries;
    final theme = Theme.of(context);
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.86,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('本篇词表（${entries.length}）',
                        style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '还没收词。开「选词模式」，点正文里的词就能收进来。',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final view = entries[i];
                        final copied = _copied == view.item.id;
                        return ListTile(
                          dense: true,
                          title: Text(view.item.word),
                          subtitle: Text(_lineOf(view)),
                          trailing: IconButton(
                            tooltip: copied ? '已复制' : '复制单词',
                            icon: Icon(
                              copied ? Icons.check : Icons.copy,
                              size: 18,
                              color: copied ? theme.colorScheme.primary : null,
                            ),
                            onPressed: () => _copy(view.item),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _lineOf(ArticleEntryView view) {
    final meaning = view.item.meaning;
    final pos = view.item.partOfSpeech;
    if (meaning == null || meaning.isEmpty) {
      return view.entry.sentenceText ?? '';
    }
    return pos == null || pos.isEmpty ? meaning : '$pos. $meaning';
  }
}
