// 发版合规：espeak-ng 数据 / libespeak_native.so 是 GPL v3，必须随包带
// 全文和版权声明。跑在桌面上直接读仓库文件，不碰 Flutter 资源包。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GPL v3 全文在仓库里，且包含关键条款', () {
    final gpl = File('assets/licenses/GPL-3.0.txt').readAsStringSync();
    expect(gpl, contains('GNU GENERAL PUBLIC LICENSE'));
    expect(gpl, contains('Version 3, 29 June 2007'));
    expect(gpl, contains('TERMS AND CONDITIONS'));
    expect(gpl, contains('END OF TERMS AND CONDITIONS'));
    expect(gpl.length, greaterThan(30000), reason: '别拿一段摘要冒充全文');
  });

  test('espeak-ng 声明写了版权、来源和 GPL 版本', () {
    final notice = File(
      'assets/licenses/espeak-ng-NOTICE.txt',
    ).readAsStringSync();
    expect(notice.toLowerCase(), contains('espeak-ng'));
    expect(notice, contains('Jonathan Duddington'));
    expect(notice, contains('GNU General Public License'));
    expect(notice, contains('version 3'));
    expect(notice, contains('https://github.com/espeak-ng/espeak-ng'));
    expect(notice, contains('Human-nature-mobile'));
    // 数据目录和 .so 两个 GPL 载体都要点到，别只写一个。
    expect(notice, contains('libespeak_native.so'));
    expect(notice, contains('assets/tts/espeak/'));
  });

  test('pubspec 声明了 assets/licenses/，否则不会打进 APK', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/licenses/'));
  });
}
