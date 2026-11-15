import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/golden_drill.dart';
import '../widgets/english_input.dart';

/// 填空正文：把整句排成一段**文章**，空位是嵌在行内的下划线输入框。
///
/// 为什么不再用 `Wrap` + 固定宽度的 `SizedBox`（用户 2026-11-15 要求）：
/// `Wrap` 的每个 child 都按整行宽度测量，长文本段会独占一行、空和文字各占
/// 一块，整句被排成「竖着的一列盒子」。改成 `Text.rich` + `WidgetSpan` 后，
/// 换行交给段落排版：文字和空一起铺满一行，空不够位置就跟着下一个词换行，
/// 跟阅读正文的观感一致。
///
/// 输入框、焦点、GlobalKey 都由外面的 `GoldenDrillView` 持有 —— 换轮要清空、
/// 判分要保留原作答、键盘要滚到当前空，这些都依赖同一个生命周期。
class GoldenFillView extends StatelessWidget {
  const GoldenFillView({
    super.key,
    required this.cloze,
    required this.controllers,
    required this.focuses,
    required this.blankKeys,
    required this.progress,
    required this.scored,
    required this.results,
    this.scrollController,
    this.onSubmitted,
  });

  final GoldenCloze cloze;

  /// 每个**空**（`cloze.blanks` 的一条）一个 controller。
  ///
  /// 按词的细碎轮会把重复出现的同一学习点去重成一条空，此时两处空位
  /// 共用一个 controller、打字同步；整句轮每个出现位置各是一条空。
  final List<TextEditingController> controllers;

  /// 每个**空位**（句子里出现的位置）一个焦点 / key。
  ///
  /// 不能按答案建：同一学习点在句子里出现两次时，一个 FocusNode 挂两个
  /// TextField、一个 GlobalKey 用在两个 WidgetSpan 上都会报错。
  final List<FocusNode> focuses;

  /// 每个空位一个 key：键盘弹出后用它把被挡住的空滚进可视区。
  final List<GlobalKey> blankKeys;

  /// 「第 3/10 句 · 填空 1/2」这类进度串，画在填空区第一行。
  final String progress;

  final bool scored;
  final List<bool> results;
  final ScrollController? scrollController;

  /// 键盘上按回车：等于点「交这一轮」。
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: scrollController,
      // 键盘弹出时 Scaffold 会把 body 缩到键盘上方，这里再加一段底部留白：
      // 最后一个空能滚到键盘上方，而不是贴着屏幕底边。
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: <Widget>[
        Text(
          progress,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        _ClozeParagraph(
          cloze: cloze,
          controllers: controllers,
          focuses: focuses,
          blankKeys: blankKeys,
          scored: scored,
          results: results,
          onSubmitted: onSubmitted,
        ),
        if (scored) ...<Widget>[
          const SizedBox(height: 16),
          _RoundVerdict(results: results),
        ],
      ],
    );
  }
}

/// 整句 + 行内空位。
class _ClozeParagraph extends StatelessWidget {
  const _ClozeParagraph({
    required this.cloze,
    required this.controllers,
    required this.focuses,
    required this.blankKeys,
    required this.scored,
    required this.results,
    required this.onSubmitted,
  });

  final GoldenCloze cloze;
  final List<TextEditingController> controllers;
  final List<FocusNode> focuses;
  final List<GlobalKey> blankKeys;
  final bool scored;
  final List<bool> results;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 行高留够输入框的高度；否则 WidgetSpan 会把行撑开，行距忽大忽小。
    final textStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      height: 2.0,
    );
    final spans = <InlineSpan>[];
    // `parts` 是「空位」序列；`blankIndex` 指向答案（`cloze.blanks`）。
    // 同一学习点重复出现时两个空位指向同一个答案，但焦点 / key 必须各一份。
    var slot = 0;
    for (final part in cloze.parts) {
      if (!part.blank) {
        spans.add(TextSpan(text: part.text));
        continue;
      }
      final currentSlot = slot++;
      final i = (part.blankIndex ?? 0) - 1;
      // 防御：控制器还没建齐（理论上同帧就建好了）时不画空，别越界。
      if (i < 0 || i >= controllers.length || i >= cloze.blanks.length) {
        continue;
      }
      final blank = cloze.blanks[i];
      final ok = scored && i < results.length ? results[i] : null;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _BlankField(
            key: currentSlot < blankKeys.length ? blankKeys[currentSlot] : null,
            slot: currentSlot,
            controller: controllers[i],
            focusNode: currentSlot < focuses.length
                ? focuses[currentSlot]
                : null,
            answer: blank.answer,
            hint: blank.hint,
            scored: scored,
            ok: ok,
            textStyle: textStyle,
            onSubmitted: onSubmitted,
          ),
        ),
      );
      // 判错后正确答案直接跟在空后面，保持文章流；不再另起一块。
      if (scored && ok == false) {
        spans.add(
          TextSpan(
            text: ' ${blank.answer}',
            style: TextStyle(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
    }
    return Text.rich(TextSpan(style: textStyle, children: spans));
  }
}

/// 一个空：行内下划线输入框，宽度按答案/提示的长度定。
///
/// 判分后保留用户填的内容（右侧跟红色正确答案），边框改成对/错颜色。
class _BlankField extends StatelessWidget {
  const _BlankField({
    super.key,
    required this.slot,
    required this.controller,
    required this.answer,
    required this.hint,
    required this.scored,
    required this.ok,
    required this.textStyle,
    this.focusNode,
    this.onSubmitted,
  });

  /// 第几个空位（按句子里的出现顺序，从 0 起）—— 只用来拼测试用的 key。
  final int slot;
  final TextEditingController controller;
  final String answer;
  final String? hint;
  final bool scored;
  final bool? ok;
  final TextStyle textStyle;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = scored
        ? (ok ?? false)
              ? theme.colorScheme.primary
              : theme.colorScheme.error
        : theme.colorScheme.outline;
    final width = _blankWidth(context, answer, hint);
    // 横向留一点白：连续两个空之间只有原文的一个空格（约 4px），
    // 两条下划线几乎连成一条，看上去像「一个空里塞了两个词」。
    // 每个空再让出 3px，重点是把相邻的空分开。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: SizedBox(
        width: width,
        child: TextField(
          key: ValueKey<String>('golden-blank-$slot'),
          controller: controller,
          focusNode: focusNode,
          enabled: !scored,
          textAlign: TextAlign.center,
          // 填的是英文原文里的词块：强制英文键盘（用户 2026-11-15 要求）。
          keyboardType: englishKeyboard,
          autocorrect: englishAutocorrect,
          enableSuggestions: englishSuggestions,
          // 回车 = 「交这一轮」（用户 2026-11-15 要求），不是跳到下一个空。
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted?.call(),
          // 关键：默认行为是「点到输入框外面就失焦」，而点**另一个空**
          // 正好满足「点到外面」—— 手指按下时旧空先失焦、textInput 排队
          // 隐藏，抬起后新空才要焦点，键盘就落下又弹起（用户 2026-11-15
          // 报的正是这个）。置空后旧空不失焦，新空直接接管连接。
          onTapOutside: (_) {},
          // 键盘刚要弹时 EditableText 先自己滚一次；留出足够边距，
          // 让它不会只露出半行。
          scrollPadding: const EdgeInsets.fromLTRB(24, 80, 24, 160),
          style: textStyle.copyWith(
            fontSize: (textStyle.fontSize ?? 16) - 1,
            height: 1.1,
            color: scored
                ? ((ok ?? false)
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error)
                : theme.colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            // 很淡的底色：连续的空挨在一起时，两块的边界一眼看得出来。
            fillColor: color.withValues(alpha: scored ? 0.10 : 0.05),
            contentPadding: const EdgeInsets.fromLTRB(2, 5, 2, 5),
            hintText: scored ? null : hint,
            hintStyle: TextStyle(
              fontSize: 10.5,
              height: 1,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
            hintMaxLines: 1,
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: color, width: 1.4),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 2.2,
              ),
            ),
            disabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: color, width: 2),
            ),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: color, width: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// 空的宽度：答案和提示谁宽取谁，再留一点余量，并夹在可点范围内。
///
/// 上限 190 是给 `uncharacteristically` 这类长词留的；下限 48 保证一个字母
/// 的词（`a` / `I`）也有手指按得中的宽度。超过上限的由输入框内部横向滚动。
double _blankWidth(BuildContext context, String answer, String? hint) {
  final scaler = MediaQuery.textScalerOf(context);
  double measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  final answerWidth = measure(
    answer,
    const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
  );
  final hintWidth = hint == null
      ? 0.0
      : measure(hint, const TextStyle(fontSize: 10.5));
  return (math.max(answerWidth, hintWidth) + 20).clamp(48.0, 190.0);
}

/// 这一轮的对错汇总。
class _RoundVerdict extends StatelessWidget {
  const _RoundVerdict({required this.results});

  final List<bool> results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allOk = goldenFillAllCorrect(results);
    final wrong = results.where((bool r) => !r).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: allOk
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        allOk ? '这一轮全对。' : '有 $wrong 个空不对，看一眼正确答案再重试。',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: allOk
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
