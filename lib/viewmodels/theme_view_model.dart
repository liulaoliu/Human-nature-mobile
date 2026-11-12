/// 主题（明暗模式）的 ViewModel。
///
/// 为什么不塞进 `StudyViewModel`：主题是全局外观，跟背单词没有半毛钱关系；
/// 塞进去以后任何一处想改主题都得把整个学习 VM 拖进依赖。
///
/// 落盘走 `PrefsStore`（键 `theme:mode`），值是枚举名不是序号 ——
/// 以后往 [AppThemeMode] 中间插值也不会让老用户的选择错位。
library;

import 'package:flutter/foundation.dart';

import '../core/theme_prefs.dart';
import '../data/prefs_store.dart';

/// 主题设置的状态。
class ThemeViewModel extends ChangeNotifier {
  /// [prefsStore] 传 null 时就是纯内存（组件测试、`smokeApp` 这种场合）。
  ThemeViewModel({PrefsStore? prefsStore}) : _store = prefsStore {
    _mode = _store?.loadThemeMode() ?? AppThemeMode.system;
  }

  final PrefsStore? _store;

  AppThemeMode _mode = AppThemeMode.system;

  /// 当前选的明暗模式。
  AppThemeMode get mode => _mode;

  /// 改明暗模式：先改内存 + 通知（界面立刻换色），再异步落盘。
  ///
  /// 顺序不能反 —— 落盘失败也不该让用户点了没反应。
  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _store?.saveThemeMode(mode);
  }

  /// 在三个值之间循环切换（给以后的快捷按钮留的口子，目前只有设置页用）。
  Future<void> cycle() {
    final next =
        AppThemeMode.values[(_mode.index + 1) % AppThemeMode.values.length];
    return setMode(next);
  }
}
