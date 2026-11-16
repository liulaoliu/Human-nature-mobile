// 离线 Kokoro 档的「资源清单」检查：打进 APK 的文件必须和设置页给出的音色、
// 以及插件 `KokoroEngine.initializationArguments()` 要的路径一一对上。
// 这里不碰 ONNX、不碰 assets 读取 —— 那两件事只能在真机上跑
// `integration_test/tts_engine_test.dart` 取证。
import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:dlaoshi_app/services/kokoro_speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('模型 / tokenizer / 词典路径与插件要的一致', () {
    final paths = kokoroAssets.values.toSet();
    expect(paths, contains('kokoro/model.onnx'));
    expect(paths, contains('kokoro/tokenizer.json'));
    // 插件里 `KokoroEngine` 去 `<tts>/en-us.bin` 读音素词典，和 Kitten 共用。
    expect(paths, contains('en-us.bin'));
  });

  test('打包的音色与设置页的 6 个音色一一对应', () {
    final packed = kokoroAssets.values
        .where((String p) => p.startsWith('kokoro/voices/'))
        .map((String p) => p.split('/').last.replaceAll('.bin', ''))
        .toSet();
    final offered = kokoroVoiceOptions.map((o) => o.id).toSet();
    expect(packed, offered);
    expect(packed, hasLength(6), reason: '别把 22 个音色全打进 APK');
  });

  test('默认音色确实在打包列表里', () {
    final packed = kokoroAssets.values
        .where((String p) => p.startsWith('kokoro/voices/'));
    expect(packed, contains('kokoro/voices/${defaultTtsVoice(TtsProvider.kokoro)}.bin'));
  });
}
