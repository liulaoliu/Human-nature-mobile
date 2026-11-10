/// 句子下面挂的附加信息：中文译文 + 语言点（结构 / 语法 / 习语 / 词组 / 用法）。
///
/// 为什么单独一个文件：阅读页正文只该管「原文怎么排」（点句取词、选中高亮），
/// 译文与语言点是另一层信息，样式与顺序只在这里定义一次。
/// 五行文案与顺序对齐 Web 版 `src/reader/panels/LanguageLines.tsx`。
library;

import 'package:flutter/material.dart';

import '../core/entry_kind.dart' show VocabKind, kindLabel;
import '../core/language.dart' show getSentenceLanguages;
import '../models/document.dart';

/// 一句的附加信息（译文 + 语言点）。两样都没有时返回 [SizedBox.shrink]。
class SentenceExtras extends StatelessWidget {
  const SentenceExtras({
    super.key,
    required this.sentence,
    this.showTranslation = true,
    this.showLanguage = true,
    this.onAddPhrase,
  });

  final Sentence sentence;
  final bool showTranslation;
  final bool showLanguage;

  /// 点词组时回调（传进来才可点；阅读页用它把词组收进本篇）。
  final void Function(String phrase)? onAddPhrase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final translation =
        showTranslation ? (sentence.translation ?? '').trim() : '';
    final langs = showLanguage ? getSentenceLanguages(sentence) : const [];
    if (translation.isEmpty && langs.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    if (translation.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 2, bottom: 6),
          child: Text(
            translation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: dim,
              height: 1.7,
            ),
          ),
        ),
      );
    }
    for (final lang in langs) {
      final lines = <Widget>[];
      if ((lang.structure ?? '').trim().isNotEmpty) {
        lines.add(_line('结构', lang.structure!, theme, dim));
      }
      if ((lang.grammar ?? '').trim().isNotEmpty) {
        lines.add(_line('语法', lang.grammar!, theme, dim));
      }
      if (lang.idioms != null && lang.idioms!.isNotEmpty) {
        lines.add(
          _terms(kindLabel[VocabKind.idiom]!, lang.idioms!, theme, dim),
        );
      }
      if (lang.phrases != null && lang.phrases!.isNotEmpty) {
        lines.add(
          _terms(
            kindLabel[VocabKind.phrase]!,
            lang.phrases!,
            theme,
            dim,
            onTap: onAddPhrase,
          ),
        );
      }
      if (lang.usage != null && lang.usage!.isNotEmpty) {
        lines.add(_terms('用法', lang.usage!, theme, dim));
      }
      if (lines.isEmpty) continue;
      children.add(
        Container(
          margin: const EdgeInsets.only(left: 2, bottom: 10),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lang.source == LanguageSource.manual)
                Text(
                  '手动',
                  style: theme.textTheme.labelSmall?.copyWith(color: dim),
                ),
              ...lines,
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _line(String label, String body, ThemeData theme, Color dim) => Text(
        '$label：$body',
        style: theme.textTheme.bodySmall?.copyWith(color: dim, height: 1.7),
      );

  /// 习语 / 词组 / 用法这类列表：项之间用「；」，可选的点击回调。
  Widget _terms(
    String label,
    List<String> items,
    ThemeData theme,
    Color dim, {
    void Function(String)? onTap,
  }) {
    final text = '$label：${items.join('；')}';
    if (onTap == null) return _line(label, items.join('；'), theme, dim);
    return InkWell(
      onTap: () => onTap(text.substring(label.length + 1)),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: dim,
          height: 1.7,
          decoration: TextDecoration.underline,
          decorationColor: dim.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
