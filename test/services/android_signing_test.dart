import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 33.16：release 包不能用 debug 签名。
///
/// 诊断：`android/app/build.gradle.kts` 里原先写死
/// `signingConfig = signingConfigs.getByName("debug")`。自用包能装，但——
///   * debug key 每台机器不一样，换台机器重打就签不上同一个包（升级失败，
///     只能卸载重装、清数据）；
///   * 永远不能上架任何应用商店。
///
/// 现在的口径：**有 `android/key.properties` 就用正式签名，没有才退回 debug**。
/// 这里锁的是「别把那条写死的 debug 加回来」以及「材料别进 git」。
void main() {
  final File gradle = File('android/app/build.gradle.kts');
  final File gitignore = File('.gitignore');

  String codeLines(String text) => text
      // 注释里会解释「以前写死 debug」，先剥掉注释再判断，否则永远误报。
      .replaceAll(RegExp(r'//[^\n]*'), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

  group('release 签名（33.16）', () {
    test('signingConfig 不再无条件指向 debug', () {
      final String code = codeLines(gradle.readAsStringSync());
      final List<String> bad = code
          .split('\n')
          .where((String l) =>
              l.contains('signingConfig = signingConfigs.getByName("debug")'))
          .toList();
      expect(
        bad,
        isEmpty,
        reason: 'release 又被写死成 debug 签名了。要么走 key.properties，'
            '要么至少写成条件分支（见本文件顶部的口径）。',
      );
    });

    test('读 key.properties，且在文件不存在时能退回 debug', () {
      final String code = codeLines(gradle.readAsStringSync());
      expect(code, contains('key.properties'));
      expect(
        code,
        contains('hasReleaseKeystore'),
        reason: '需要一个「有没有正式签名材料」的判断，缺材料时不该直接构建失败',
      );
      expect(
        code,
        contains('signingConfigs.getByName("release")'),
        reason: '有材料时要用 release 那个 signingConfig',
      );
    });

    test('keystore 与 key.properties 都不进 git', () {
      final String text = gitignore.readAsStringSync();
      for (final String pattern in <String>[
        '/android/key.properties',
        '*.jks',
        '*.keystore',
      ]) {
        expect(
          text,
          contains(pattern),
          reason: '签名材料进 git 等于把口令公开；缺 $pattern',
        );
      }
    });

    test('仓库里确实没有签好的 keystore（材料只在开发机本地）', () {
      final Directory android = Directory('android');
      final List<String> found = <String>[];
      for (final FileSystemEntity e in android.listSync(recursive: true)) {
        if (e is! File) continue;
        final String name = e.uri.pathSegments.last;
        if (name.endsWith('.jks') || name.endsWith('.keystore')) {
          found.add(e.path);
        }
      }
      expect(found, isEmpty, reason: 'keystore 不能提交：${found.join(', ')}');
      expect(
        File('android/key.properties').existsSync(),
        isFalse,
        reason: 'key.properties 含明文口令，只该存在于开发机本地',
      );
    });

    test('示例文件在，别人照着能建出 key.properties', () {
      final File example = File('android/key.properties.example');
      expect(example.existsSync(), isTrue, reason: '缺 key.properties.example');
      final String text = example.readAsStringSync();
      for (final String key in <String>[
        'storeFile',
        'storePassword',
        'keyAlias',
        'keyPassword',
      ]) {
        expect(text, contains(key), reason: '示例里缺 $key 一行');
      }
      expect(
        text.contains('CHANGE_ME'),
        isTrue,
        reason: '示例里要写清占位符，别让人误以为那就是真口令',
      );
    });
  });
}
