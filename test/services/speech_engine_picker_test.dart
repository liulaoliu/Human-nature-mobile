// 挑朗读引擎：列表读到什么、存下来的名字装不装得回去、换引擎有没有落盘。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/ports.dart';
import 'package:dlaoshi_app/core/tts_engine.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/services/speech_engine_picker.dart';

/// 假引擎口：想给什么列表就给什么，记下被设过什么。
class _FakeEnginePort implements SpeechEnginePort {
  _FakeEnginePort([this.list = const <SpeechEngine>[]]);

  final List<SpeechEngine> list;
  final List<String?> applied = <String?>[];
  bool throwOnList = false;

  @override
  Future<List<SpeechEngine>> engines() async {
    if (throwOnList) throw StateError('读不到');
    return list;
  }

  @override
  Future<void> setEngine(String? name) async => applied.add(name);
}

const SpeechEngine _local = SpeechEngine(name: 'com.google.tts', label: 'Google');
const SpeechEngine _other = SpeechEngine(name: 'com.iflytek.tts', label: '讯飞');

void main() {
  group('没有引擎能力时', () {
    test('available 是 false，load / select 都不炸也不落盘', () async {
      final store = PrefsStore.memory();
      final picker = SpeechEnginePicker(port: null, store: store);

      expect(picker.available, isFalse);
      expect(picker.engines, isEmpty);
      expect(picker.selected, isNull);

      await picker.load();
      await picker.select('com.google.tts');

      expect(picker.engines, isEmpty);
      expect(picker.selected, isNull);
      expect(store.loadTtsEngine(), isNull);
    });
  });

  group('读列表', () {
    test('读到什么就存什么，没设过时选中是 null', () async {
      final picker = SpeechEnginePicker(
        port: _FakeEnginePort(const <SpeechEngine>[_local, _other]),
        store: PrefsStore.memory(),
      );

      await picker.load();

      expect(picker.available, isTrue);
      expect(picker.engines.map((e) => e.name),
          <String>['com.google.tts', 'com.iflytek.tts']);
      expect(picker.selected, isNull);
    });

    test('存过的引擎还装着：装回去', () async {
      final port = _FakeEnginePort(const <SpeechEngine>[_local, _other]);
      final store = PrefsStore.memory();
      await store.saveTtsEngine('com.iflytek.tts');
      final picker = SpeechEnginePicker(port: port, store: store);

      await picker.load();

      expect(picker.selected, 'com.iflytek.tts');
      expect(port.applied, <String?>['com.iflytek.tts']);
    });

    test('存过的引擎已卸载：退回系统默认，不去设一个装不上的名字', () async {
      final port = _FakeEnginePort(const <SpeechEngine>[_local]);
      final store = PrefsStore.memory();
      await store.saveTtsEngine('com.gone.tts');
      final picker = SpeechEnginePicker(port: port, store: store);

      await picker.load();

      expect(picker.selected, isNull);
      expect(port.applied, isEmpty);
    });
  });

  group('换引擎', () {
    test('选中、设给朗读器、写回本机，三件事一起做', () async {
      final port = _FakeEnginePort(const <SpeechEngine>[_local, _other]);
      final store = PrefsStore.memory();
      final picker = SpeechEnginePicker(port: port, store: store);

      await picker.select('com.google.tts');

      expect(picker.selected, 'com.google.tts');
      expect(port.applied, <String?>['com.google.tts']);
      expect(store.loadTtsEngine(), 'com.google.tts');
    });

    test('传 null 是选回系统默认：设 null、键也删掉', () async {
      final port = _FakeEnginePort(const <SpeechEngine>[_local]);
      final store = PrefsStore.memory();
      final picker = SpeechEnginePicker(port: port, store: store);
      await picker.select('com.google.tts');

      await picker.select(null);

      expect(picker.selected, isNull);
      expect(port.applied.last, isNull);
      expect(store.loadTtsEngine(), isNull);
    });

    test('换引擎会通知界面（设置页要重画下拉框）', () async {
      final picker = SpeechEnginePicker(
        port: _FakeEnginePort(const <SpeechEngine>[_local]),
        store: PrefsStore.memory(),
      );
      var calls = 0;
      picker.addListener(() => calls++);

      await picker.select('com.google.tts');

      expect(calls, 1);
    });
  });
}
