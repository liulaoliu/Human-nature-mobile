// 主题：设置页两级目录、皮肤页三选一、选完真的换色、落盘能读回来。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/core/theme_prefs.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/theme/app_skin.dart';
import 'package:dlaoshi_app/theme/app_theme.dart';
import 'package:dlaoshi_app/viewmodels/theme_view_model.dart';
import 'package:dlaoshi_app/views/settings_page.dart';
import 'package:dlaoshi_app/views/backup_page.dart';
import 'package:dlaoshi_app/views/speed_settings_page.dart';
import 'package:dlaoshi_app/views/study_settings_page.dart';
import 'package:dlaoshi_app/views/theme_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  Future<void> pumpSettings(
    WidgetTester tester, {
    ThemeViewModel? themeVm,
    required PrefsStore prefs,
  }) async {
    final db = await smokeOpenDb(tester);
    // smokeApp 会自己造一份 prefs / theme VM；要断言就把它传进去，
    // 否则内层 Provider 会遮住外层那一个（Provider 取最近的一个）。
    await smokePump(
      tester,
      smokeApp(
        db,
        const SettingsPage(),
        theme: themeVm ?? ThemeViewModel(prefsStore: prefs),
      ),
    );
  }

  testWidgets('设置页是目录：四个入口（背诵 / 速读 / 皮肤 / 备份），点进去才是具体项', (tester) async {
    smokeUseTallScreen(tester);
    await pumpSettings(tester, prefs: PrefsStore.memory());

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('背诵设置'), findsOneWidget);
    expect(find.text('速读设置'), findsOneWidget);
    expect(find.text('皮肤'), findsOneWidget);
    // 备份从首页搬到了这里（2026-11-13 用户要求）。
    expect(find.text('备份'), findsOneWidget);
    // 目录页上不该再有具体开关。
    expect(find.text('每组词数'), findsNothing);
    expect(find.text('深色'), findsNothing);
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-entry-study')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StudySettingsPage), findsOneWidget);
    expect(find.text('每组词数'), findsOneWidget);
    expect(find.text('朗读'), findsOneWidget);

    Navigator.of(tester.element(find.byType(StudySettingsPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // 退场动画没走完就点，命中的是正在淡出的那一层 —— 再等一帧。
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('settings-entry-speed')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SpeedSettingsPage), findsOneWidget);
    expect(find.text('语速'), findsOneWidget);
    expect(find.text('超时就拷打'), findsOneWidget);

    Navigator.of(tester.element(find.byType(SpeedSettingsPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('settings-entry-theme')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ThemePage), findsOneWidget);

    Navigator.of(tester.element(find.byType(ThemePage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('settings-entry-backup')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BackupPage), findsOneWidget);
    expect(find.text('导出'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('皮肤页：三个选项都在，点浅色就切过去并落盘', (tester) async {
    smokeUseTallScreen(tester);
    final store = PrefsStore.memory();
    final vm = ThemeViewModel(prefsStore: store);
    await pumpSettings(tester, themeVm: vm, prefs: store);

    await tester.tap(find.byKey(const ValueKey('settings-entry-theme')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(vm.mode, AppThemeMode.system);

    await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(vm.mode, AppThemeMode.light);

    // 落盘也走了（VM 里是 unawaited 之外的真 await，让出一次微任务即可）。
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(store.loadThemeMode(), AppThemeMode.light);

    await tester.tap(find.byKey(const ValueKey('theme-mode-dark')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(vm.mode, AppThemeMode.dark);

    await smokeFinish(tester);
  });

  testWidgets('主题真的换了：MaterialApp 的 themeMode 跟着 VM 走', (tester) async {
    final vm = ThemeViewModel();

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeViewModel>.value(
        value: vm,
        child: Consumer<ThemeViewModel>(
          builder: (BuildContext context, ThemeViewModel themeVm, Widget? _) {
            return MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: themeModeOf(themeVm.mode),
              home: const Scaffold(body: Text('内容')),
            );
          },
        ),
      ),
    );
    await tester.pump();

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app().themeMode, ThemeMode.system);
    expect(app().theme, isNotNull);
    expect(app().darkTheme, isNotNull);

    await vm.setMode(AppThemeMode.light);
    await tester.pump();
    expect(app().themeMode, ThemeMode.light);

    await vm.setMode(AppThemeMode.dark);
    await tester.pump();
    expect(app().themeMode, ThemeMode.dark);

    // 两个主题的底色不一样，否则「切了但看不出」。
    expect(
      app().theme!.colorScheme.surface,
      isNot(app().darkTheme!.colorScheme.surface),
    );
  });

  testWidgets('浅色和深色两套主题各自的皮肤令牌都注册上了', (tester) async {
    late SkinColors light;
    late SkinColors dark;
    await tester.pumpWidget(
      Column(
        children: [
          MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (BuildContext context) {
                light = SkinColors.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
          MaterialApp(
            theme: AppTheme.dark(),
            home: Builder(
              builder: (BuildContext context) {
                dark = SkinColors.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(light, SkinColors.classicLight);
    expect(dark, SkinColors.classicDark);
    // 浅色的成功色要比深色的深（白底上得压下去）。
    expect(light.heat1, isNot(dark.heat1));
  });
}
