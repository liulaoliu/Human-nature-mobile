import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonemize/phonemize.dart' as p;

/// 音素化产出 ↔ Kokoro tokenizer 的契约测试。
///
/// 2026-11-16 用户报「文章读音像德语」：`phonemize` 产出 `ɝ`（perfect）和
/// `ɫ`（global）这两个音标，而 `assets/tts/kokoro/tokenizer.json` 的 vocab 里
/// 没有它们 —— `KokoroSession.encode` 拿不到 id 就**静默跳过**，于是
/// `perfect` → `pfɪkt`、`global` → `ɡoʊbə`。文章里这两符号密度高，
/// 所以大片词听起来像外语；预览句只有一个是，不明显。
///
/// 修法是 `KokoroEngine.normalizePhonemes`（Kotlin，真机上跑的那个）在进
/// tokenizer 前做映射。这里把它复刻一份，好在**桌面**就守住契约：
/// 不需要 ONNX、不需要真机，`flutter test` 阶段就能红。
///
/// 注意：映射的**唯一权威**是
/// `packages/neural_tts/android/src/main/kotlin/com/localmind/neural_tts/engines/KokoroEngine.kt`
/// 的 `normalizePhonemes`；改动那边时这里要跟着改。
void main() {
  late Set<String> vocab;

  setUpAll(() {
    p.initDefaultProcessors();
    final json =
        jsonDecode(File('assets/tts/kokoro/tokenizer.json').readAsStringSync())
            as Map<String, dynamic>;
    final model = json['model'] as Map<String, dynamic>;
    final raw = model['vocab'] as Map<String, dynamic>;
    // 只收单字符串元：encode() 是逐 char 查表的。
    vocab = raw.keys.where((k) => k.runes.length == 1).toSet();
  });

  /// 复刻 `KokoroEngine.normalizePhonemes`。
  String mapToVocab(String ipa) {
    // 与 Kotlin 保持一致：顺序无关，都是单字符替换。
    const single = <String, String>{
      'ɫ': 'l',
      'ê': 'e', 'é': 'e', 'è': 'e', 'ë': 'e',
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ñ': 'n',
      'ç': 's',
      '’': "'", '‘': "'",
      '-': ' ', '–': ' ', '—': ' ', '[': ' ', ']': ' ',
      '【': ' ', '】': ' ', '（': ' ', '）': ' ', '|': ' ', '#': ' ',
    };
    final out = StringBuffer();
    for (final ch in ipa.split('')) {
      if (ch == 'ɝ') {
        out.write('ɜɹ'); // 美音 r 化；若太卷可改 ɜː
      } else {
        out.write(single[ch] ?? ch);
      }
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String ipaOf(String text) =>
      p.phonemize(text, language: 'en-us', stripStress: false, format: 'ipa');

  /// 模拟 `KokoroSession.encode` 的丢弃行为，返回被丢掉的字符。
  Set<String> droppedBy(String mapped) => {
        for (final ch in mapped.split(''))
          if (!vocab.contains(ch)) ch,
      };

  // 覆盖用户报障的三类：含 ɝ 的、含 ɫ 的、以及一段真实文章长句。
  const sentences = <String>[
    'Reading makes perfect.', // ɝ
    'The global economy has many ailments and few easy remedies.', // ɫ
    'A decade or so, when mainstream politicians such as Britain\'s '
        'David Cameron were petting huskies and embracing environmental issues.',
    'The first word was worth more than the third.', // ɝ 密集
    'Clear schools still hold old gold.', // ɫ 密集
  ];

  test('映射之后，一个字符都不会被 Kokoro tokenizer 丢掉', () {
    for (final s in sentences) {
      final mapped = mapToVocab(ipaOf(s));
      expect(droppedBy(mapped), isEmpty,
          reason: '这句映射后仍有字符不在 vocab：$s\nIPA=$mapped');
    }
  });

  test('不做映射时确实会丢字符 —— 证明这条测试不是空转', () {
    final allDropped = <String>{};
    for (final s in sentences) {
      allDropped.addAll(droppedBy(ipaOf(s)));
    }
    // 只要 espeak 还产 ɝ / ɫ，这里就不可能空；真变空了说明上游改了符号，
    // 那时要想的是「映射表是不是可以删了」，而不是让它悄悄失效。
    expect(allDropped, isNotEmpty);
  });

  test('未映射就被丢弃的字符只能是已知那两个（ɝ / ɫ）', () {
    // 守的是「phonemize 哪天开始吐新符号」：出现第三个字符就红，
    // 提醒往 KokoroEngine.normalizePhonemes 里补映射。
    final unknown = <String>{};
    for (final s in sentences) {
      unknown.addAll(droppedBy(ipaOf(s)));
    }
    expect(unknown.difference({'ɝ', 'ɫ'}), isEmpty,
        reason: '出现没被映射表覆盖的新音标，要补 KokoroEngine.normalizePhonemes：'
            '${unknown.difference({'ɝ', 'ɫ'})}');
  });

  test('映射用到的替换符号本身在 vocab 里（防止修法自己踩空）', () {
    // ɝ → ɜɹ 这两个符号必须存在，否则「修了还是一样怪」。
    for (final ch in ['ɜ', 'ɹ', 'l']) {
      expect(vocab.contains(ch), isTrue, reason: '$ch 不在 Kokoro vocab 里');
    }
  });
}
