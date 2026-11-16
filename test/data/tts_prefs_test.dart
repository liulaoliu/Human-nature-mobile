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
      await prefs.saveProvider(TtsProvider.kokoro);
      expect(store.read(ttsProviderKey), 'kokoro');
      expect(prefs.loadProvider(), TtsProvider.kokoro);
    });

    test('老版本存下的 kitten 档：迁到 kokoro，而不是悄悄变系统朗读', () {
      final prefs = TtsPrefs(PrefsStore.memory({ttsProviderKey: 'kitten'}));
      expect(prefs.loadProvider(), TtsProvider.kokoro);
    });

    test('存坏了回系统档（永远可用的一档）', () {
      final prefs = TtsPrefs(PrefsStore.memory({ttsProviderKey: 'no-such'}));
      expect(prefs.loadProvider(), TtsProvider.system);
    });
  });

  group('音色', () {
    test('没存过：回这一档的默认音色', () {
      final prefs = TtsPrefs(PrefsStore.memory());
      expect(prefs.loadVoice(TtsProvider.kokoro), defaultTtsVoice(TtsProvider.kokoro));
      expect(prefs.loadVoice(TtsProvider.edge), defaultTtsVoice(TtsProvider.edge));
    });

    test('本档的音色存得住', () async {
      final prefs = TtsPrefs(PrefsStore.memory());
      await prefs.saveVoice('bf_emma');
      expect(prefs.loadVoice(TtsProvider.kokoro), 'bf_emma');
    });

    test('跨档的 id 退回这一档的默认（Kokoro 与 Edge 的 id 互不相干）', () async {
      final prefs = TtsPrefs(PrefsStore.memory());
      await prefs.saveVoice('en-GB-RyanNeural');
      expect(prefs.loadVoice(TtsProvider.edge), 'en-GB-RyanNeural');
      expect(
        prefs.loadVoice(TtsProvider.kokoro),
        defaultTtsVoice(TtsProvider.kokoro),
      );
    });

    test('老 Kitten 档的音色 id 在 Kokoro 档认不出，回默认', () async {
      final prefs = TtsPrefs(PrefsStore.memory());
      await prefs.saveVoice('expr-voice-5-m');
      expect(
        prefs.loadVoice(TtsProvider.kokoro),
        defaultTtsVoice(TtsProvider.kokoro),
      );
    });

    test('清空等于删键', () async {
      final store = PrefsStore.memory();
      final prefs = TtsPrefs(store);
      await prefs.saveVoice('bf_emma');
      await prefs.saveVoice('  ');
      expect(store.read(ttsVoiceKey), isNull);
      expect(
        prefs.loadVoice(TtsProvider.kokoro),
        defaultTtsVoice(TtsProvider.kokoro),
      );
    });
  });
}
