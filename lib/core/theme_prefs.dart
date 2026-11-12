/// 明暗模式（皮肤）的偏好：三个值的闭集 + 字符串往返。
///
/// 为什么不在 core 里直接用 `ThemeMode`：core 不许 import flutter
/// （`tool/check_layers.dart` 的 R1），而这一层只管「读回来的脏值怎么洗」。
/// 映射到 `ThemeMode` 的那一步在 `lib/theme/app_theme.dart` 里做。
///
/// 以后加皮肤（配色方案）不在这里：这里是**明暗**，皮肤是那一套配色，
/// 两者正交 —— 一个皮肤要有浅色和深色两版，所以键也分开存。
library;

/// 主题模式：跟随系统 / 浅色 / 深色。
///
/// 默认 [system]：用户没表过态就跟手机走，这是对「大半夜被白屏闪一下」最友好的默认。
enum AppThemeMode { system, light, dark }

/// 存明暗模式的键。
const String themeModeKey = 'theme:mode';

/// 三个选项的中文名（设置页直接用）。
const Map<AppThemeMode, String> themeModeLabel = {
  AppThemeMode.system: '跟随系统',
  AppThemeMode.light: '浅色',
  AppThemeMode.dark: '深色',
};

/// 每个选项的一句话说明（设置页副标题）。
const Map<AppThemeMode, String> themeModeHint = {
  AppThemeMode.system: '手机切到深色它也跟着切',
  AppThemeMode.light: '白底黑字，白天户外更清楚',
  AppThemeMode.dark: '黑底，晚上不刺眼（一直是这个）',
};

/// 读回存着的明暗模式；没存过 / 存坏了都回 [AppThemeMode.system]。
///
/// 只认枚举名（`system` / `light` / `dark`），认不出就回默认 ——
/// 存的是名字不是序号，以后往枚举中间插值也不会错位。
AppThemeMode parseThemeMode(String? raw) {
  final text = (raw ?? '').trim().toLowerCase();
  for (final mode in AppThemeMode.values) {
    if (mode.name == text) return mode;
  }
  return AppThemeMode.system;
}

/// 落盘用的字符串。
String themeModeStorage(AppThemeMode mode) => mode.name;
