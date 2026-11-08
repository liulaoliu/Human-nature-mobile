// ============================================================
// check_layers.dart — 分层依赖方向门禁
//
// 规则（对应 AGENTS.md「目录」一节）：
//   R1  lib/core/ 不许 import flutter / sqflite / shared_preferences
//   R2  lib/core/ 不许 import lib/data、lib/viewmodels、lib/views、lib/widgets
//   R3  lib/data/ 不许 import lib/viewmodels、lib/views、lib/widgets
//   R4  lib/views/ 与 lib/widgets/ 不许直接 import sqflite
//
// 用法：dart run tool/check_layers.dart
//   退出码 0 = 通过；1 = 有违规（CI 门禁失败）
// ============================================================
// ignore_for_file: avoid_print

import 'dart:io';

const _coreForbiddenPackages = <String>[
  'package:flutter/',
  'package:sqflite/',
  'package:shared_preferences/',
];

const _upperLayers = <String>[
  '/data/',
  '/viewmodels/',
  '/views/',
  '/widgets/',
];

class _Violation {
  const _Violation(this.rule, this.file, this.detail);
  final String rule;
  final String file;
  final String detail;
}

void main() {
  final violations = <_Violation>[];
  final files = _dartFiles(Directory('lib'));

  for (final f in files) {
    final rel = _rel(f.path);
    for (final line in f.readAsLinesSync()) {
      final target = _importTarget(line);
      if (target == null) continue;
      violations.addAll(_check(rel, target));
    }
  }

  if (violations.isEmpty) {
    print('✅ 分层门禁通过：${files.length} 个源文件，依赖方向全部合规');
    return;
  }

  for (final v in violations) {
    print('❌ ${v.rule} ${v.file} → ${v.detail}');
  }
  exitCode = 1;
}

Iterable<_Violation> _check(String rel, String target) sync* {
  final inCore = rel.startsWith('lib/core/');
  final inData = rel.startsWith('lib/data/');
  final inView = rel.startsWith('lib/views/') || rel.startsWith('lib/widgets/');

  if (inCore) {
    for (final pkg in _coreForbiddenPackages) {
      if (target.startsWith(pkg)) {
        yield _Violation('R1', rel, target);
        return;
      }
    }
    for (final layer in _upperLayers) {
      if (target.contains(layer)) {
        yield _Violation('R2', rel, target);
        return;
      }
    }
  }

  if (inData) {
    for (final layer in ['/viewmodels/', '/views/', '/widgets/']) {
      if (target.contains(layer)) {
        yield _Violation('R3', rel, target);
        return;
      }
    }
  }

  if (inView && target.startsWith('package:sqflite/')) {
    yield _Violation('R4', rel, target);
  }
}

/// 抓 `import '...'` / `export '...'` 的路径，注释行返回 null。
String? _importTarget(String line) {
  final t = line.trim();
  if (t.startsWith('//')) return null;
  final m = RegExp(r"""^(?:import|export)\s+['"]([^'"]+)['"]""").firstMatch(t);
  return m?.group(1);
}

String _rel(String path) => path.replaceAll('\\', '/');

Iterable<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.contains('.dart_tool'))
    .where((f) => !f.path.endsWith('.g.dart') && !f.path.endsWith('.freezed.dart'));
