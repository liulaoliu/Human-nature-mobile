import 'dart:io';

import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:dlaoshi_app/services/kitten_speech.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neural_tts/neural_tts.dart';

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

  test('语速接受 150%：1.5 原样保留，超过夹回全局上限', () async {
    final speech = KittenSpeech();
    await speech.setRate(1.5);
    expect(speech.rate, 1.5);
    await speech.setRate(9);
    expect(speech.rate, maxTtsRate);
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

  // 2026-11-17 的 bug：Kitten 读成 "reading makes fit"。第一版以为是喂了 Dart
  // `phonemize` 包算的 espeak **规则**音素（与真 espeak 逐字节只有 2.4% 一致），
  // 改成让引擎查自带 en-us.bin；后来发现引擎那本词典是**词级**的，与真 espeak
  // 的**句子级**输出也只有 36.8% 一致（功能词被塞主重音、没有连读），于是又改成
  // 在 Dart 侧用真 espeak-ng（`EspeakPhonemizer`）算，见下面的 `phonemeChunksFor`。
  // 但不管用哪套，引擎的 `expandDigits` 都是逐位替换（"30,000" → "three zero,
  // zero zero zero"），所以数字必须在 Dart 侧先变成单词 —— 这条守的就是这一步。
  group('送进引擎前的文本处理', () {
    test('数字展开成英文单词，不然引擎会逐位拆开', () {
      // 引擎的 expandDigits 会把 30000 拆成 "three zero zero zero zero"。
      expect(
        KittenSpeech.prepareText('The price went to 30000 megawatts.'),
        contains('thirty thousand'),
      );
      // 年代：normalizeTtsText 已把 1990s 补成 1990's，年份规则再把 1990
      // 读成 nineteen ninety（词典里有 nineties，'s 由引擎的所有格层处理）
      expect(
        KittenSpeech.prepareText("in the 1990's"),
        contains('nineteen ninety'),
      );
      expect(
        KittenSpeech.prepareText("in the 1990's"),
        isNot(contains('one thousand nine hundred')),
      );
      // 序数
      expect(KittenSpeech.prepareText('the 1st time'), contains('first'));
    });

    test('同时做了归一化（弯引号、破折号、缩写）', () {
      // normalizeTtsText 把 ’ 换成 '，再把 IMF 这类缩写展开成字母
      final out = KittenSpeech.prepareText("IMF's 2019 report");
      expect(out, isNot(contains('’')));
      expect(out, contains('twenty nineteen'));
    });

    test('空输入返回空串', () {
      expect(KittenSpeech.prepareText(''), '');
      expect(KittenSpeech.prepareText('   '), '');
    });
  });

  // espeak-ng 的数据：缺一个文件就是 `Espeak.init` 抛
  // `StateError('espeak_Initialize failed')`，表现出来是「点了没声音」。
  // 这份数据是从 numpy 版 espeakng-loader 的 18MB 里挑出来的英文子集。
  test('espeak 数据齐全，且 lang 整棵都在', () {
    const expected = <String, int>{
      'assets/tts/espeak/en_dict': 168204,
      'assets/tts/espeak/phondata': 554740,
      'assets/tts/espeak/phontab': 58652,
      'assets/tts/espeak/phonindex': 43316,
      'assets/tts/espeak/intonations': 2312,
      'assets/tts/espeak/phondata-manifest': 21866,
    };
    expected.forEach((path, size) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path 不见了');
      expect(file.lengthSync(), size, reason: '$path 大小与预期不符');
    });

    // 关键：`lang/gmw/en-US` 必须有 —— `espeak_SetVoiceByName('en-us')` 读的是
    // 这个文件，缺了会抛 `ArgumentError: Unknown voice: en-us`。
    // 2026-11-17 第一版只带了 `lang/{eu,ko,qu}`，真机上整个离线档直接不可用。
    for (final voice in const <String>[
      'lang/gmw/en-US', // en-us 的配置（phonemes en-us / dictrules）
      'lang/gmw/en', // en-gb 的配置
      'lang/eu',
      'lang/ko',
      'lang/qu',
    ]) {
      final file = File('assets/tts/espeak/$voice');
      expect(file.existsSync(), isTrue, reason: 'assets/tts/espeak/$voice 不见了');
      expect(file.lengthSync(), greaterThan(0));
    }
    expect(
      File('assets/tts/espeak/lang/gmw/en-US').readAsStringSync(),
      contains('language en-us'),
    );
  });

  test('lang 目录被整棵拷走（不是只拷几个列出来的文件）', () {
    // 安装逻辑改成扫 `AssetManifest`，所以 assets 里有多少个 lang 文件，
    // 就该拷多少个 —— 这里是「声明与实现一致」的守护。
    final langDir = Directory('assets/tts/espeak/lang');
    expect(langDir.existsSync(), isTrue);
    final onDisk = langDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.lengthSync() > 0)
        .length;
    // 官方全量是 33 个目录 141 个文件；少到这个数以下说明拷漏了。
    expect(onDisk, greaterThanOrEqualTo(141), reason: '实际 $onDisk 个');
    expect(espeakAssetsPrefix, 'assets/tts/espeak/');
  });

  test('phonemeChunksFor 按块给出音素与原文长度', () {
    // 真 espeak 在 Windows 上编不出来（`espeak` 包的 `hook/build.dart` 对
    // Windows 直接 return），所以这里用插件里现成的 `PassthroughPhonemizer`
    // （把原文当音素原样返回）来测「切块 → 逐块音素化 → 带 refLength」这段
    // 编排逻辑；真 espeak 本身留给真机集成测试。
    const fake = PassthroughPhonemizer();
    final chunks = KittenSpeech.phonemeChunksFor(
      'One thing. Two things!',
      fake,
    );
    expect(chunks, isNotNull);
    expect(chunks!.length, 2);
    // 每块的 refLength 必须是**这块原文**的字符数（官方取 style 行用原文长度，
    // 用音素串长度会系统性偏后十几行 —— 那是「元音被压扁」的老 bug 之一）。
    expect(chunks[0]['refLength'], 'One thing.'.length);
    expect(chunks[1]['refLength'], 'Two things!'.length);
    expect(chunks[0]['phonemes'], 'One thing.');
    expect(chunks[1]['phonemes'], 'Two things!');
    // 切不出有内容的块（纯标点）时返回 null，而不是把空音素喂给模型。
    expect(KittenSpeech.phonemeChunksFor('...', fake), isNull);
    // 没有音素器（测试环境、espeak 没起来）返回 null，让引擎走自己的老路。
    expect(KittenSpeech.phonemeChunksFor('One thing.', null), isNull);
  });
}
