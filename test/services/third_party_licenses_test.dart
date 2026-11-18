// 许可页不是「把文件放进 assets 就完了」：还得真的注册进 Flutter 的
// LicenseRegistry。这里调一次注册，再把全文读回来，防止 main() 里那行被误删。
import 'package:dlaoshi_app/services/third_party_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('注册后能从 LicenseRegistry 读到 espeak-ng 的版权与 GPL 全文', () async {
    registerThirdPartyLicenses();
    final entries = await LicenseRegistry.licenses
        .where((e) => e.packages.contains('espeak-ng'))
        .toList();
    expect(entries, hasLength(1));
    final text = entries.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('Jonathan Duddington'));
    expect(text, contains('libespeak_native.so'));
    expect(text, contains('GNU GENERAL PUBLIC LICENSE'));
    expect(text, contains('Version 3, 29 June 2007'));
  });
}
