/// 随包的第三方许可声明。
///
/// `assets/tts/espeak/` 的数据和 `libespeak_native.so` 是 GPL v3；Flutter 自带的
/// 「开源许可」页只收 pub 包的 LICENSE，不会自动读这两个文件，所以这里手工
/// 注册。文本在用户点开许可页时才读，不占启动时间。
///
/// 单独成文件是为了能直接测：`test/services/third_party_licenses_test.dart`
/// 会调一次本函数，再从 `LicenseRegistry.licenses` 里把全文读回来。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 把 GPL v3 全文和 espeak-ng 声明接进 Flutter 的许可列表。
///
/// 在 `main()` 里、`runApp` 之前调用一次即可。
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    final notice = await rootBundle.loadString(
      'assets/licenses/espeak-ng-NOTICE.txt',
    );
    final gpl = await rootBundle.loadString('assets/licenses/GPL-3.0.txt');
    yield LicenseEntryWithLineBreaks(<String>['espeak-ng'], '$notice\n\n$gpl');
  });
}
