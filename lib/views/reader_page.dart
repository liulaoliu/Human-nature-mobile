/// 阅读页：逐句正文 + 选词模式 + 本篇词表。
///
/// 交互按 `docs/ARCHITECTURE.md` 的「Web 语义 → Flutter」对照表：
/// Web 的鼠标划词 → 手机上的「选词模式 + 点词」（`PickModeViewModel`，与速读共用）；
/// 不选词时点句子 → 朗读这一句、长按复制整句（见 `sentence_tap.dart`，
/// 用户 2026-11-15 明确要求替代老的取词面板）；
/// 悬浮详情（Web 的 hover）→ 长按列表项。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../core/article_vocab.dart' show ArticleEntryView;
import '../core/language.dart' show buildLanguagePrompt;
import '../core/tts_audio_cache.dart' show estimateTtsAudioBytes, formatTtsAudioBytes;
import '../core/tts_provider.dart' show TtsProvider, ttsVoiceLabel;
import '../core/vocab_stats.dart' show PickSession;
import '../core/word_pick.dart' show PickEntry;
import '../core/learning.dart' show LearningSection;
import '../data/repositories/learning_repository.dart'
    show LearningRepository;
import '../models/document.dart' show SavedArticle, Sentence;
import '../models/vocab.dart' show VocabItem;
import '../viewmodels/offline_audio_view_model.dart';
import '../viewmodels/pick_mode_view_model.dart';
import '../viewmodels/reader_view_model.dart';
import '../viewmodels/tts_view_model.dart';
import 'ai_batch_bar.dart' show AiBatchBar;
import 'ai_paste_sheet.dart';
import 'auto_vocab_sheet.dart' show runAutoVocab;
import 'reader_body.dart';

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

  /// 上一次同步给选词模式的文章 id（换文章要清空选中）。
  String? _pickedArticleId;

  /// AI-Batch Work 横条是否显示（默认不显示，不占阅读空间）。
  bool _showBatch = false;

  /// 换文章时清掉上一轮的选中（不然会把上一篇的词加到这一篇上）。
  ///
  /// 背单词/产出训练/仿写的「本篇」不在这里推 —— 那件事归 `ArticleContextSync`
  /// （挂在 App 根上，跟当前在哪个页面无关），否则不打开精读页就没有本篇。
  void _syncPickArticle(SavedArticle article) {
    if (_pickedArticleId == article.id) return;
    _pickedArticleId = article.id;
    context.read<PickModeViewModel?>()?.clear();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReaderViewModel>();
    final pick = context.watch<PickModeViewModel?>();
    final offline = context.watch<OfflineAudioViewModel?>();
    final article = vm.current;
    if (article == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('没有打开的文章')),
      );
    }
    // 渲染期只读，写状态放到帧后（否则 build 里 notifyListeners 会报错）。
    if (_pickedArticleId != article.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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
          // 顶栏只留「选词模式 + 更多」两个按钮。
          //
          // 用户 2026-11-15 反馈：原来 7 个图标一长排，右边挤到返回键，
          // 手一抖就退出去了。冷门的（整篇语言点、AI 跑批、词表）收进菜单。
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _onMenu(context, vm, article, pick, value),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'translation',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _showTranslation ? Icons.subtitles : Icons.subtitles_off,
                  ),
                  title: Text(_showTranslation ? '隐藏译文' : '显示译文'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'language',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _showLanguage ? Icons.notes : Icons.notes_outlined,
                  ),
                  title: Text(_showLanguage ? '隐藏语言点' : '显示语言点'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'offline-audio',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: Text(
                    offline?.status == OfflineAudioStatus.generating
                        ? '离线朗读生成中 ${offline!.done}/${offline.total}'
                        : offline?.entry == null
                        ? '生成离线朗读'
                        : '离线朗读（${formatTtsAudioBytes(offline!.bytes)}）',
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'auto-vocab',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_awesome),
                  title: Text('自动标词'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'batch',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _showBatch
                        ? Icons.smart_toy
                        : Icons.smart_toy_outlined,
                  ),
                  title: Text(_showBatch ? '收起 AI-Batch Work' : 'AI-Batch Work'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'lang-sheet',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.translate),
                  title: Text('语言点（整篇）'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'vocab',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Badge(
                    label: Text('${vm.currentEntries.length}'),
                    isLabelVisible: vm.currentEntries.isNotEmpty,
                    child: const Icon(Icons.list_alt),
                  ),
                  title: Text('本篇词表（${vm.currentEntries.length}）'),
                ),
              ),
            ],
          ),
        ],
      ),
      // 词表放右侧抽屉：从右边缘往左滑也能拉出来（`endDrawerEnableOpenDragGesture`）。
      endDrawer: const _VocabDrawer(),
      endDrawerEnableOpenDragGesture: true,
      body: Column(
        children: [
          // AI-Batch Work：默认不占位，点顶栏那个机器人按钮才出现（收起成一行）。
          if (_showBatch) AiBatchBar(articleId: article.id),
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
              // 点句子 = 朗读这一句（用户 2026-11-15 要求，不再弹取词面板）；
              // 长按复制整句由 `sentence_tap.dart` 处理。
              onTapSentence: (s) {
                vm.selectSentence(s.id);
                unawaited(_speakSentence(vm, s));
              },
              onTapWord: (s, index, word) => pick?.toggle(s.id, index, word),
            ),
          ),
        ],
      ),
      // 底栏只在选词模式下出现（选词条）。平时的「本篇已收 N 个」用户说没用，删了。
      bottomNavigationBar: picking
          ? PickBar(
              pick: pick,
              busy: vm.busy,
              articleEntries: vm.currentEntries,
              onCommit: (entries) => _commitPicks(vm, article, entries),
            )
          : null,
    );
  }

  /// 顶栏「更多」菜单的六项（原来是一排图标，挤到返回键了）。
  void _onMenu(
    BuildContext context,
    ReaderViewModel vm,
    SavedArticle article,
    PickModeViewModel? pick,
    String value,
  ) {
    switch (value) {
      case 'translation':
        setState(() => _showTranslation = !_showTranslation);
      case 'language':
        setState(() => _showLanguage = !_showLanguage);
      case 'offline-audio':
        final audio = context.read<OfflineAudioViewModel?>();
        if (audio == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('离线朗读没有接上，重启 App 再试')),
          );
          return;
        }
        _openOfflineAudioSheet(context, audio, article);
      case 'auto-vocab':
        runAutoVocab(
          context,
          vm: vm,
          article: article,
          known: {
            for (final v in vm.currentEntries) v.item.lemma.toLowerCase(),
          },
        );
      case 'batch':
        setState(() => _showBatch = !_showBatch);
      case 'lang-sheet':
        _openLanguageSheet(context, vm, article);
      case 'vocab':
        _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  /// 点句朗读；如果这一档在原生侧失败了，把它退回系统朗读的原因告诉用户。
  Future<void> _speakSentence(ReaderViewModel vm, Sentence sentence) async {
    await vm.speakSentence(sentence.id, sentence.text);
    if (!mounted) return;
    final tts = context.read<TtsViewModel?>();
    if (tts?.speech.fellBack != true) return;
    final reason = tts!.speech.fallbackReason;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(reason ?? 'Kokoro 没跑起来，这一次用的是系统朗读')),
    );
  }

  /// 打开「离线朗读音频」面板。
  Future<void> _openOfflineAudioSheet(
    BuildContext context,
    OfflineAudioViewModel offline,
    SavedArticle article,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _OfflineAudioSheet(offline: offline, article: article),
    );
  }

  /// 选中的条目（单词 / 词组，各带类型）一次性加进本篇。
  Future<void> _commitPicks(
    ReaderViewModel vm,
    SavedArticle article,
    List<PickEntry> entries,
  ) async {
    var added = 0;
    for (final entry in entries) {
      final saved = await vm.markCurrentWord(
        entry.word,
        sentenceId: entry.sentenceId,
        sentenceText: null,
        kind: entry.kind,
      );
      if (saved != null) added++;
    }
    if (!mounted) return;
    context.read<PickModeViewModel?>()?.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0 ? '没加进去（可能已收过）' : '已收录 $added 条',
        ),
      ),
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

/// 「离线朗读音频」底部面板：生成进度 / 体积 / 删除 / 重新生成。
class _OfflineAudioSheet extends StatelessWidget {
  const _OfflineAudioSheet({required this.offline, required this.article});

  final OfflineAudioViewModel offline;
  final SavedArticle article;

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsViewModel?>();
    final kokoro = tts?.provider == TtsProvider.kokoro;
    return AnimatedBuilder(
      animation: offline,
      builder: (context, _) {
        final theme = Theme.of(context);
        final status = offline.status;
        final entry = offline.entry;
        final total = article.sentences
            .where((s) => s.text.trim().isNotEmpty)
            .length;
        final estimate = estimateTtsAudioBytes(
          article.sentences.map((s) => s.text).join(' '),
        );
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.offline_bolt_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '离线朗读音频',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (entry != null)
                      Text(
                        formatTtsAudioBytes(entry.bytes),
                        style: theme.textTheme.labelMedium,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '用当前 Kokoro 音色把整篇合成成音频文件。最多保留 2 篇，'
                  '生成第 3 篇会自动删最久没用的那一篇。生成中可以关掉这个面板'
                  '先去读，后台会继续；要停就点取消。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (!offline.supported)
                  Text(
                    '这个版本没有接上离线朗读。',
                    style: TextStyle(color: theme.colorScheme.error),
                  )
                else if (status == OfflineAudioStatus.generating) ...[
                  LinearProgressIndicator(
                    value: offline.total == 0
                        ? null
                        : offline.done / offline.total,
                  ),
                  const SizedBox(height: 8),
                  Text('正在生成 ${offline.done} / ${offline.total} 句…'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('先退出，后台继续'),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: offline.cancel,
                        child: const Text('取消'),
                      ),
                    ],
                  ),
                ] else ...[
                  if (entry != null) ...[
                    Text(
                      '已生成 ${entry.sentenceCount} 句 · '
                      '${formatTtsAudioBytes(entry.bytes)}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '音色：${ttsVoiceLabel(TtsProvider.kokoro, entry.voice)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else
                    Text(
                      '预计 ${formatTtsAudioBytes(estimate)} · $total 句'
                      '（AAC 64kbps）',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (!kokoro) ...[
                    const SizedBox(height: 8),
                    Text(
                      '当前朗读档不是 Kokoro。先到「朗读设置」切到 Kokoro，'
                      '生成和缓存播放才生效。',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  if (offline.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      offline.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (entry != null)
                        OutlinedButton.icon(
                          onPressed: () => _confirmDelete(context),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('删除'),
                        ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: !kokoro || !offline.supported
                            ? null
                            : () {
                                offline.generate(article);
                              },
                        icon: const Icon(Icons.download),
                        label: Text(entry == null ? '开始生成' : '重新生成'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除离线朗读？'),
        content: Text('会删掉《${article.title}》的音频缓存，下次点句会重新现合成。'),
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
    if (ok == true) await offline.delete();
  }
}
