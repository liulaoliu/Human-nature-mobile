// ============================================================
// check_god_class.dart — 上帝类（超大文件）体检门禁
// ignore_for_file: avoid_print  // CLI 工具用 print 输出结果
//
// 扫 lib/ 下全部 .dart（排除 codegen *.g.dart / *.freezed.dart），
// 按类体行数 / 方法数 / 字段数 / 注入仓库数 / 文件总行数判定。
// 阈值照搬 I:\Examples\patrol_helper 的工程约定（800 / 40 / 30 / 4）。
//
// 基线机制：存量超限登记在 _baseline（值=当前测得的最高指标），
// 允许存在但**禁止再增长**；新增超限必须拆或显式登记（登记即承认债务）。
// main.dart 的 DI 装配仓库数豁免（装配不属耦合）。
//
// 用法：dart run tool/check_god_class.dart
//   退出码 0 = 通过；1 = 有超限（CI 门禁失败）
// ============================================================

import 'dart:io';

const _maxLines = 800;
const _maxMethods = 40;
const _maxFields = 30;
const _maxRepos = 4;

/// 存量上帝类基线：file -> {kind: 允许的最高指标}。只准下调。
/// 目前为空 —— 新仓库从零开始，不许一上来就欠债。
const _baseline = <String, Map<String, int>>{};

class _Violation {
  const _Violation(this.file, this.kind, this.value, this.message);
  final String file;
  final String kind;
  final int value;
  final String message;
}

void main() {
  final violations = <_Violation>[];
  final files = _sourceFiles(Directory('lib'));

  for (final f in files) {
    final lines = f.readAsLinesSync();
    violations.addAll(_classViolations(f, lines));
    violations.addAll(_fileViolations(f, lines));
  }

  final normalized = violations.where((v) => !_isDiAssembly(v)).toList();
  if (normalized.isEmpty) {
    print('✅ 上帝类体检通过：${files.length} 个源文件，均未超限');
    return;
  }

  var failed = false;
  for (final v in normalized) {
    final key = v.file.replaceAll('\\', '/');
    final allowed = _baseline[key]?[v.kind];
    if (allowed != null && v.value <= allowed) {
      print('⚠️  已登记基线（未增长）：${v.file} ${v.message}');
      continue;
    }
    failed = true;
    print(allowed != null
        ? '❌ 存量超限且再增长：${v.file} ${v.message}（基线 $allowed，需拆分下调）'
        : '❌ 新增超限：${v.file} ${v.message}（新上帝类，需拆分或登记基线并说明）');
  }

  if (failed) {
    exitCode = 1;
  } else {
    print('✅ 上帝类体检通过：${files.length} 个源文件，'
        '无新增超限且存量未增长（${normalized.length} 处登记基线）');
  }
}

Iterable<File> _sourceFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) =>
        f.path.endsWith('.dart') &&
        !f.path.endsWith('.g.dart') &&
        !f.path.endsWith('.freezed.dart'))
    .where((f) => !f.path.contains('.dart_tool'));

/// main.dart 的 DI 装配：仓库作为 Provider 依赖传入是组装，不是类自身耦合。
bool _isDiAssembly(_Violation v) =>
    v.file.endsWith('main.dart') && v.kind == 'repos';

List<_Violation> _classViolations(File f, List<String> lines) {
  final result = <_Violation>[];
  final classDecl = RegExp(r'^class (\w+)');
  // 两空格缩进的「方法定义」行：返回值 + 名字 + 左括号。
  final methodDef = RegExp(r'^\s{2}(?:@override\s*)?'
      r'(?:Future<|Future |void |bool |int |double |String |List<|Map<|Set<|'
      r'Iterable<|DateTime|Stream<|dynamic |[A-Z][A-Za-z0-9_<>?, ]*\s+)\S*\(?');
  // 两空格缩进的字段行：`final X x` / `X x;` / `X? x = ...`。
  final fieldDef = RegExp(
      r'^\s{2}(?:static )?(?:final|var|late|const|[A-Z][A-Za-z0-9_<>?]*)\s+\w+\s*(?:=|;|,)');

  var i = 0;
  while (i < lines.length) {
    final m = classDecl.firstMatch(lines[i]);
    if (m == null || lines[i].trimLeft().startsWith('abstract class _')) {
      i++;
      continue;
    }
    var depth = 0;
    var end = i;
    for (var j = i; j < lines.length; j++) {
      depth += '{'.allMatches(lines[j]).length;
      depth -= '}'.allMatches(lines[j]).length;
      if (depth <= 0) {
        end = j;
        break;
      }
    }
    final body = lines.sublist(i, end + 1);
    final size = end - i + 1;
    final methods = body.where((l) => methodDef.hasMatch(l)).length;
    final fields = body.where((l) => fieldDef.hasMatch(l)).length;
    final repos = body
        .where((l) => l.contains('Repository)') || l.contains('Repository?'))
        .length;

    if (size > _maxLines) {
      result.add(_Violation(
          f.path, 'class', size, '类 ${m.group(1)} 行数 $size > $_maxLines'));
    }
    if (methods > _maxMethods) {
      result.add(_Violation(f.path, 'methods', methods,
          '类 ${m.group(1)} 方法数 $methods > $_maxMethods'));
    }
    if (fields > _maxFields) {
      result.add(_Violation(f.path, 'fields', fields,
          '类 ${m.group(1)} 字段数 $fields > $_maxFields'));
    }
    if (repos > _maxRepos) {
      result.add(_Violation(f.path, 'repos', repos,
          '类 ${m.group(1)} 注入仓库数 $repos > $_maxRepos'));
    }

    i = end + 1;
  }
  return result;
}

List<_Violation> _fileViolations(File f, List<String> lines) {
  if (lines.length <= _maxLines) return const [];
  return [
    _Violation(
        f.path, 'file', lines.length, '文件总行数 ${lines.length} > $_maxLines')
  ];
}
