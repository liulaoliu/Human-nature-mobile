import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 33.7：`apiKey` 存在 SharedPreferences（`lib/data/prefs_store.dart` 的 `ai:config`），
/// 系统级 Auto Backup / D2D 迁移默认会把它带出设备私有存储。应用自己有一套导出/导入
/// （备份页），换机用它，所以这里应该显式关掉系统备份。
///
/// 这条拦的是「有人在改 manifest 时顺手删掉一行」—— 删掉不会有任何编译/运行错误，
/// 只会在用户的下一台手机上悄悄多带走一把 key。
void main() {
  const manifest = 'android/app/src/main/AndroidManifest.xml';

  String manifestText() => File(manifest).readAsStringSync();

  /// 把注释剥掉再看，否则注释里出现的 `android:allowBackup` 会误判。
  String stripped() => manifestText()
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAll(RegExp(r'\n\s*\n'), '\n');

  test('主 manifest 显式关掉系统备份（allowBackup="false"）', () {
    final text = stripped();
    expect(
      text,
      contains('android:allowBackup="false"'),
      reason: 'Auto Backup 开着会把 SharedPreferences 里的 ai:config 带出去（33.7）',
    );
  });

  test('关掉备份这件事要写清理由，别人改的时候知道在做什么', () {
    expect(
      manifestText(),
      contains('ai:config'),
      reason: '注释里点名那个键，读的人才知道为什么不能开',
    );
  });
}
