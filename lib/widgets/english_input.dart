/// 只收英文的输入框统一配置。
///
/// 为什么要单独抽出来：Android 的输入法会记住「上次用的语言」，用户上一处打了
/// 中文，下一次进填空 / 拷打就是中文键盘，得手动切回英文 —— 用户（2026-11-15）
/// 明确要求这些地方默认就是英文键盘。
///
/// 做法：`TextInputType.visiblePassword` 在 Android 上映射成
/// `TYPE_CLASS_TEXT | TYPE_TEXT_VARIATION_VISIBLE_PASSWORD`，输入法看到「密码类
/// 型」会切回自己的拉丁键盘并关掉联想候选（中文输入法没法在这种输入框上用拼写
/// 组合），比在 label 上写「请输入英文」有效得多。再配 `autocorrect: false` /
/// `enableSuggestions: false` 关掉系统纠错，免得填到一半被改成别的词。
library;

import 'package:flutter/services.dart';

/// 强制拉丁（英文）键盘的输入类型。
const TextInputType englishKeyboard = TextInputType.visiblePassword;

/// 英文输入框统一的「别纠错、别联想」配置。
///
/// 用法：`TextField(keyboardType: englishKeyboard, autocorrect: false,
/// enableSuggestions: false, ...)`。
const bool englishAutocorrect = false;

/// 见 [englishAutocorrect]：英文输入统一关联想。
const bool englishSuggestions = false;
