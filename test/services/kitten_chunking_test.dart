import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// KittenEngine 的切块与语速口径必须与官方实现一致。
///
/// 2026-11-17 踩过两个坑，听感上都是「元音不对」，但根因全在模型输入之外：
///
/// 1. **切的是音素串，而且是硬切**。旧代码先 `phonemizer.convert(整段)` 再用
///    `chunked(200)` 切音素 —— 200 个音素只对应约 180 个英文字符，一句话常常被
///    切成两块，块边界还会落在一个词中间（`compan|ies`），模型拿到残词，元音
///    自然就歪。官方 `chunk_text(text, max_len=400)` 切的是**原文**：按
///    `[.!?]+` 分句，句子超长再按词分，每块补标点。
/// 2. **语速传了 1.0**。官方 `_prepare_inputs` 有
///    `speed = speed * self.speed_priors[voice]`，而 `config.json` 里八个音色
///    的 prior 全是 0.8（`expr-voice-4-m` 是 0.9）。传 1.0 等于比训练分布快
///    25%，`sexual` 会被压成 "sex sell"。
///
/// 这两条都写在 Kotlin 里，跑不了单测，所以按源码常量钉死。
void main() {
  const engineFile = 'packages/neural_tts/android/src/main/kotlin/'
      'com/localmind/neural_tts/engines/KittenEngine.kt';
  const dartEngineFile = 'packages/neural_tts/lib/src/engines/kitten_engine.dart';
  const sessionFile = 'packages/neural_tts/android/src/main/kotlin/'
      'com/localmind/neural_tts/onnx/KittenSession.kt';

  /// 去掉注释后的 Kotlin 源码 —— 文件里有大段注释在讲这些坑，不剥掉会误判。
  String codeOf(String path) => File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*'), '');

  test('切块长度默认 400，不是 200', () {
    final code = codeOf(engineFile);
    expect(code.contains('maxChunkSize: Int = 400'), isTrue,
        reason: '默认值必须是官方的 400');
    expect(code.contains(r'args["maxChunkSize"] as? Int) ?: 400'), isTrue,
        reason: 'Dart 侧没传时也要落到 400');
    expect(code.contains('?: 200'), isFalse,
        reason: '200 是 Kokoro 那条路的口径，Kitten 不能再用');
  });

  test('切的是原文，不是先音素化再切', () {
    final code = codeOf(engineFile);
    // 必须先 chunk 原文，再在循环里逐块 convert。
    expect(code.contains('val chunks = chunkText(text)'), isTrue,
        reason: '要先按原文切块');
    expect(code.contains('val phonemized = if (isPhonemized) chunk else phonemizer.convert(chunk)'),
        isTrue,
        reason: '音素化必须发生在切块之后、逐块进行');
    expect(code.contains('phonemizer.convert(text)'), isFalse,
        reason: '不能再对整段先音素化再切');
    expect(code.contains('.chunked(maxChunkSize'), isFalse,
        reason: 'chunked() 是等长硬切，会切断词，官方不这么做');
  });

  test('style 行用这块原文的长度，不是音素串长度', () {
    expect(File(sessionFile).readAsStringSync().contains('refLength'), isTrue,
        reason: 'synthesize 要能收原文长度');
    final code = codeOf(sessionFile);
    expect(code.contains('minOf(refLen, embedMatrix.size - 1)'), isTrue,
        reason: '官方是 min(len(text), 399)，text 指原文');
    expect(codeOf(engineFile).contains('chunk.length'), isTrue,
        reason: '调用处要把原文块长传进去');
  });

  test('语速要乘 config.json 里的 speed_priors', () {
    final code = codeOf(engineFile);
    expect(code.contains('readSpeedPriors'), isTrue,
        reason: '不读 speed_priors 就会一直用 1.0，比训练分布快 25%');
    expect(code.contains('speedPriors[voiceId]'), isTrue,
        reason: '按音色取 prior');
    expect(code.contains('speed_priors'), isTrue);
    // Dart 侧得把 config.json 的路径传下去，否则读不到。
    expect(File(dartEngineFile).readAsStringSync().contains("'configPath'"), isTrue,
        reason: 'initializationArguments 要带 configPath');
  });

  test('config.json 里八个音色的 prior 确实是 0.8 量级', () {
    // 这是「传 1.0 就错了」的证据：官方默认语速从来不是 1.0。
    final config = File('assets/tts/kitten/config.json').readAsStringSync();
    expect(config.contains('"speed_priors"'), isTrue);
    final priors = RegExp(r'"expr-voice-[^"]+"\s*:\s*([0-9.]+)')
        .allMatches(config)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(priors.length, 8, reason: '八个音色都该有 prior');
    for (final p in priors) {
      expect(p, lessThan(1.0), reason: 'prior 必须 < 1.0，否则就是没在减速');
      expect(p, greaterThanOrEqualTo(0.5));
    }
  });

  test('Dart 侧的 chunk 常量与插件对齐', () {
    final constants =
        File('packages/neural_tts/lib/src/constants.dart').readAsStringSync();
    expect(constants.contains('const kittenMaxChunkSize = 400;'), isTrue);
    expect(
      File(dartEngineFile).readAsStringSync().contains("'maxChunkSize': kittenMaxChunkSize"),
      isTrue,
      reason: 'kitten_engine.dart 不能再用 Kokoro 那份 200 的 maxChunkSize',
    );
  });
}
