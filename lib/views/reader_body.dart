/// 精读正文：逐句排版 + 译文 / 语言点 + 选词模式。
///
/// 从 `reader_page.dart` 拆出来的（那个文件已到 450 行，再加选词就撞 800 行门禁）。
///
/// 选词模式的渲染交给 `pickable_sentence.dart` 的 [PickableSentence]：
/// 速读页用的是同一个部件，所以两边的点词手感、选中配色、已收下划线完全一致。
library;

import 'package:flutter/material.dart';

import '../core/article_vocab.dart' show ArticleEntryView;
import '../core/language.dart' show getSentenceLanguages;
import '../core/word_pick.dart' show PickEntry;
import '../models/document.dart';
import '../viewmodels/pick_mode_view_model.dart';
import 'pickable_sentence.dart';
import 'sentence_extras.dart';

/// 精读正文。
class ReaderBody extends StatelessWidget {
  const ReaderBody({
    super.key,
    required this.article,
    required this.selected,
    this.showTranslation = true,
    this.showLanguage = true,
    this.pick,
    this.pickedLemmas = const <String>{},
    this.onTapSentence,
    this.onTapWord,
  });

  final SavedArticle article;

  /// 当前选中的句子 id（高亮用）。
  final String? selected;

  final bool showTranslation;
  final bool showLanguage;

  /// 选词模式（null = 不支持选词，按普通阅读渲染）。
  final PickModeViewModel? pick;

  /// 本篇已经收过的词原形（选词模式里标成「已收」，防止重复点）。
  final Set<String> pickedLemmas;

  final void Function(Sentence sentence)? onTapSentence;

  /// 点某个词：`index` 与 `wordSpans` 的下标一致。
  final void Function(Sentence sentence, int index, String word)? onTapWord;

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
    final extras = SentenceExtras(
      sentence: s,
      showTranslation: showTranslation,
      showLanguage: showLanguage,
    );
    final hasExtras = (showTranslation &&
            (s.translation ?? '').trim().isNotEmpty) ||
        (showLanguage && getSentenceLanguages(s).isNotEmpty);

    final picking = pick != null && pick!.enabled;
    // 句尾带一个空格：段落里句子是连着排的，这个空格就是句子之间的间隔。
    // 拆词渲染时它是末尾的 tail，会原样保留。
    final body = PickableSentence(
      sentenceId: s.id,
      text: '${s.text} ',
      pick: pick,
      style: Theme.of(context).textTheme.bodyLarge,
      highlight: s.id == selected,
      pickedLemmas: pickedLemmas,
      onTapWord: (index, word) => onTapWord?.call(s, index, word),
    );
    // 不开选词模式时点句子仍然打开取词面板（老用户的习惯路径）。
    final tappable = picking || onTapSentence == null
        ? body
        : InkWell(
            key: ValueKey('sentence-${s.id}'),
            onTap: () => onTapSentence!(s),
            child: body,
          );

    if (!hasExtras) return <Widget>[tappable];
    return <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [tappable, extras],
      ),
    ];
  }
}

/// 底部选词条：选中几个词 + 加入生词本 / 清空。
///
/// 用户说的「快速读一遍，把自动选词没选入的词加进生词本」就是这条：
/// 精读和速读共用同一份 [PickModeViewModel]，所以在哪一页攒的都能在这加。
class PickBar extends StatelessWidget {
  const PickBar({
    super.key,
    required this.pick,
    required this.busy,
    required this.onCommit,
    this.articleEntries = const <ArticleEntryView>[],
  });

  final PickModeViewModel pick;
  final bool busy;

  /// 把选中的条目（单词 / 词组，各带类型）加进生词本。
  final Future<void> Function(List<PickEntry> entries) onCommit;

  /// 本篇已有的词条（给「已收」标记用）。
  final List<ArticleEntryView> articleEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = pick.count;
    final entries = pick.state.entries;
    final phraseCount = entries.where((e) => e.isPhrase).length;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.pan_tool,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _pickSummary(n, entries.length, phraseCount),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (n == 0)
                    Text(
                      pick.multi ? '可以连着点几个词拼成词组' : '一次只收一个词',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // 多选开关：默认关（单选），要词组时自己打开。
            FilterChip(
              key: const ValueKey('pick-multi'),
              label: const Text('多选'),
              selected: pick.multi,
              visualDensity: VisualDensity.compact,
              onSelected: pick.setMulti,
            ),
            if (n > 0)
              TextButton(
                onPressed: pick.clear,
                child: const Text('清空'),
              ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: n == 0 || busy ? null : () => onCommit(entries),
              child: Text(phraseCount > 0 ? '加入生词本（$phraseCount 词组）' : '加入生词本'),
            ),
          ],
        ),
      ),
    );
  }

  static String _pickSummary(int words, int entries, int phrases) {
    if (words == 0) return '点正文里的词选中';
    if (entries == words) return '已选 $words 个词';
    return '已选 $words 个词 · $entries 条（$phrases 条词组）';
  }
}
