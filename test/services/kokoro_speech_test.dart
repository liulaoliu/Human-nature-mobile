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
    // 插件里 `KokoroEngine` 去 `<tts>/en-us.bin` 读音素词典（phonemizer 共用一份）。
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

  test('资源版本标记非空：换模型后靠它让老安装整包重拷', () {
    // 2026-11-16：q8f16 输出全 NaN，换 int8 模型后，手机上那份旧模型还在
    // （installAssetsFromBundle 原来只看文件在不在），只能卸载重装。
    // 现在版本号一变就重拷，这条守着别把常量删空。
    expect(kokoroAssetsRevision.trim(), isNotEmpty);
    // 版本标记是运行时写的，不属于打包资源，别混进清单。
    expect(kokoroAssets.keys, isNot(contains('revision.txt')));
  });
}
