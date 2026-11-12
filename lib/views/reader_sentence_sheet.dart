/// 一句话里的取词面板：点一个词就收进本篇。
///
/// 从 `reader_page.dart` 拆出来的：阅读页本身要加选词模式，再挤在一起就撞
/// 800 行的上帝文件门禁。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/analyzer_parse.dart' show ParsedAnalysis, parseAnalysis;
import '../core/analyzer_prompt.dart' show buildPrompt;
import '../core/analyzer_shared.dart' show AnalysisTask, BuildPromptInput;
import '../core/vocab/analysis_fill.dart'
    show applyFilledWords, fillAllFromDict, wordAnalysisFromDict;
import '../core/vocab/word.dart' show lemmaOf;
import '../core/word_select.dart';
import '../data/dictionary_loader.dart' show dictionary;
import '../models/document.dart';
import '../viewmodels/reader_view_model.dart';
import 'ai_paste_sheet.dart';

/// 取词面板里用：与 `lib/core/vocab/word.dart` 的 lemma 口径保持一致。
String normalizeLemma(String raw) => lemmaOf(raw);

/// 弹出某一句的取词面板。
Future<void> showSentenceSheet(
  BuildContext context, {
  required Sentence sentence,
  required String articleId,
  String? fileName,
}) async {
  final vm = context.read<ReaderViewModel>();
  vm.selectSentence(sentence.id);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<ReaderViewModel>.value(
      value: vm,
      child: SentenceSheet(
        sentence: sentence,
        articleId: articleId,
        fileName: fileName,
      ),
    ),
  );
  vm.selectSentence(null);
}

/// 一句话的取词面板。
class SentenceSheet extends StatefulWidget {
  const SentenceSheet({
    super.key,
    required this.sentence,
    required this.articleId,
    this.fileName,
  });

  final Sentence sentence;

  /// 查词结果要挂到哪一篇上（按篇来源 + 语境）。
  final String articleId;
  final String? fileName;

  @override
  State<SentenceSheet> createState() => _SentenceSheetState();
}

class _SentenceSheetState extends State<SentenceSheet> {
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
    final spans =
        mergeHyphenated(widget.sentence.text, wordSpans(widget.sentence.text));
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
