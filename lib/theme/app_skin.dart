/// 皮肤（Skin）与皮肤化表面色（SkinColors）。
///
/// 为什么要有这一层：App 里有一批颜色不能直接从 `colorScheme` 推出来 ——
/// 卡片热度的三档绿黄橙、答案正确的绿、「浅绿那条」的边框。以前是写在
/// `views/study_card_view.dart` 里的字面量，浅色主题一上来就全糊了
/// （深色绿当浅色底、浅色绿当浅色字）。
///
/// 结构照 `I:\Examples\patrol_helper\lib\utils\app_skin.dart` 抄的形状：
///   - `enum AppSkin`：皮肤清单，每个皮肤带中文名与浅/深两个种子色；
///   - `SkinColors extends ThemeExtension`：皮肤自己的令牌，每个皮肤 ×
///     明暗各一份常量，经 `ThemeData.extensions` 注册；
///   - `SkinColors.of(context)`：**取不到时按明暗回落经典** ——
///     组件测试里常常只有一个裸 `MaterialApp(home: X())`，不能因此崩。
///
/// 现在只有一个皮肤（经典蓝）。加皮肤要做的事只有三件：
/// 1. 往 `AppSkin` 加一个值（带 label 与两个种子）；
/// 2. 往 `SkinColors` 加那份常量的两个变体（浅/深）；
/// 3. 在 `SkinColors.resolve` 与 `lib/theme/app_theme.dart` 的 switch 里各补一支。
/// 界面代码一行都不用改 —— 它们只认令牌名，不认皮肤名。
library;

import 'package:flutter/material.dart';

/// 经典蓝的浅色种子（= 原来 `main.dart` 里写死的那个色）。
const Color kClassicLightSeed = Color(0xFF3D7EFF);

/// 经典蓝的深色种子。比浅色种子压深压灰一点，深色底上不那么刺眼。
const Color kClassicDarkSeed = Color(0xFF5B8DEF);

/// 皮肤清单。
///
/// 以后加「墨绿」「护眼黄」「EVA」之类，都在这里加值，别在界面里散分支。
enum AppSkin {
  /// 经典蓝（现状默认）。
  classic('经典蓝');

  const AppSkin(this.label);

  /// 设置页显示的名字。
  final String label;

  /// 这个皮肤在浅色模式用的种子色。
  Color get lightSeed => switch (this) {
        AppSkin.classic => kClassicLightSeed,
      };

  /// 这个皮肤在深色模式用的种子色。
  Color get darkSeed => switch (this) {
        AppSkin.classic => kClassicDarkSeed,
      };
}

/// 皮肤化表面色令牌。
///
/// 只放「`ColorScheme` 推不出来、但又必须跟着主题走」的色。能由
/// `colorScheme.primary/error/outlineVariant` 推出的**不要**往这里加，
/// 令牌越多皮肤越难维护。
@immutable
class SkinColors extends ThemeExtension<SkinColors> {
  const SkinColors({
    required this.success,
    required this.successSurface,
    required this.heat1,
    required this.heat2,
    required this.heat3,
  });

  /// 表示成功 / 连接正常的绿（`ai_batch_page` 那两处）。
  final Color success;

  /// 成功色的浅底（选对答案的底色）。
  final Color successSurface;

  /// 卡片热度 1（停了有一会儿）的边框色。
  final Color heat1;

  /// 卡片热度 2（停得有点久）。
  final Color heat2;

  /// 卡片热度 3（快该锤炼了）。
  final Color heat3;

  /// 经典蓝 · 浅色。深色底的绿在浅色下太淡，这里换成压深的墨绿系。
  static const classicLight = SkinColors(
    success: Color(0xFF2E7D32),
    successSurface: Color(0xFFDCEFD0),
    heat1: Color(0xFF6E9B44),
    heat2: Color(0xFFB08A1E),
    heat3: Color(0xFFC4621F),
  );

  /// 经典蓝 · 深色（= 原来写在界面里的那三个字面量）。
  static const classicDark = SkinColors(
    success: Color(0xFF81C784),
    successSurface: Color(0xFF32491F),
    heat1: Color(0xFFCFE3B8),
    heat2: Color(0xFFE6C96A),
    heat3: Color(0xFFE08A3C),
  );

  /// 按皮肤与明暗取对应变体。
  static SkinColors resolve(AppSkin skin, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    switch (skin) {
      case AppSkin.classic:
        return dark ? classicDark : classicLight;
    }
  }

  /// 从主题里取当前皮肤的令牌；没注册（裸 `MaterialApp` 的组件测试）按明暗回落经典。
  static SkinColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SkinColors>() ??
        resolve(AppSkin.classic, theme.brightness);
  }

  @override
  SkinColors copyWith({
    Color? success,
    Color? successSurface,
    Color? heat1,
    Color? heat2,
    Color? heat3,
  }) {
    return SkinColors(
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      heat1: heat1 ?? this.heat1,
      heat2: heat2 ?? this.heat2,
      heat3: heat3 ?? this.heat3,
    );
  }

  /// 主题切换动画时不做插值：令牌是「语义色」，插到一半会出现
  /// 既不像旧皮肤也不像新皮肤的中间色，反而更晃眼。
  @override
  SkinColors lerp(SkinColors? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }

  @override
  bool operator ==(Object other) =>
      other is SkinColors &&
      other.success == success &&
      other.successSurface == successSurface &&
      other.heat1 == heat1 &&
      other.heat2 == heat2 &&
      other.heat3 == heat3;

  @override
  int get hashCode =>
      Object.hash(success, successSurface, heat1, heat2, heat3);
}
