/// 主题装配：把「皮肤 + 明暗」变成一份 `ThemeData`。
///
/// 分两层的原因（照 `I:\Examples\patrol_helper\lib\utils\app_theme.dart`）：
///   - `app_skin.dart` 管**颜色值**（皮肤令牌）；
///   - 这个文件管**怎么拼成主题**（`ColorScheme` 从哪个种子生成、
///     卡片/输入框的圆角、注册哪个 `ThemeExtension`）。
/// 加皮肤只动前者与这里的 switch，不改界面。
///
/// 浅色与深色必须是**两份** `ThemeData`，交给 `MaterialApp` 的
/// `theme` / `darkTheme` + `themeMode` 去选 —— 不要自己拿
/// `MediaQuery.platformBrightnessOf` 拼一次，那样系统切换时不会重建。
library;

import 'package:flutter/material.dart';

import '../core/theme_prefs.dart';
import 'app_skin.dart';

/// `core` 的 [AppThemeMode] → Flutter 的 [ThemeMode]。
///
/// 这一层转换只能放这儿：`lib/core/` 不许 import flutter（分层门禁 R1）。
ThemeMode themeModeOf(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

/// 主题工厂。
class AppTheme {
  const AppTheme._();

  /// 浅色主题。
  static ThemeData light({
    AppSkin skin = AppSkin.classic,
    Color? seedColor,
  }) =>
      _build(
        skin: skin,
        brightness: Brightness.light,
        seedColor: seedColor ?? skin.lightSeed,
      );

  /// 深色主题。
  static ThemeData dark({
    AppSkin skin = AppSkin.classic,
    Color? seedColor,
  }) =>
      _build(
        skin: skin,
        brightness: Brightness.dark,
        seedColor: seedColor ?? skin.darkSeed,
      );

  static ThemeData _build({
    required AppSkin skin,
    required Brightness brightness,
    required Color seedColor,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final skinColors = SkinColors.resolve(skin, brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return base.copyWith(
      // 卡片与输入框统一圆角：Material 3 默认值在几种容器上不一致，
      // 统一成 16 / 12 之后深色浅色看着是同一个 App。
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      extensions: <ThemeExtension<dynamic>>[skinColors],
    );
  }
}
