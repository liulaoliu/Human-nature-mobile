import 'package:dlaoshi_app/core/tts_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSpeechEngines', () {
    test('正常列表：name + label 都取到', () {
      final engines = parseSpeechEngines(<Object?>[
        <String, Object?>{'name': 'com.google.android.tts', 'label': 'Google 语音服务'},
        <String, Object?>{'name': 'com.samsung.SMT', 'label': '三星 TTS'},
      ]);
      expect(engines, hasLength(2));
      expect(engines.first.name, 'com.google.android.tts');
      expect(engines.first.label, 'Google 语音服务');
    });

    test('label 缺失就用 name', () {
      final engines = parseSpeechEngines(<Object?>[
        <String, Object?>{'name': 'com.x.tts'},
      ]);
      expect(engines.single.label, 'com.x.tts');
    });

    test('不是列表 → 空表（界面只显示系统默认）', () {
      expect(parseSpeechEngines(null), isEmpty);
      expect(parseSpeechEngines('nope'), isEmpty);
      expect(parseSpeechEngines(<String, Object?>{}), isEmpty);
    });

    test('没有 name 的项跳过，非 Map 的项跳过', () {
      final engines = parseSpeechEngines(<Object?>[
        <String, Object?>{'label': '没有包名'},
        'just a string',
        42,
        <String, Object?>{'name': 'ok.tts', 'label': '好使的'},
      ]);
      expect(engines, hasLength(1));
      expect(engines.single.name, 'ok.tts');
    });

    test('name 是空白字符串也当没有', () {
      final engines = parseSpeechEngines(<Object?>[
        <String, Object?>{'name': '   '},
        <String, Object?>{'name': 'real.tts'},
      ]);
      expect(engines, hasLength(1));
    });

    test('同名只留第一条', () {
      final engines = parseSpeechEngines(<Object?>[
        <String, Object?>{'name': 'dup.tts', 'label': '先来的'},
        <String, Object?>{'name': 'dup.tts', 'label': '后来的'},
      ]);
      expect(engines, hasLength(1));
      expect(engines.single.label, '先来的');
    });

    test('返回的是不可变列表', () {
      final engines = parseSpeechEngines(<Object?>[
        <String, Object?>{'name': 'a.tts'},
      ]);
      expect(() => engines.add(const SpeechEngine(name: 'b', label: 'b')),
          throwsUnsupportedError);
    });
  });

  group('readTtsEngine', () {
    test('空 / 没存过 → null（= 系统默认）', () {
      expect(readTtsEngine(null), isNull);
      expect(readTtsEngine(''), isNull);
      expect(readTtsEngine('   '), isNull);
    });

    test('有值就 trim 后返回', () {
      expect(readTtsEngine('  com.google.android.tts '), 'com.google.android.tts');
    });
  });

  group('resolveTtsEngine', () {
    const engines = <SpeechEngine>[
      SpeechEngine(name: 'a.tts', label: 'A'),
      SpeechEngine(name: 'b.tts', label: 'B'),
    ];

    test('存的引擎还在列表里 → 用它', () {
      expect(resolveTtsEngine('b.tts', engines), 'b.tts');
    });

    test('引擎被卸载了 → 退回系统默认，不拿悬空名字去 setEngine', () {
      expect(resolveTtsEngine('gone.tts', engines), isNull);
    });

    test('没存过 → 系统默认', () {
      expect(resolveTtsEngine(null, engines), isNull);
    });

    test('列表空（老系统不给引擎表）→ 系统默认', () {
      expect(resolveTtsEngine('a.tts', const <SpeechEngine>[]), isNull);
    });
  });

  test('speechEngineLabel 给的是给人看的名字', () {
    expect(
      speechEngineLabel(const SpeechEngine(name: 'a.tts', label: '谷歌语音')),
      '谷歌语音',
    );
  });

  test('SpeechEngine 按 name + label 判等', () {
    expect(
      const SpeechEngine(name: 'a', label: 'A'),
      const SpeechEngine(name: 'a', label: 'A'),
    );
    expect(
      const SpeechEngine(name: 'a', label: 'A'),
      isNot(const SpeechEngine(name: 'a', label: 'B')),
    );
  });
}
