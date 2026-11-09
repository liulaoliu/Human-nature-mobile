// 跟读模块本机偏好的用例（对应 Web 版 `src/state/shadowingPrefs.test.ts` 95 行）。
import 'package:dlaoshi_app/core/shadowing_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('跟读模块的本机偏好', () {
    test('没存过时全是默认值', () {
      expect(readShadowingViewMode(null), ShadowingViewMode.full);
      expect(readShadowingMicRaw(null), isTrue);
      expect(readShadowingMicDevice(null), '');
      expect(readShadowingHangover(null), 2500);
      expect(readShadowingTakeBoost(null), 2);
    });

    test('显示模式存得住，脏值回默认', () {
      expect(readShadowingViewMode('focus'), ShadowingViewMode.focus);
      expect(readShadowingViewMode('block'), ShadowingViewMode.block);
      expect(readShadowingViewMode('huge'), defaultShadowingPrefs.viewMode);
      expect(readShadowingViewMode(''), defaultShadowingPrefs.viewMode);
    });

    test('原声/降噪开关存成 1 和 0', () {
      expect(readShadowingMicRaw('0'), isFalse);
      expect(readShadowingMicRaw('1'), isTrue);
      // 脏值只要不是 '0' 就当开着（保守：原声优先）
      expect(readShadowingMicRaw('yes'), isTrue);
    });

    test('麦克风设备 id 存得住（空串表示系统默认）', () {
      expect(readShadowingMicDevice('mic-2'), 'mic-2');
      expect(readShadowingMicDevice(''), '');
    });

    test('静音判定时长：非数字、小于 0.8 秒的脏值都回 2500', () {
      expect(readShadowingHangover('4000'), 4000);
      expect(readShadowingHangover('abc'), defaultShadowingPrefs.hangoverMs);
      expect(readShadowingHangover('100'), defaultShadowingPrefs.hangoverMs);
      // 边界：正好 800 是合法的
      expect(readShadowingHangover('800'), 800);
      expect(readShadowingHangover('799'), defaultShadowingPrefs.hangoverMs);
    });

    test('回放放大倍数：小于 0.5 的脏值回 2（0 等于听不见了）', () {
      expect(readShadowingTakeBoost('3'), 3);
      expect(readShadowingTakeBoost('0.1'), defaultShadowingPrefs.takeBoost);
      // 边界：正好 0.5 是合法的
      expect(readShadowingTakeBoost('0.5'), 0.5);
      expect(readShadowingTakeBoost('0.49'), defaultShadowingPrefs.takeBoost);
    });

    test('一次读全：缺键 / 坏值各自回默认，不互相影响', () {
      final prefs = readShadowingPrefs(<String, String?>{
        shadowingViewModeKey: 'focus',
        shadowingHangoverKey: 'junk',
      });
      expect(prefs.viewMode, ShadowingViewMode.focus);
      expect(prefs.hangoverMs, 2500);
      expect(prefs.micRaw, isTrue);
      expect(prefs.micDevice, '');
      expect(prefs.takeBoost, 2);
    });

    test('空 map 等于什么都没存过', () {
      final prefs = readShadowingPrefs(const <String, String?>{});
      expect(prefs.viewMode, ShadowingViewMode.full);
      expect(prefs.hangoverMs, 2500);
      expect(prefs.takeBoost, 2);
    });

    test('toJson 的键名与 Web 版逐字一致', () {
      final json = const ShadowingPrefs().toJson();
      expect(json[shadowingViewModeKey], 'full');
      expect(json[shadowingMicRawKey], '1');
      expect(json[shadowingMicDeviceKey], '');
      expect(json[shadowingHangoverKey], '2500');
      expect(json[shadowingTakeBoostKey], '2.0');
    });

    test('toJson → readShadowingPrefs 往返不丢东西', () {
      const before = ShadowingPrefs(
        viewMode: ShadowingViewMode.block,
        micRaw: false,
        micDevice: 'mic-2',
        hangoverMs: 4000,
        takeBoost: 3,
      );
      final back = readShadowingPrefs(<String, String?>{
        for (final e in before.toJson().entries) e.key: e.value as String?,
      });
      expect(back.viewMode, ShadowingViewMode.block);
      expect(back.micRaw, isFalse);
      expect(back.micDevice, 'mic-2');
      expect(back.hangoverMs, 4000);
      expect(back.takeBoost, 3);
    });

    test('显示模式的循环顺序是 全文 → 聚焦 → 单块', () {
      expect(shadowingViewModes, <ShadowingViewMode>[
        ShadowingViewMode.full,
        ShadowingViewMode.focus,
        ShadowingViewMode.block,
      ]);
    });
  });
}
