/// 阅读页：逐句正文 + 点句取词 + 本篇词表。
///
/// 交互按 `docs/ARCHITECTURE.md` 的「Web 语义 → Flutter」对照表：
/// 正文点选（Web 的鼠标划词）→ 点句子打开取词面板；
/// 悬浮详情（Web 的 hover）→ 长按列表项。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/analyzer_parse.dart' show ParsedAnalysis, parseAnalysis;
import '../core/analyzer_prompt.dart' show buildPrompt;
import '../core/analyzer_shared.dart'
    show AnalysisTask, BuildPromptInput;
import '../core/article_vocab.dart';
import '../core/language.dart'
    show buildLanguagePrompt, getSentenceLanguages;
import '../core/vocab/analysis_fill.dart'
    show applyFilledWords, fillAllFromDict, wordAnalysisFromDict;
import '../core/vocab/word.dart' show lemmaOf;
import '../core/word_select.dart';
import '../data/dictionary_loader.dart' show dictionary;
import '../models/document.dart';
import '../viewmodels/reader_view_model.dart';
import 'ai_paste_sheet.dart';
import 'sentence_extras.dart';

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

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReaderViewModel>();
    final article = vm.current;
    if (article == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('没有打开的文章')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(article.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
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
            onPressed: () => _openVocabSheet(context, vm),
          ),
        ],
      ),
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
            child: _Body(
              article: article,
              selected: vm.selectedSentenceId,
              showTranslation: _showTranslation,
              showLanguage: _showLanguage,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(vm: vm),
    );
  }

  Future<void> _openVocabSheet(BuildContext context, ReaderViewModel vm) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<ReaderViewModel>.value(
        value: vm,
        child: const _VocabSheet(),
      ),
    );
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

class _Body extends StatelessWidget {
  const _Body({
    required this.article,
    required this.selected,
    this.showTranslation = true,
    this.showLanguage = true,
  });

  final SavedArticle article;
  final String? selected;
  final bool showTranslation;
  final bool showLanguage;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final s in article.sentences) s.id: s};
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: article.paragraphs.length,
      itemBuilder: (context, i) {
        final para = article.paragraphs[i];
        final sentences = [
          for (final id in para.sentenceIds)
            if (byId[id] != null) byId[id]!,
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              for (final s in sentences) ..._sentenceChildren(context, s),
            ],
          ),
        );
      },
    );
  }

  /// 一句要占几个排版单元。
  ///
  /// 没译文也没语言点时只出一个内联的原文（句子连着排，和以前一样）；
  /// 有其中任意一样时整句变成一块（原文 + 下面的附加信息）。
  /// 这与 Web 版一致：`tr-block` / `lang-block` 是块级元素，会把行断开，
  /// 而普通句子继续在同一行里流。
  List<Widget> _sentenceChildren(BuildContext context, Sentence s) {
    final theme = Theme.of(context);
    final raw = Text.rich(
      TextSpan(text: '${s.text} '),
      style: theme.textTheme.bodyLarge?.copyWith(
        height: 1.55,
        color: s.id == selected ? theme.colorScheme.primary : null,
        backgroundColor: s.id == selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
      ),
    );
    final extras = SentenceExtras(
      sentence: s,
      showTranslation: showTranslation,
      showLanguage: showLanguage,
    );
    final hasExtras = (showTranslation &&
            (s.translation ?? '').trim().isNotEmpty) ||
        (showLanguage && getSentenceLanguages(s).isNotEmpty);
    if (!hasExtras) {
      return <Widget>[
        InkWell(
          key: ValueKey('sentence-${s.id}'),
          onTap: () => _openSentenceSheet(context, s),
          child: raw,
        ),
      ];
    }
    return <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: ValueKey('sentence-${s.id}'),
            onTap: () => _openSentenceSheet(context, s),
            child: raw,
          ),
          extras,
        ],
      ),
    ];
  }

  Future<void> _openSentenceSheet(BuildContext context, Sentence s) async {
    final vm = context.read<ReaderViewModel>();
    vm.selectSentence(s.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<ReaderViewModel>.value(
        value: vm,
        child: _SentenceSheet(
          sentence: s,
          articleId: article.id,
          fileName: article.book,
        ),
      ),
    );
    vm.selectSentence(null);
  }
}

/// 一句话里的取词面板：点一个词就收进本篇。
class _SentenceSheet extends StatefulWidget {
  const _SentenceSheet({
    required this.sentence,
    required this.articleId,
    this.fileName,
  });

  final Sentence sentence;

  /// 查词结果要挂到哪一篇上（按篇来源 + 语境）。
  final String articleId;
  final String? fileName;

  @override
  State<_SentenceSheet> createState() => _SentenceSheetState();
}

class _SentenceSheetState extends State<_SentenceSheet> {
  final TextEditingController _meaning = TextEditingController();
  String? _picked;

  @override
  void dispose() {
    _meaning.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReaderViewModel>();
    // 同一句里重复出现的词只给一个按钮；已收的词不再重复列。
    final collected = {for (final v in vm.currentEntries) v.item.lemma};
    final spans = mergeHyphenated(widget.sentence.text, wordSpans(widget.sentence.text));
    final words = <String>[];
    for (final w in spans) {
      if (!collected.contains(normalizeLemma(w.text))) words.add(w.text);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.sentence.text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (words.isEmpty)
            const Text('这句的词都已经收过了')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in words)
                  ChoiceChip(
                    label: Text(w),
                    selected: _picked == w,
                    onSelected: (_) => setState(() => _picked = w),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          if (_picked != null) _dictPreview(context),
          TextField(
            controller: _meaning,
            decoration: const InputDecoration(
              labelText: '释义（可空，之后查词再补）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _picked == null || vm.busy
                ? null
                : () async {
                    final ok = await vm.markCurrentWord(
                      _picked!,
                      sentenceId: widget.sentence.id,
                      sentenceText: widget.sentence.text,
                      meaning: _meaning.text.trim().isEmpty
                          ? null
                          : _meaning.text.trim(),
                    );
                    if (!context.mounted) return;
                    if (ok == null) return;
                    setState(() {
                      _picked = null;
                      _meaning.clear();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已收录 ${ok.word}')),
                    );
                  },
            child: const Text('收进本篇'),
          ),
          const Divider(height: 32),
          Text('用 AI 补齐（复制提示词 → 粘到网页版 AI → 结果粘回来）',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _picked == null ? null : () => _lookup(context, vm),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('查这个词'),
              ),
              OutlinedButton(
                onPressed: () => _analyze(
                  context,
                  vm,
                  task: AnalysisTask.translate,
                  title: '翻译这一句',
                  hint: '直接粘译文就行',
                ),
                child: const Text('翻译'),
              ),
              OutlinedButton(
                onPressed: () => _analyze(
                  context,
                  vm,
                  task: AnalysisTask.grammar,
                  title: '分析句子结构',
                  hint: '粘 AI 给的结构分析',
                ),
                child: const Text('结构'),
              ),
              OutlinedButton(
                onPressed: () => _analyze(
                  context,
                  vm,
                  task: AnalysisTask.collocations,
                  title: '挑搭配',
                  hint: '每条一行，用「 — 」分隔搭配和中文',
                ),
                child: const Text('搭配'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 选中词立刻用离线词典查一遍（不联网、不复制提示词）。
  ///
  /// 查得到就把音标 / 词性 / 释义摊在面板里，并给一个「填进释义」按钮 ——
  /// 大多数词到这里就结束了，不用再走 AI。查不到才提示用下面的 AI 查词。
  Widget _dictPreview(BuildContext context) {
    final found = wordAnalysisFromDict(dictionary(), _picked!);
    final theme = Theme.of(context).textTheme;
    if (found == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '离线词典里没查到，可以自己写释义，或用下面的 AI 查词。',
          style: theme.bodySmall,
        ),
      );
    }
    final gloss = found.meaning ?? found.definition;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(found.word, style: theme.titleSmall),
              if (found.phonetic != null) ...[
                const SizedBox(width: 8),
                Text(found.phonetic!, style: theme.bodySmall),
              ],
              if (found.partOfSpeech != null) ...[
                const SizedBox(width: 8),
                Text(
                  found.partOfSpeech!,
                  style: theme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
          if (gloss != null) ...[
            const SizedBox(height: 6),
            Text(gloss, style: theme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: gloss == null
                  ? null
                  : () => setState(() {
                        _meaning.text = _shortGloss(gloss);
                      }),
              icon: const Icon(Icons.arrow_downward, size: 16),
              label: const Text('填进释义'),
            ),
          ),
        ],
      ),
    );
  }

  /// 词典释义是多行的（`n. 竞争对手\nvt. 与……匹敌`），填进输入框只取第一行。
  String _shortGloss(String gloss) {
    final line = gloss.split('\n').first.trim();
    return line.isEmpty ? gloss : line;
  }

  /// 查词：提示词 → 粘回表格 → `applyWordAnalysis` 落盘。
  Future<void> _lookup(BuildContext context, ReaderViewModel vm) async {
    final word = _picked;
    if (word == null) return;
    final prompt = buildPrompt(
      BuildPromptInput(
        task: AnalysisTask.lookup,
        text: widget.sentence.text,
        words: [word],
      ),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiPasteSheet(
        title: '查词：$word',
        prompt: prompt,
        hint: '一行一个词，字段用 | 分隔',
        onApply: (raw) async {
          final ParsedAnalysis parsed = parseAnalysis(raw);
          if (parsed.words.isEmpty) {
            return '没解析出词条，检查一下是不是粘错了';
          }
          // AI 优先、离线词典只补空缺（词性 / 释义 / 英英必须同源）。
          final filled = fillAllFromDict(parsed.words, dictionary());
          final saved = await vm.applyLibraryTransform(
            (lib) => applyFilledWords(
              lib,
              filled,
              articleId: widget.articleId,
              fileName: widget.fileName,
              sentenceId: widget.sentence.id,
              sentenceText: widget.sentence.text,
            ),
          );
          if (saved == null) return vm.error ?? '写词库失败';
          return null;
        },
      ),
    );
  }

  /// 翻译 / 结构 / 搭配：结果落到当前句子上。
  Future<void> _analyze(
    BuildContext context,
    ReaderViewModel vm, {
    required AnalysisTask task,
    required String title,
    required String hint,
  }) async {
    final prompt = buildPrompt(
      BuildPromptInput(task: task, text: widget.sentence.text),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiPasteSheet(
        title: title,
        prompt: prompt,
        hint: hint,
        onApply: (raw) async {
          final updated = await vm.applySentenceAnalysis(
            sentenceId: widget.sentence.id,
            task: task,
            raw: raw,
          );
          return updated == null ? (vm.error ?? '没落到句子上') : null;
        },
      ),
    );
  }
}

/// 底部条：本篇词数 + 打开词表。
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
            Icon(Icons.touch_app_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '点任意一句取词 · 本篇已收 $n 个',
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

/// 本篇词表（侧栏）。
class _VocabSheet extends StatelessWidget {
  const _VocabSheet();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReaderViewModel>();
    final entries = vm.currentEntries;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('本篇词表（${entries.length}）',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '还没收词。点正文任意一句，再点里面的词就能收进来。',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final view = entries[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontSize: 11)),
                      ),
                      title: Text(view.item.word),
                      subtitle: Text(_lineOf(view)),
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

/// 取词面板里用：与 `lib/core/vocab/word.dart` 的 lemma 口径保持一致。
String normalizeLemma(String raw) => lemmaOf(raw);
