// 33.8：系统合成引擎的选择要跟着 PickSpeech 走，别在切档时丢掉。
//
// 场景（用户报过的路径）：设置页选了「讯飞」→ 切到 Kokoro 档 → 再切回系统档，
// 重建出来的 `SystemSpeech` 要还是讯飞；降级兜底同理。
//
// 测试环境没有真的 TTS 插件，`SystemSpeech.setEngine` 会 catch 掉
// `MissingPluginException` 并把引擎退回 null —— 那样就验不出「记没记住」。
// 所以我们给 `flutter_tts` 的 method channel 装一个假实现，让 setEngine 成功。
import 'package:dlaoshi_app/core/ports.dart';
import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:dlaoshi_app/services/pick_speech.dart';
import 'package:dlaoshi_app/services/shadowing_speech.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  late List<String?> applied;

  setUp(() {
    applied = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'setEngine') {
        applied.add(call.arguments as String?);
      }
      return 1;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// 当前 delegate 如果是系统档，返回它记住的引擎名。
  String? engineOf(SpeechPort port) => port is SystemSpeech ? port.engine : null;

  test('选了引擎 B 再切档：切回系统档还是 B（33.8）', () async {
    final speech = PickSpeech(provider: TtsProvider.system);

    await speech.setEngine('com.iflytek.tts');
    expect(engineOf(speech.delegate), 'com.iflytek.tts');

    // 切到神经档再切回来 —— 重建 delegate 时不能把引擎选择丢掉。
    await speech.setProvider(TtsProvider.kokoro);
    await speech.setProvider(TtsProvider.system);

    expect(
      engineOf(speech.delegate),
      'com.iflytek.tts',
      reason: '切档不是「清空设置」：用户选过的合成引擎要跟着回来',
    );
  });

  test('换引擎会转发给当前 delegate（33.8）', () async {
    final speech = PickSpeech(provider: TtsProvider.system);

    await speech.setEngine('com.google.tts');
    expect(engineOf(speech.delegate), 'com.google.tts');
    expect(applied, contains('com.google.tts'));

    await speech.setEngine(null);
    expect(engineOf(speech.delegate), isNull, reason: 'null = 回系统默认');
  });

  test('非系统档时设引擎也记得住，切回系统档才生效（33.8）', () async {
    final speech = PickSpeech(provider: TtsProvider.kokoro);

    // 当前是 Kokoro，delegate 不是 SystemSpeech；设置只记着，不报错。
    await speech.setEngine('com.iflytek.tts');
    expect(engineOf(speech.delegate), isNull);

    await speech.setProvider(TtsProvider.system);
    expect(engineOf(speech.delegate), 'com.iflytek.tts');
  });

  test('降级兜底也用选过的引擎，不跳回系统默认（33.8）', () async {
    final speech = PickSpeech(provider: TtsProvider.kokoro);

    // 先在 Kokoro 档上设引擎（只记着），再让它降级。
    await speech.setEngine('com.iflytek.tts');
    await speech.speak('hello');

    expect(speech.fellBack, isTrue, reason: 'Kokoro 在测试环境没模型，必然降级');
    // 兜底那个 SystemSpeech 用的是同一个引擎选择。
    expect(
      applied.where((String? e) => e == 'com.iflytek.tts'),
      isNotEmpty,
      reason: '降级到系统朗读时应该用用户选的那个合成器',
    );
  });
}
