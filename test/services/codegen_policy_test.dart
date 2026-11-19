import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守护 33.9 的决定：**模型有意不用 codegen**。
///
/// 以前 `AGENTS.md` 写着「模型一律 codegen（freezed + json_serializable）」，
/// 但仓库里 0 个 `*.freezed.dart` / `*.g.dart`，也没人 import 过那两个包 ——
/// 规范和代码是反的。33.9 选了「明确登记不用 codegen」这条路，理由写在
/// `AGENTS.md`「语言与类型」与 `docs/ARCHITECTURE.md` 第四节：
/// 全库 18 处 `identical(...)` 快路径依赖「内容没变就还是同一个对象」，
/// freezed 的值相等 `==` 与「copyWith 恒造新对象」会让这些语义漂移。
///
/// 这组用例是那条决定的可执行版本：谁把依赖加回来、或者谁开始写生成产物，
/// 这里就红，逼他先来改这份文档和理由。
void main() {
  final Directory root = Directory.current;
  final File pubspec = File('${root.path}/pubspec.yaml');

  /// 去掉 YAML 里的行注释与空行，避免「注释里提到 freezed」被误判。
  List<String> codeLinesOf(String text) => text
      .split('\n')
      .map((String line) => line.replaceFirst(RegExp(r'\s+#.*$'), ''))
      .where((String line) => line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
      .toList();

  group('模型不用 codegen（33.9 的决定）', () {
    test('pubspec 里没有 freezed / json_serializable / build_runner 的依赖', () {
      final List<String> lines = codeLinesOf(pubspec.readAsStringSync());
      // 只认「依赖声明行」的形状：以包名开头、后面跟冒号。
      const List<String> banned = <String>[
        'freezed',
        'freezed_annotation',
        'json_annotation',
        'json_serializable',
        'build_runner',
      ];
      for (final String pkg in banned) {
        final List<String> hits = lines
            .where((String line) => RegExp('^\\s*$pkg\\s*:').hasMatch(line))
            .toList();
        expect(
          hits,
          isEmpty,
          reason: 'pubspec.yaml 里又出现 $pkg 了。模型是否要改回 codegen 是个决策，'
              '不是顺手加个依赖 —— 先把 AGENTS.md 与 docs/ARCHITECTURE.md 的理由推翻。',
        );
      }
    });

    test('仓库里没有生成产物：*.freezed.dart / *.g.dart / build.yaml', () {
      final List<String> generated = <String>[];
      for (final String dir in <String>['lib', 'test', 'tool', 'integration_test', 'packages']) {
        final Directory d = Directory('${root.path}/$dir');
        if (!d.existsSync()) continue;
        for (final FileSystemEntity e in d.listSync(recursive: true)) {
          if (e is! File) continue;
          final String name = e.uri.pathSegments.last;
          if (name.endsWith('.freezed.dart') || name.endsWith('.g.dart')) {
            generated.add(e.path);
          }
        }
      }
      expect(
        generated,
        isEmpty,
        reason: '出现了 codegen 生成的文件。要么删掉它，要么先把「不用 codegen」这个决定改掉。',
      );
      expect(
        File('${root.path}/build.yaml').existsSync(),
        isFalse,
        reason: 'build.yaml 是 build_runner 的配置；不用 codegen 就不该有这个文件。',
      );
    });

    test('lib/models 里没有 JSON 处理：映射都在 lib/core/*_json.dart', () {
      final Directory models = Directory('${root.path}/lib/models');
      expect(models.existsSync(), isTrue);
      final List<String> offenders = <String>[];
      for (final FileSystemEntity e in models.listSync()) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final String text = e.readAsStringSync();
        for (final String needle in <String>[
          "import 'dart:convert'",
          'jsonEncode(',
          'jsonDecode(',
        ]) {
          if (text.contains(needle)) {
            offenders.add('${e.uri.pathSegments.last}: $needle');
          }
        }
      }
      // 例外：ListeningQuestion 自己带一个 toJson / fromJson（历史遗留，见 33.9 记录）。
      // 那不是 codegen 的入口，也不做 encode/decode，所以只拦 dart:convert 与 jsonEncode。
      expect(
        offenders.where((String s) => !s.contains('listening.dart')).toList(),
        isEmpty,
        reason: 'lib/models 是纯数据，不该自己 encode/decode。JSON 映射放 lib/core/*_json.dart。',
      );
    });

    test('lib/core 里确实有四份手写映射（别删了它们又忘了加回来）', () {
      for (final String path in <String>[
        'lib/core/article_json.dart',
        'lib/core/vocab/vocab_json.dart',
        'lib/core/writing_json.dart',
        'lib/core/writing_record_json.dart',
      ]) {
        expect(
          File('${root.path}/$path').existsSync(),
          isTrue,
          reason: '$path 是模型的手写映射，不是生成物。删了它模型就没法持久化了。',
        );
      }
      // 抽查一眼映射确实是「手写」的 JSON 字面量，而不是转发给什么生成器。
      final String vocabJson =
          File('${root.path}/lib/core/vocab/vocab_json.dart').readAsStringSync();
      expect(vocabJson.contains('jsonEncode'), isTrue);
      expect(utf8.encode(vocabJson).isNotEmpty, isTrue);
    });
  });
}
