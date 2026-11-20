/// 拼写输入框：卡面拼写 / 组末拼写 / 锤炼拼写三处共用。
///
/// 抽出来的原因（用户 2026-11-20 的两条反馈，`docs/TODO.md` 34.3 / 34.4）：
///
/// 1. **键盘**：输入 `reve` 会弹 `revenge` 之类的候选，还会自动首字母大写。
///    光靠 [englishKeyboard]（`visiblePassword`）挡不住联想 —— 三处各写一遍时
///    组末拼写那处连 `keyboardType` 都没配，走的是默认键盘。配置收在一处，
///    以后就不会再漏。`textCapitalization: none` 关掉自动大写，
///    `smartDashes/smartQuotes` 关掉智能标点（拼写判分是大小写不敏感的，
///    但被改成弯引号会拼不出来）。
/// 2. **尺寸**：默认字号 + `OutlineInputBorder` 在单词卡的大留白里显得又小又挤。
///    改成 `headlineMedium`（28sp）+ 居中 + 无外框、只留一块浅色底；
///    纵向 padding 20 保证点击高度远超 56dp。长单词靠单行横向滚动，不换行。
library;

import 'package:flutter/material.dart';

import 'english_input.dart';

/// 拼写输入框。三处必须都用它，别各自再写一个 `TextField`。
class SpellingInput extends StatelessWidget {
  const SpellingInput({
    super.key,
    this.controller,
    this.autofocus = true,
    this.enabled = true,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
  });

  /// 可空：卡面拼写不需要自己读回文本（输入走 `onChanged`），
  /// 组末拼写要在判分后清空输入框，就传一个进来。
  final TextEditingController? controller;

  /// 进页面就聚焦：拼写是这一屏唯一的动作，省一次点击。
  final bool autofocus;

  /// 判分后锁住（锤炼拼错就不能再改）。
  final bool enabled;

  final String? hintText;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      // —— 34.3：拉丁键盘 + 关联想 + 关自动大写 ——
      keyboardType: englishKeyboard,
      autocorrect: englishAutocorrect,
      enableSuggestions: englishSuggestions,
      textCapitalization: TextCapitalization.none,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textInputAction: TextInputAction.done,
      // —— 34.4：大字、居中、无外框 ——
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: scheme.onSurface,
      ),
      cursorHeight: 32,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        hintText: hintText,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 2.2,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      ),
    );
  }
}
