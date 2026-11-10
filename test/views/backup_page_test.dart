// 备份页的 smoke：怎么用 / 导出 / 导入三张卡片与按钮文案。
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

    await smokeFinish(tester);
  });
}
