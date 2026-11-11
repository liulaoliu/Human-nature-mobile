// 备份页的 smoke：怎么用 / 导出 / 导入三张卡片与按钮文案。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/backup_page.dart';
import 'smoke_harness.dart';

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('BackupPage：标题、怎么用与导出 / 导入按钮', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const BackupPage()));

    expect(find.text('备份'), findsOneWidget);
    expect(find.text('怎么用'), findsOneWidget);
    expect(find.text('整库导出一个 JSON 文件。'), findsOneWidget);
    expect(find.text('导出并分享'), findsOneWidget);
    expect(find.text('合并导入'), findsOneWidget);
    expect(find.text('覆盖导入'), findsOneWidget);
    // debug 包多一张「导入内置样本」的开发卡片。
    expect(find.text('开发用'), findsOneWidget);
    expect(find.text('导入内置样本'), findsOneWidget);

    await smokeFinish(tester);
  });

  test('内置样本：文件在仓库里，且已在 pubspec 的 assets 里登记', () {
    // 只查「文件在不在、有没有被 pubspec 收进去」——
    // 真解析一次 33MB 要好几秒，而且 widget 测试里读大 asset 会卡在假异步上，
    // 所以「能不能导入」交给真机验收。
    //
    // 样本不进 git（见 assets/data/README.md），新克隆的仓库没有这个文件，
    // 这种情况下这条用例跳过，不算失败。
    final file = File(sampleBackupAsset);
    if (!file.existsSync()) {
      markTestSkipped('本机没有 $sampleBackupAsset，跳过');
      return;
    }
    expect(file.lengthSync(), greaterThan(30 * 1024 * 1024));

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('assets/data/'), isTrue,
        reason: 'pubspec.yaml 的 assets 里没登记 assets/data/');
  });
}
