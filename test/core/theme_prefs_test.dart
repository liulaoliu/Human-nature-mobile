// 明暗模式的偏好解析：三个枚举名、脏值兜底、往返。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/theme_prefs.dart';

void main() {
  group('parseThemeMode', () {
    test('三个枚举名都认得', () {
      expect(parseThemeMode('system'), AppThemeMode.system);
      expect(parseThemeMode('light'), AppThemeMode.light);
      expect(parseThemeMode('dark'), AppThemeMode.dark);
    });

    test('前后空白与大小写都不影响', () {
      expect(parseThemeMode('  Dark \n'), AppThemeMode.dark);
      expect(parseThemeMode('LIGHT'), AppThemeMode.light);
    });

    test('没存过回「跟随系统」', () {
      expect(parseThemeMode(null), AppThemeMode.system);
      expect(parseThemeMode(''), AppThemeMode.system);
      expect(parseThemeMode('   '), AppThemeMode.system);
    });

    test('存坏了回「跟随系统」而不是瞎猜', () {
      expect(parseThemeMode('blue'), AppThemeMode.system);
      expect(parseThemeMode('2'), AppThemeMode.system);
    });
  });

  group('themeModeStorage', () {
    test('落到盘上的是枚举名', () {
      expect(themeModeStorage(AppThemeMode.system), 'system');
      expect(themeModeStorage(AppThemeMode.light), 'light');
      expect(themeModeStorage(AppThemeMode.dark), 'dark');
    });

    test('存了再读回来是同一个值', () {
      for (final mode in AppThemeMode.values) {
        expect(parseThemeMode(themeModeStorage(mode)), mode);
      }
    });
  });

  group('标签与说明', () {
    test('三个值都有中文名，没有重复', () {
      expect(themeModeLabel.length, AppThemeMode.values.length);
      expect(themeModeLabel.values.toSet().length, AppThemeMode.values.length);
      expect(themeModeLabel[AppThemeMode.system], '跟随系统');
    });

    test('三个值都有说明', () {
      for (final mode in AppThemeMode.values) {
        expect(themeModeHint[mode], isNotEmpty);
      }
    });
  });
}
