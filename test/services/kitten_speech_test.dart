import 'dart:io';

import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:dlaoshi_app/services/kitten_speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 我踩过的坑：`kittenAssets` 里的相对位置只要和插件
  // `KittenEngine.initializationArguments()` 要的对不上，真机上就是
  // 「模型拷过去了但引擎说找不到文件」，报错只会说 load 失败。
  // 这里把三处硬编码的路径钉死，改哪边都得先过这条。
  test('模型 / 音色 / 词典路径与插件要的一致', () {
    // 插件要：<support>/tts/kitten/kitten_tts_nano_v0_8.onnx
    //        <support>/tts/kitten/voices.npz
    //        <support>/tts/en-us.bin        （音素词典，与 Kokoro 共用）
    expect(kittenAssets.values, contains('kitten/kitten_tts_nano_v0_8.onnx'));
    expect(kittenAssets.values, contains('kitten/voices.npz'));
    expect(kittenAssets.values, contains('en-us.bin'));
    // config.json 插件不读（KittenEngine 只解析 args），但要跟着模型一起搬，
    // 免得将来上游开始读它时又缺文件。
    expect(kittenAssets.values, contains('kitten/config.json'));
  });

  test('打包的 8 个音色与设置页选项一一对应', () {
    // 插件里 kittenVoices 的 id 是 expr-voice-2-f 这种；
    // 设置页少一个就选不出来，多一个就是喂了无效 id。
    expect(kittenVoiceOptions.length, 8);
    final ids = kittenVoiceOptions.map((o) => o.id).toList();
    expect(ids.toSet().length, ids.length, reason: '音色 id 不能重复');
    for (final id in ids) {
      expect(id, startsWith('expr-voice-'));
    }
  });

  test('默认音色确实在设置页列表里', () {
    final fallback = defaultTtsVoice(TtsProvider.kitten);
    expect(fallback, isNotNull);
    expect(
      ttsVoiceOptionsOf(TtsProvider.kitten).map((o) => o.id),
      contains(fallback),
    );
  });

  // 这条守的是「assets 真的在仓库里」：文件被误删、被 .gitignore 吃掉、
  // 或者拉代码时没走 fetch 脚本，都会在这里红，而不是等真机上听不到声。
  test('asset 文件确实存在且大小对得上', () {
    // 单测在桌面跑，仓库根就是当前目录。
    const expected = <String, int>{
      'assets/tts/kitten/kitten_tts_nano_v0_8.onnx': 24369971,
      'assets/tts/kitten/voices.npz': 3278902,
      'assets/tts/en-us.bin': 3556124,
    };
    expected.forEach((path, size) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path 不见了');
      expect(file.lengthSync(), size, reason: '$path 大小与预期不符');
    });
    // config.json 上游改过几版，只查存在与非空。
    final config = File('assets/tts/kitten/config.json');
    expect(config.existsSync(), isTrue);
    expect(config.lengthSync(), greaterThan(0));
  });

  test('Kitten 与 Kokoro 的默认音色互不冲突', () {
    // 两档共用一份 en-us.bin，但音色 id 体系不同，跨档喂 id 会得到「未知音色」。
    final kitten = defaultTtsVoice(TtsProvider.kitten);
    final kokoro = defaultTtsVoice(TtsProvider.kokoro);
    expect(kitten, isNot(equals(kokoro)));
    expect(
      ttsVoiceOptionsOf(TtsProvider.kokoro).map((o) => o.id),
      isNot(contains(kitten)),
    );
  });
}
