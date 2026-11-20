// 备份页的 smoke：怎么用 / 导出 / 导入三张卡片与按钮文案，外加一条真导入。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/learning.dart' show emptyLearning;
import 'package:dlaoshi_app/data/db/backup_export.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/views/backup_page.dart';
import 'smoke_harness.dart';

/// 假的文件选择器：只回一段内存里的 JSON，不弹系统对话框。
///
/// 必须 `extends FilePicker` 而不是 `implements` —— `FilePicker.platform` 的
/// setter 会 `PlatformInterface.verifyToken`，token 是父类构造函数私有的，
/// 只有 `extends` 才拿得到（官方注释里也要求平台实现用 extends）。
class _FakePicker extends FilePicker {
  _FakePicker(this.bytes);

  final Uint8List bytes;
  String? lastDialogTitle;
  List<String>? lastAllowedExtensions;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    lastDialogTitle = dialogTitle;
    lastAllowedExtensions = allowedExtensions;
    return FilePickerResult([
      PlatformFile(name: 'merged.json', size: bytes.length, bytes: bytes),
    ]);
  }
}

/// 造一份最小可用备份：一个词 + 一条学习记录键都没有。
String _tinyBackup() => encodeBackupJson(
      backupPayload(
        library: const VocabLibrary(items: [
          VocabItem(
            id: 'item-zephyr',
            word: 'zephyr',
            lemma: 'zephyr',
            meaning: '微风',
            createdAt: '2026-11-01T00:00:00.000Z',
            updatedAt: '2026-11-01T00:00:00.000Z',
          ),
        ]),
        learning: emptyLearning(),
        exportedAt: '2026-11-15T00:00:00.000Z',
      ),
    );

/// 测试环境里 `FilePicker.platform` 可能一次都没被初始化（没有插件注册），
/// 那时 getter 抛 `LateInitializationError`。这里只用来决定收尾要不要还原。
FilePicker? _currentPicker() {
  try {
    return FilePicker.platform;
  } on Error {
    return null;
  }
}

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

  testWidgets('合并导入：选的 JSON 真的合进库里，不是只弹一句提示', (tester) async {
    // 导入是破坏性操作，只验「按钮在不在」等于没验。这条用例把整条链走通：
    // 点「合并导入」→ 假选择器给字节 → 解析 → `mergeLibraries` → 落盘 → 卡片出现。
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final picked = _FakePicker(Uint8List.fromList(utf8.encode(_tinyBackup())));
    final original = _currentPicker();
    FilePicker.platform = picked;
    addTearDown(() {
      if (original != null) FilePicker.platform = original;
    });

    await smokePump(tester, smokeApp(db, const BackupPage()));
    expect(find.text('上一次导入'), findsNothing);

    await tester.tap(find.text('合并导入'));
    // 解析 + 合并 + 两次落盘都是真 IO：真时钟与假时钟交替推着走
    // （只在一侧等会互相死锁，见 study_page_test 里同款注释）。
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    // 选择器的参数也要对得上：只收 json、给的是合并语境。
    expect(picked.lastDialogTitle, '选一份备份：合并进来');
    expect(picked.lastAllowedExtensions, ['json']);

    final library = await tester.runAsync(smokeVocabRepo(db).load);
    expect(library, isNotNull);
    expect(library!.items.map((it) => it.word), contains('zephyr'));

    // 界面也得说清楚这次导入了什么。
    expect(find.text('上一次导入'), findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('覆盖导入的文案与行为一致：文章只覆盖文件里有的那几篇（33.14）', (tester) async {
    // 行为侧（`BackupService.replace`）是「词库 / 记录整份替换，文章逐篇写入、
    // 不删本机多出来的」，与 Web `onImportBackup` 一致。文案以前写「当前库里的
    // 东西不会留着」，把「文章也只增不删」这件事说成了「全清」—— 这条用例把
    // 改过的两处话锁住，免得下次又被改回「整份清空」。
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final picked = _FakePicker(Uint8List.fromList(utf8.encode(_tinyBackup())));
    final original = _currentPicker();
    FilePicker.platform = picked;
    addTearDown(() {
      if (original != null) FilePicker.platform = original;
    });

    await smokePump(tester, smokeApp(db, const BackupPage()));

    // 卡片上的「怎么用」要先说清覆盖导入到底覆盖什么。
    expect(find.textContaining('文章按 id 覆盖文件里有的那几篇'), findsOneWidget);

    await tester.tap(find.text('覆盖导入'));
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    // 二次确认弹窗：标题不再说「整份替换」，正文明确「本机多出来的会留着」。
    expect(find.text('按备份覆盖？'), findsOneWidget);
    expect(find.textContaining('本机多出来的会留着'), findsOneWidget);
    expect(find.textContaining('当前库里的东西不会留着'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pump();

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
