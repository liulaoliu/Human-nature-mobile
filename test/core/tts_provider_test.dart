import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('档位与文案', () {
    test('四档都给了中文名和说明，顺序固定为 系统 → 离线两档 → 在线', () {
      expect(ttsProviders, <TtsProvider>[
        TtsProvider.system,
        TtsProvider.kitten,
        TtsProvider.kokoro,
        TtsProvider.edge,
      ]);
      for (final p in TtsProvider.values) {
        expect(ttsProviderLabel[p], isNotEmpty);
        expect(ttsProviderHint[p], isNotEmpty);
      }
    });

    test('只有 Edge 档标成需要联网', () {
      final infos = ttsProviderInfos;
      expect(infos.length, 4);
      expect(infos.first.offline, isTrue);
      expect(infos[1].offline, isTrue);
      expect(infos[2].offline, isTrue, reason: 'Kokoro 也是离线档');
      expect(infos.last.offline, isFalse);
    });
  });

  group('音色表', () {
    test('系统档没有音色可选', () {
      expect(ttsVoiceOptionsOf(TtsProvider.system), isEmpty);
      expect(defaultTtsVoice(TtsProvider.system), isNull);
    });

    test('离线档 8 个音色，默认第一个', () {
      expect(ttsVoiceOptionsOf(TtsProvider.kitten).length, 8);
      expect(
        defaultTtsVoice(TtsProvider.kitten),
        ttsVoiceOptionsOf(TtsProvider.kitten).first.id,
      );
    });

    test('Kokoro 离线档 6 个音色，默认 Heart，英式音也在表里', () {
      expect(ttsVoiceOptionsOf(TtsProvider.kokoro).length, 6);
      expect(defaultTtsVoice(TtsProvider.kokoro), 'af_heart');
      final ids = ttsVoiceOptionsOf(TtsProvider.kokoro).map((o) => o.id);
      expect(ids, containsAll(<String>['af_heart', 'bf_emma', 'bm_george']));
    });

    test('在线档默认 Aria，且都在列表里', () {
      expect(defaultTtsVoice(TtsProvider.edge), 'en-US-AriaNeural');
      final ids = ttsVoiceOptionsOf(TtsProvider.edge).map((o) => o.id);
      expect(ids, contains('en-US-AriaNeural'));
    });
  });

  group('parseTtsProvider', () {
    test('存的名字能读回来', () {
      for (final p in TtsProvider.values) {
        expect(parseTtsProvider(p.name), p);
      }
    });

    test('空 / 坏值 / 不认识都回系统档', () {
      expect(parseTtsProvider(null), TtsProvider.system);
      expect(parseTtsProvider(''), TtsProvider.system);
      expect(parseTtsProvider('piper'), TtsProvider.system);
      expect(parseTtsProvider(42), TtsProvider.system);
    });

    test('大小写与空白容错', () {
      expect(parseTtsProvider(' KITTEN '), TtsProvider.kitten);
    });
  });

  group('parseTtsVoice', () {
    test('本档的音色原样保留', () {
      expect(parseTtsVoice('expr-voice-3-m', TtsProvider.kitten), 'expr-voice-3-m');
      expect(parseTtsVoice('bf_emma', TtsProvider.kokoro), 'bf_emma');
      expect(parseTtsVoice('en-GB-RyanNeural', TtsProvider.edge), 'en-GB-RyanNeural');
    });

    test('换档后旧档的 id 认不出，退回本档默认', () {
      // 拿 Kitten 的 id 去喂 Edge
      expect(
        parseTtsVoice('expr-voice-3-m', TtsProvider.edge),
        defaultTtsVoice(TtsProvider.edge),
      );
      // 反方向同理
      expect(
        parseTtsVoice('en-US-AriaNeural', TtsProvider.kitten),
        defaultTtsVoice(TtsProvider.kitten),
      );
      // Kokoro 与 Kitten 的 id 也不相干（虽然都是 Kitten 风格的名字）
      expect(
        parseTtsVoice('expr-voice-3-m', TtsProvider.kokoro),
        defaultTtsVoice(TtsProvider.kokoro),
      );
    });

    test('空值给默认，系统档恒为 null', () {
      expect(parseTtsVoice(null, TtsProvider.kitten), defaultTtsVoice(TtsProvider.kitten));
      expect(parseTtsVoice('', TtsProvider.edge), defaultTtsVoice(TtsProvider.edge));
      expect(parseTtsVoice('anything', TtsProvider.system), isNull);
      expect(parseTtsVoice(null, TtsProvider.system), isNull);
    });
  });

  group('ttsVoiceLabel', () {
    test('认得出给中文名，认不出原样返回，空给「默认」', () {
      expect(ttsVoiceLabel(TtsProvider.kitten, 'expr-voice-2-f'), 'Bella · 女');
      expect(ttsVoiceLabel(TtsProvider.kokoro, 'bf_emma'), 'Emma · 英音女');
      expect(ttsVoiceLabel(TtsProvider.edge, 'en-US-AriaNeural'), 'Aria · 美音女');
      expect(ttsVoiceLabel(TtsProvider.edge, 'xx-Unknown'), 'xx-Unknown');
      expect(ttsVoiceLabel(TtsProvider.system, null), '默认');
    });
  });

  group('语速换算', () {
    test('神经引擎：0.45 → 0.95，0.5 → 1.0，1.0 → 1.5', () {
      expect(neuralRateOf(0.45), closeTo(0.95, 1e-9));
      expect(neuralRateOf(0.5), closeTo(1.0, 1e-9));
      expect(neuralRateOf(1.0), closeTo(1.5, 1e-9));
    });

    test('神经引擎夹在 0.5–1.8', () {
      expect(neuralRateOf(0), 0.5);
      expect(neuralRateOf(2), 1.8);
    });

    test('Edge：0.5 → +0%，0.45 → -10%，1.0 → +100%', () {
      expect(edgeRateOf(0.5), '+0%');
      expect(edgeRateOf(0.45), '-10%');
      expect(edgeRateOf(1.0), '+100%');
      expect(edgeRateOf(0.3), '-40%');
    });
  });
}
