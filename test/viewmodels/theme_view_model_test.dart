// 主题 ViewModel：默认跟随系统、改了就通知、落盘能读回来、同值不通知。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/theme_prefs.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/theme/app_theme.dart' show themeModeOf;
import 'package:dlaoshi_app/viewmodels/theme_view_model.dart';

void main() {
  test('没注入 PrefsStore 也能用：默认跟随系统', () {
    final vm = ThemeViewModel();
    expect(vm.mode, AppThemeMode.system);
  });

  test('读回存着的值', () {
    final vm = ThemeViewModel(prefsStore: PrefsStore.memory({themeModeKey: 'dark'}));
    expect(vm.mode, AppThemeMode.dark);
  });

  test('改了就通知，并且落盘', () async {
    final store = PrefsStore.memory();
    final vm = ThemeViewModel(prefsStore: store);
    var notified = 0;
    vm.addListener(() => notified++);

    await vm.setMode(AppThemeMode.light);

    expect(vm.mode, AppThemeMode.light);
    expect(notified, 1);
    expect(store.loadThemeMode(), AppThemeMode.light);
  });

  test('同一个值不通知（避免白重建一次整棵树）', () async {
    final store = PrefsStore.memory();
    final vm = ThemeViewModel(prefsStore: store);
    var notified = 0;
    vm.addListener(() => notified++);

    await vm.setMode(AppThemeMode.system);
    expect(notified, 0);

    await vm.setMode(AppThemeMode.dark);
    await vm.setMode(AppThemeMode.dark);
    expect(notified, 1);
  });

  test('换个 ViewModel 能读回来（真的落了盘）', () async {
    final store = PrefsStore.memory();
    final a = ThemeViewModel(prefsStore: store);
    await a.setMode(AppThemeMode.light);

    final b = ThemeViewModel(prefsStore: store);
    expect(b.mode, AppThemeMode.light);
  });

  test('cycle 依次轮三个值，转回起点', () async {
    final vm = ThemeViewModel();
    final seen = <AppThemeMode>[vm.mode];
    for (var i = 0; i < AppThemeMode.values.length; i++) {
      await vm.cycle();
      seen.add(vm.mode);
    }
    expect(seen.first, seen.last);
    expect(seen.toSet().length, AppThemeMode.values.length);
  });

  test('themeModeOf 三个值一一对应（core 不许 import flutter，转换在主题层）', () {
    expect(themeModeOf(AppThemeMode.system), ThemeMode.system);
    expect(themeModeOf(AppThemeMode.light), ThemeMode.light);
    expect(themeModeOf(AppThemeMode.dark), ThemeMode.dark);
  });
}
