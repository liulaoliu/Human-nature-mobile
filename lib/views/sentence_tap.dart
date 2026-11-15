/// 句子的两种手势：点一下朗读、长按复制整句（精读与速读共用）。
///
/// 为什么抽出来：用户 2026-11-15 要求精读和速读「点句子朗读、长按复制」，
/// 两边要是各写一份，手感（长按多久、复制完提示什么、选词模式下让位给点词）
/// 迟早会走偏。这里只做手势与提示，朗读本身由各页的 ViewModel 提供。
///
/// 选词模式开着的时候**不接管**手势：那时点句子的语义是「点词」，
/// 由 `PickableSentence` 负责，调用方传 null 就退化成纯手势。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// 给一句正文包上「点=朗读 / 长按=复制」。
class SentenceTapRegion extends StatelessWidget {
  const SentenceTapRegion({
    super.key,
    required this.text,
    this.onSpeak,
    this.onTap,
    this.child,
    this.speakKey,
  });

  /// 整句原文（复制用它；朗读默认也用它）。
  final String text;

  /// 点一下要做什么（一般是朗读）。为 null 时不响应点击。
  final VoidCallback? onSpeak;

  /// 覆盖点击行为（精读里还要顺手选中这一句）。
  final VoidCallback? onTap;

  final Widget? child;

  /// 给点句手势挂 key（测试用 `sentence-<id>` 定位）。
  final Key? speakKey;

  @override
  Widget build(BuildContext context) {
    final child = this.child ?? Text(text);
    final tap = onTap ?? onSpeak;
    if (tap == null && text.trim().isEmpty) return child;
    return GestureDetector(
      key: speakKey,
      behavior: HitTestBehavior.opaque,
      onTap: tap,
      onLongPress: () => _copy(context),
      child: child,
    );
  }

  Future<void> _copy(BuildContext context) async {
    final raw = text.trim();
    if (raw.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: raw));
    messenger?.showSnackBar(
      const SnackBar(content: Text('已复制这一句'), duration: Duration(seconds: 1)),
    );
  }
}
