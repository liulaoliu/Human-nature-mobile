/// 一段可点词的正文（精读与速读共用）。
///
/// 为什么不用 `TextSpan(recognizer:)`：每个 `TapGestureRecognizer` 都要手动
/// dispose，而 `build` 会反复跑（选词、计时、翻面都会重建），很容易漏掉、
/// 或者把旧 recognizer 留在旧 TextPainter 上。按词渲染成 [Text] 最简单，
/// 英文换行本来就在词边界，排版效果和整段一致。
library;

import 'package:flutter/material.dart';

import '../core/word_select.dart' show mergeHyphenated, wordSpans;
import '../viewmodels/pick_mode_view_model.dart';

/// 一句/一段正文，选词模式下逐词可点。
class PickableSentence extends StatelessWidget {
  const PickableSentence({
    super.key,
    required this.sentenceId,
    required this.text,
    required this.pick,
    this.style,
    this.highlight = false,
    this.pickedLemmas = const <String>{},
    this.onTapWord,
  });

  /// 用哪一句的身份记选中（要和 `Sentence.id` 一致）。
  final String sentenceId;

  final String text;

  /// 选词模式状态；为 null 或没打开时退化成普通整段文字。
  final PickModeViewModel? pick;

  final TextStyle? style;

  /// 整句高亮（精读里选中某句时用）。
  final bool highlight;

  /// 本篇已收的词原形（给下划线提示，防重复点）。
  final Set<String> pickedLemmas;

  /// 点词回调：`index` 与 `wordSpans` 的下标一致。
  final void Function(int index, String word)? onTapWord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = (style ?? theme.textTheme.bodyLarge)?.copyWith(
      height: 1.55,
      color: highlight ? theme.colorScheme.primary : null,
      backgroundColor:
          highlight ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
    );
    final vm = pick;
    if (vm == null || !vm.enabled) {
      return Text.rich(TextSpan(text: text), style: base);
    }

    final spans = mergeHyphenated(text, wordSpans(text));
    if (spans.isEmpty) return Text.rich(TextSpan(text: text), style: base);

    final children = <Widget>[];
    var cursor = 0;
    for (var i = 0; i < spans.length; i++) {
      final span = spans[i];
      // span 之前的空白 / 标点原样保留，别丢。
      final gap = text.substring(cursor, span.start);
      if (gap.isNotEmpty) children.add(Text(gap, style: base));
      final picked = vm.state.contains(sentenceId, i);
      children.add(
        GestureDetector(
          key: ValueKey('pick-$sentenceId-$i'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onTapWord?.call(i, span.text),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            decoration: picked
                ? BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(3),
                  )
                : null,
            child: Text(
              span.text,
              style: base?.copyWith(
                color: picked ? theme.colorScheme.primary : null,
                decoration: pickedLemmas.contains(span.text.toLowerCase())
                    ? TextDecoration.underline
                    : null,
                decorationStyle: TextDecorationStyle.dotted,
              ),
            ),
          ),
        ),
      );
      cursor = span.end;
    }
    final tail = text.substring(cursor);
    if (tail.isNotEmpty) children.add(Text(tail, style: base));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
