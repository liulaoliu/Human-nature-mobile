/// 自动标词：按词汇水平让 AI 从正文里挑词，勾选后一次收进本篇。
///
/// 流程与 Web 的 `ReaderToolbar.tsx:287`（`tb-autovocab`）一致，
/// 只是手机上把「待选页签」换成一张可勾选的清单：
///   选水平 → 复制提示词 → 粘回结果 → 勾选 → 收进本篇。
library;

import 'package:flutter/material.dart';

import '../core/analyzer_prompt.dart' show buildAutoVocabPrompt;
import '../core/auto_vocab.dart';
import '../core/ecdict.dart' show EcdictLevel;
import '../models/document.dart' show SavedArticle;
import '../viewmodels/reader_view_model.dart';
import 'ai_paste_sheet.dart';

/// 跑一遍自动标词。
///
/// [known] 传本篇已有的原形（小写），用来把「已经收过的」提前剔掉；
/// 不传就全列出来，由用户自己看着勾。
Future<void> runAutoVocab(
  BuildContext context, {
  required ReaderViewModel vm,
  required SavedArticle article,
  Set<String> known = const {},
}) async {
  final level = await showDialog<EcdictLevel>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('按什么水平挑词'),
      children: [
        for (final value in EcdictLevel.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(value),
            child: Text(autoVocabLevelLabel[value] ?? value.name),
          ),
      ],
    ),
  );
  if (level == null || !context.mounted) return;

  final text = article.sentences.map((s) => s.text).join(' ').trim();
  if (text.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('这篇没有正文，挑不出词')));
    return;
  }

  List<String>? candidates;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AiPasteSheet(
        title: '自动标词（${autoVocabLevelLabel[level] ?? level.name}）',
        prompt: buildAutoVocabPrompt(text, level: level),
        hint: '每行一个原形单词；带编号、释义、短语的行会自动清理掉',
        onApply: (raw) async {
          final picked = autoVocabCandidates(raw, known: known);
          if (picked.isEmpty) return '没挑出新的词（可能都已经收过了）';
          candidates = picked;
          return null;
        },
      ),
    ),
  );
  if (!context.mounted) return;
  final picked = candidates;
  if (picked == null || picked.isEmpty) return;

  final chosen = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CandidateSheet(words: picked),
  );
  if (chosen == null || chosen.isEmpty || !context.mounted) return;

  var added = 0;
  for (final word in chosen) {
    final saved = await vm.markCurrentWord(word);
    if (saved != null) added++;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(added == 0 ? '都没加进去（可能已收过）' : '已收进本篇 $added 个'),
    ),
  );
}

/// 勾选清单。
///
/// 默认**全选**：AI 挑出来的通常就是想要的，让用户从「全选」往下减，
/// 比从「全不选」往上加省事（Web 的「待选」默认也是全要）。
class _CandidateSheet extends StatefulWidget {
  const _CandidateSheet({required this.words});

  final List<String> words;

  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
  late final Set<String> _picked = {...widget.words};

  void _toggle(String word, bool on) {
    setState(() {
      if (on) {
        _picked.add(word);
      } else {
        _picked.remove(word);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = _picked.length == widget.words.length;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '挑出 ${widget.words.length} 个词',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    if (all) {
                      _picked.clear();
                    } else {
                      _picked
                        ..clear()
                        ..addAll(widget.words);
                    }
                  }),
                  child: Text(all ? '全不选' : '全选'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.words.length,
              itemBuilder: (context, i) {
                final word = widget.words[i];
                return CheckboxListTile(
                  value: _picked.contains(word),
                  onChanged: (v) => _toggle(word, v ?? false),
                  title: Text(word),
                  dense: true,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _picked.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_picked.toList()),
                child: Text('收进本篇 ${_picked.length} 个'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
