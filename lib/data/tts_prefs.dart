/// 朗读相关的偏好读写（引擎 / 档位 / 音色）。
///
/// 为什么从 [PrefsStore] 里搬出来：三档朗读铺开之后，光朗读就有 6 个读写入口，
/// 全塞在 `PrefsStore` 里会把这个类顶过 40 个方法的门禁；而这六个方法本来
/// 就是一组的（都只碰 `tts:` 开头的三个键），单独成类反而更好找。
///
/// 只依赖 [PrefsStore] 的 read / write / remove 三个薄入口，可以单独测。
library;

import '../core/shadowing_prefs.dart' show legacyShadowingRateKey, readLegacyShadowingRate;
import '../core/tts_engine.dart';
import '../core/tts_provider.dart';
import 'prefs_store.dart';

/// 朗读偏好的读写口。
class TtsPrefs {
  const TtsPrefs(this._store);

  final PrefsStore _store;

  /// 读「用哪个朗读引擎」；null = 系统默认。
  ///
  /// 存的是引擎的包名（`com.google.android.tts` 这类）。存坏了 / 空串都当没选过。
  String? loadEngine() => readTtsEngine(_store.read(ttsEngineKey));

  /// 写「用哪个朗读引擎」；传 null / 空串 = 回系统默认（直接删键）。
  Future<void> saveEngine(String? name) async {
    final value = readTtsEngine(name);
    if (value == null) {
      await _store.remove(ttsEngineKey);
      return;
    }
    await _store.write(ttsEngineKey, value);
  }

  /// 读「用哪一档朗读」；没存过 / 存坏了都回系统档（永远可用）。
  TtsProvider loadProvider() => parseTtsProvider(_store.read(ttsProviderKey));

  /// 写「用哪一档朗读」（存枚举名，不存序号）。
  Future<void> saveProvider(TtsProvider provider) =>
      _store.write(ttsProviderKey, provider.name);

  /// 读「用哪个音色」；空 / 不属于这一档都回默认。
  ///
  /// 要和 [loadProvider] 一起用：Kitten / Kokoro / Edge 的音色 id 互不相干。
  String? loadVoice(TtsProvider provider) =>
      parseTtsVoice(_store.read(ttsVoiceKey), provider);

  /// 写「用哪个音色」；空 = 删键（回默认）。
  Future<void> saveVoice(String? voice) async {
    final value = voice?.trim() ?? '';
    if (value.isEmpty) {
      await _store.remove(ttsVoiceKey);
      return;
    }
    await _store.write(ttsVoiceKey, value);
  }

  /// 读某一档的语速；没存过 / 存坏了都回这一档的默认值。
  ///
  /// **每档一个键**（`tts:rate:system` / `tts:rate:kitten` …）：四档的刻度
  /// 不一样，Kitten 还额外乘一个 0.8 的音色先验，共用一个值会互相拖累。
  double loadRate(TtsProvider provider) =>
      parseTtsRate(_store.read(ttsRateKey(provider)), provider);

  /// 写某一档的语速（存的是 0–1 的小数，四舍五入到三位省得存一串浮点尾巴）。
  Future<void> saveRate(TtsProvider provider, double rate) {
    final value = rate.clamp(minTtsRate, maxTtsRateOf(provider));
    return _store.write(ttsRateKey(provider), value.toStringAsFixed(3));
  }

  /// 读老版本存在跟读页里的那个「跟读语速」（`shadowing.ui.speechRate`）。
  ///
  /// 只用来迁移一次：那个键当年会在跟读页 bootstrap 时**反向覆盖**全局语速，
  /// 是 33.2 那个「界面写 150%、声音还是 45%」的根源。现在语速只有
  /// [TtsViewModel] 一个写入方，旧值搬完就删。
  double? loadLegacyRate() =>
      readLegacyShadowingRate(_store.read(legacyShadowingRateKey));

  /// 把旧键的值搬到**系统档**，然后删掉旧键。
  ///
  /// 为什么搬系统档：旧滑块的上限就是 1.0（正好是系统档的刻度），而且当年
  /// 跟读「听标准音」默认走系统合成器。系统档已经存过新值时不覆盖 ——
  /// 新界面里调过的那个才是用户当下的意思。
  Future<void> adoptLegacyRate(double rate) async {
    final key = ttsRateKey(TtsProvider.system);
    if (_store.read(key) == null) {
      final value = rate.clamp(minTtsRate, maxTtsRateOf(TtsProvider.system));
      await _store.write(key, value.toStringAsFixed(3));
    }
    await _store.remove(legacyShadowingRateKey);
  }
}
