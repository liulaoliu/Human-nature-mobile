// 朗读偏好：引擎包名 / 档位 / 音色的读写口径（脏值都回默认，null 等于删键）。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/tts_engine.dart' show ttsEngineKey;
import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/tts_prefs.dart';

void main() {
  group('引擎包名', () {
    test('没存过：回 null（用系统默认）', () {
      final prefs = TtsPrefs(PrefsStore.memory());
      expect(prefs.loadEngine(), isNull);
    });

    test('存了再读：包名回来', () async {
      final prefs = TtsPrefs(PrefsStore.memory());
      await prefs.saveEngine('com.google.android.tts');
      expect(prefs.loadEngine(), 'com.google.android.tts');
    });

    test('传 null 等于回系统默认：键被删掉，不是存个空串', () async {
      final store = PrefsStore.memory();
      final prefs = TtsPrefs(store);
      await prefs.saveEngine('com.google.android.tts');
      await prefs.saveEngine(null);
      expect(prefs.loadEngine(), isNull);
      expect(store.read(ttsEngineKey), isNull);
      // 空串也当没选过（用户手清空输入框的情况）。
      await prefs.saveEngine('   ');
      expect(prefs.loadEngine(), isNull);
    });

    test('脏值（空串）当没设过', () {
      final prefs = TtsPrefs(PrefsStore.memory({ttsEngineKey: ''}));
      expect(prefs.loadEngine(), isNull);
    });
  });

  group('朗读档位', () {
    test('没存过：回系统档', () {
      final prefs = TtsPrefs(PrefsStore.memory());
      expect(prefs.loadProvider(), TtsProvider.system);
    });

    test('存的是枚举名，不是序号', () async {
      final store = PrefsStore.memory();
      final prefs = TtsPrefs(store);
      await prefs.saveProvider(TtsProvider.kitten);
      expect(store.read(ttsProviderKey), 'kitten');
      expect(prefs.loadProvider(), TtsProvider.kitten);
    });

    test('存坏了回系统档（永远可用的一档）', () {
      final prefs = TtsPrefs(PrefsStore.memory({ttsProviderKey: 'no-such'}));
      expect(prefs.loadProvider(), TtsProvider.system);
    });
  });

  group('语速', () {
    test('没存过：回这一档的默认值（Kitten 与别档不同）', () {
      final prefs = TtsPrefs(PrefsStore.memory());
      expect(prefs.loadRate(TtsProvider.system), 0.45);
      expect(prefs.loadRate(TtsProvider.kokoro), 0.45);
      expect(prefs.loadRate(TtsProvider.edge), 0.45);
      expect(prefs.loadRate(TtsProvider.kitten), 0.7);
      // 默认值本身要和 defaultTtsRateOf 一致，别两处各写一份。
      for (final p in TtsProvider.values) {
        expect(prefs.loadRate(p), defaultTtsRateOf(p));
      }
    });

    test('每档一个键：调一档不动别档', () async {
      final store = PrefsStore.memory();
      final prefs = TtsPrefs(store);
      await prefs.saveRate(TtsProvider.kitten, 0.8);
      expect(store.read(ttsRateKey(TtsProvider.kitten)), '0.800');
      expect(prefs.loadRate(TtsProvider.kitten), 0.8);
      // 别的档还是各自的默认值。
      expect(prefs.loadRate(TtsProvider.kokoro), 0.45);
      expect(prefs.loadRate(TtsProvider.edge), 0.45);
      expect(store.read(ttsRateKey(TtsProvider.kokoro)), isNull);
    });

    test('键名就是 tts:rate:<枚举名>', () {
      expect(ttsRateKey(TtsProvider.kitten), 'tts:rate:kitten');
      expect(ttsRateKey(TtsProvider.system), 'tts:rate:system');
    });

    test('写入时夹到 0.1–1.0', () async {
      final prefs = TtsPrefs(PrefsStore.memory());
      await prefs.saveRate(TtsProvider.kitten, 5);
      expect(prefs.loadRate(TtsProvider.kitten), 1.0);
      await prefs.saveRate(TtsProvider.kitten, -1);
      expect(prefs.loadRate(TtsProvider.kitten), 0.1);
    });

    test('脏值回该档默认，而不是卡在边界', () {
      final prefs = TtsPrefs(
        PrefsStore.memory({ttsRateKey(TtsProvider.kitten): 'abc'}),
      );
      expect(prefs.loadRate(TtsProvider.kitten), defaultTtsRateOf(TtsProvider.kitten));
      final out = TtsPrefs(
        PrefsStore.memory({ttsRateKey(TtsProvider.kitten): '9'}),
      );
      expect(out.loadRate(TtsProvider.kitten), defaultTtsRateOf(TtsProvider.kitten));
    });
  });

  group('音色', () {
    test('没存过：回这一档的默认音色', () {
      final prefs = TtsPrefs(PrefsStore.memory());
      expect(prefs.loadVoice(TtsProvider.kitten), defaultTtsVoice(TtsProvider.kitten));
      expect(prefs.loadVoice(TtsProvider.edge), defaultTtsVoice(TtsProvider.edge));
    });

    test('本档的音色存得住', () async {
      final prefs = TtsPrefs(PrefsStore.memory());
      await prefs.saveVoice('expr-voice-5-m');
      expect(prefs.loadVoice(TtsProvider.kitten), 'expr-voice-5-m');
    });

    test('跨档的 id 退回这一档的默认（Kitten 与 Edge 的 id 互不相干）', () async {
      final prefs = TtsPrefs(PrefsStore.memory());
      await prefs.saveVoice('en-GB-RyanNeural');
      expect(prefs.loadVoice(TtsProvider.edge), 'en-GB-RyanNeural');
      expect(
        prefs.loadVoice(TtsProvider.kitten),
        defaultTtsVoice(TtsProvider.kitten),
      );
    });

    test('清空等于删键', () async {
      final store = PrefsStore.memory();
      final prefs = TtsPrefs(store);
      await prefs.saveVoice('expr-voice-5-m');
      await prefs.saveVoice('  ');
      expect(store.read(ttsVoiceKey), isNull);
      expect(
        prefs.loadVoice(TtsProvider.kitten),
        defaultTtsVoice(TtsProvider.kitten),
      );
    });
  });
}
