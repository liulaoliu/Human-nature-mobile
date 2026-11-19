// 朗读设置：档位 / 音色 / 语速三件事的编排口径。
//
// 重点是语速：用户 2026-11-17 要求「不同引擎分开，因为不同引擎设置不同」，
// 所以这里盯住三条 —— 每档各存一份、换档读回新档自己的值、Kitten 默认值不同。
//
// 2026-11-19（33.2）追加三条：旧键迁移、setRate 值没变也要推朗读器、
// 跟读页 bootstrap 不再反向覆盖全局语速。
import 'package:dlaoshi_app/core/shadowing_prefs.dart' show legacyShadowingRateKey;
import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/viewmodels/tts_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('语速按档分开', () {
    test('刚起来：用当前档的默认语速，并把它交给朗读器', () {
      final vm = TtsViewModel(prefsStore: PrefsStore.memory());
      expect(vm.provider, TtsProvider.system);
      expect(vm.rate, defaultTtsRateOf(TtsProvider.system));
      // 构造时就要把语速同步给朗读实现，否则第一次朗读还是引擎默认速度。
      expect(vm.speech.rate, vm.rate);
    });

    test('存过 Kitten 的语速：起来就用它（不是 0.45）', () {
      final vm = TtsViewModel(
        prefsStore: PrefsStore.memory({
          ttsProviderKey: 'kitten',
          ttsRateKey(TtsProvider.kitten): '0.800',
        }),
      );
      expect(vm.provider, TtsProvider.kitten);
      expect(vm.rate, 0.8);
      expect(vm.speech.rate, 0.8);
    });

    test('调语速：落盘、同步给朗读器，且只动这一档', () async {
      final store = PrefsStore.memory();
      final vm = TtsViewModel(prefsStore: store);

      await vm.setRate(0.6);
      expect(vm.rate, 0.6);
      expect(vm.speech.rate, 0.6);
      expect(store.read(ttsRateKey(TtsProvider.system)), '0.600');

      // 别的档不受影响：Kitten 的键没被写过，读出来还是它自己的默认 0.7。
      expect(store.read(ttsRateKey(TtsProvider.kitten)), isNull);
      expect(defaultTtsRateOf(TtsProvider.kitten), 0.7);
    });

    test('语速夹在该档上限：Kokoro 1.5 / 系统 1.0', () async {
      final store = PrefsStore.memory();
      final vm = TtsViewModel(prefsStore: store);
      // 系统档还是 1.0（flutter_tts 的安全上限）。
      await vm.setRate(9);
      expect(vm.rate, 1.0);

      await vm.setProvider(TtsProvider.kokoro);
      await vm.setRate(9);
      expect(vm.rate, 1.5);
      expect(vm.speech.rate, 1.5);
      expect(store.read(ttsRateKey(TtsProvider.kokoro)), '1.500');

      await vm.setRate(-3);
      expect(vm.rate, minTtsRate);
    });

    test('换档读回新档自己的语速，不沿用旧档', () async {
      final store = PrefsStore.memory({
        ttsRateKey(TtsProvider.system): '0.900',
        ttsRateKey(TtsProvider.kitten): '0.650',
      });
      final vm = TtsViewModel(prefsStore: store);
      expect(vm.rate, 0.9);

      await vm.setProvider(TtsProvider.kitten);
      expect(vm.rate, 0.65);
      expect(vm.speech.rate, 0.65);

      await vm.setProvider(TtsProvider.system);
      expect(vm.rate, 0.9);
      expect(vm.speech.rate, 0.9);
    });

    test('没存过的档换过去：用该档默认值（Kitten 是 0.7，不是 0.45）', () async {
      final vm = TtsViewModel(prefsStore: PrefsStore.memory());
      await vm.setProvider(TtsProvider.kitten);
      expect(vm.rate, 0.7);
      expect(vm.speech.rate, 0.7);
    });
  });

  group('档位与音色', () {
    test('换档会落盘，音色跟着换成新档的默认', () async {
      final store = PrefsStore.memory();
      final vm = TtsViewModel(prefsStore: store);
      await vm.setProvider(TtsProvider.edge);
      expect(store.read(ttsProviderKey), 'edge');
      expect(vm.voice, defaultTtsVoice(TtsProvider.edge));
    });

    test('换音色只影响当前档', () async {
      final store = PrefsStore.memory({ttsProviderKey: 'kitten'});
      final vm = TtsViewModel(prefsStore: store);
      await vm.setVoice(kittenVoiceOptions.last.id);
      expect(vm.voice, kittenVoiceOptions.last.id);
      expect(vm.voiceLabel, isNot('默认'));
    });

    test('跨档的脏音色回这一档的默认', () async {
      final vm = TtsViewModel(
        prefsStore: PrefsStore.memory({
          ttsProviderKey: 'edge',
          ttsVoiceKey: 'expr-voice-2-f', // Kitten 的 id，Edge 不认
        }),
      );
      expect(vm.voice, defaultTtsVoice(TtsProvider.edge));
    });
  });

  group('33.2 语速只有一个写入方', () {
    test('旧键（跟读语速）搬进系统档，然后删掉', () async {
      final store = PrefsStore.memory(<String, String>{
        legacyShadowingRateKey: '0.650',
      });
      final vm = TtsViewModel(prefsStore: store);
      // 迁移是异步的（构造里 unawaited），给它一个微任务。
      await Future<void>.delayed(Duration.zero);

      expect(store.read(ttsRateKey(TtsProvider.system)), '0.650');
      expect(store.read(legacyShadowingRateKey), isNull, reason: '旧键用完就删');
      expect(vm.provider, TtsProvider.system);
      expect(vm.rate, 0.65);
      expect(vm.speech.rate, 0.65, reason: '迁移完要真的推给朗读器');
    });

    test('系统档已经存过新值时，旧键不覆盖它', () async {
      final store = PrefsStore.memory(<String, String>{
        legacyShadowingRateKey: '0.650',
        ttsRateKey(TtsProvider.system): '0.900',
      });
      final vm = TtsViewModel(prefsStore: store);
      await Future<void>.delayed(Duration.zero);

      expect(vm.rate, 0.9, reason: '新值才是用户当下的意思');
      expect(store.read(ttsRateKey(TtsProvider.system)), '0.900');
      expect(store.read(legacyShadowingRateKey), isNull);
    });

    test('没存过旧键就什么都不做', () async {
      final store = PrefsStore.memory();
      final vm = TtsViewModel(prefsStore: store);
      await Future<void>.delayed(Duration.zero);
      expect(store.read(ttsRateKey(TtsProvider.system)), isNull);
      expect(vm.rate, defaultTtsRateOf(TtsProvider.system));
    });

    test('值没变也要推给朗读器（别处可能已经改过它）', () async {
      final store = PrefsStore.memory(<String, String>{
        ttsRateKey(TtsProvider.system): '0.600',
      });
      final vm = TtsViewModel(prefsStore: store);
      expect(vm.rate, 0.6);
      expect(vm.speech.rate, 0.6);

      // 模拟「跟读页/别处把共享朗读器的语速改成别的数」。
      await vm.speech.setRate(0.35);
      expect(vm.speech.rate, 0.35);

      // 用户在这里再拖到同一个值：必须推回去，否则声音还是 0.35。
      await vm.setRate(0.6);
      expect(vm.speech.rate, 0.6, reason: '33.2：不许因为「值没变」就不推');
    });
  });
}
