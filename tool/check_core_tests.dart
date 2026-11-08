// ============================================================
// check_core_tests.dart — core 层「每个文件都要有同名测试」门禁
// ignore_for_file: avoid_print
//
// 为什么只盯 core：core 是纯领域逻辑，是这套 App 唯一能脱离手机单跑的部分，
// 也是从 Web 版逐函数搬过来的部分 —— 没有测试就没有「搬对了」的证据。
// （对应 Web 版 tool/check_architecture.mjs 的 R7）
//
// 规则：lib/core/<路径>/<名>.dart 必须存在 test/core/<路径>/<名>_test.dart
// 例外：`ports.dart` 这类纯接口声明可登记在 _allowNoTest（需写明理由）。
//
// 用法：dart run tool/check_core_tests.dart
//   退出码 0 = 通过；1 = 有缺失
// ============================================================

import 'dart:io';

/// 允许没有测试的 core 文件（相对 lib/core 的路径）。必须写理由。
const _allowNoTest = <String, String>{
  // 纯抽象端口声明，没有可执行逻辑（实现方在 data/repositories 里各自带测试）。
  'ports.dart': '纯接口声明',
};

void main() {
  final coreDir = Directory('lib/core');
  if (!coreDir.existsSync()) {
    print('❌ 找不到 lib/core');
    exitCode = 1;
    return;
  }

  final sources = _dartFiles(coreDir);
  final missing = <String>[];

  for (final f in sources) {
    final rel = _rel(f.path).replaceFirst('lib/core/', '');
    if (_allowNoTest.containsKey(rel)) continue;
    final expected = 'test/core/${rel.replaceFirst(RegExp(r'\.dart$'), '_test.dart')}';
    if (!File(expected).existsSync()) missing.add('$rel  →  缺 $expected');
  }

  if (missing.isEmpty) {
    print('✅ core 测试覆盖门禁通过：${sources.length} 个源文件都有同名测试'
        '（${_allowNoTest.length} 个例外已登记理由）');
    return;
  }

  for (final m in missing) {
    print('❌ $m');
  }
  print('共 ${missing.length} 个 core 文件缺测试。');
  exitCode = 1;
}

String _rel(String path) => path.replaceAll('\\', '/');

Iterable<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.contains('.dart_tool'))
    .where((f) => !f.path.endsWith('.g.dart') && !f.path.endsWith('.freezed.dart'));
