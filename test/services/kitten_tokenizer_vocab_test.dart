import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kitten 的 tokenizer 词汇表必须与训练时**逐字符**一致。
///
/// 2026-11-17 踩过的坑：`Tokenizer.kt` 里手抄的那张表用了中文弯引号 `“”`
/// 代替直引号/撇号，又把 `'`(U+0027) + `̩`(U+0329) 写成 `\u0301`，
/// 于是 `"` 的 id 从 15 变成 11、`ᵻ` 从 177 变成 176 —— 之后所有 token
/// 全部错位，模型收到训练分布外的 id。听感上的表现是「辅音对、元音怪」：
/// `companies` 的 `ʌ`、`introverts` 的 `ə`、`discriminating` 的 `ᵻ` 都不对。
///
/// 这条测试把官方表钉死，改 Kotlin 常量会立刻红。
void main() {
  /// 官方 `kittentts` pip 包（v0.1.3）`KittenTTS.__init__` 里那张表，178 项。
  ///
  /// ```python
  /// {symbol: i for i, symbol in enumerate(list(
  ///   '$;:,.!?¡¿—…"«»""' ' ABC…xyz' 'ɑɐɒ…ʢ' 'ǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘\'̩\'ᵻ'))}
  /// ```
  const official =
      "\$;:,.!?¡¿—…\"«»\"\" ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      "abcdefghijklmnopqrstuvwxyz"
      "ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘɹɺɾɻʀʁɽʂʃʈʧʉʊʋ"
      "ⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢ"
      "ǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘'\u0329'ᵻ";

  const tokenizerFile =
      'packages/neural_tts/android/src/main/kotlin/'
      'com/localmind/neural_tts/phonemizer/Tokenizer.kt';

  /// 从 Kotlin 源码里抠出 `SYMBOLS` 常量，按 Kotlin 转义规则还原。
  String readSymbolsFromKotlin(String source) {
    final start = source.indexOf('const val SYMBOLS =');
    expect(start, greaterThanOrEqualTo(0), reason: 'Kotlin 里找不到 SYMBOLS 常量');
    final rest = source.substring(start);
    final end = rest.indexOf('/** 官方');
    expect(end, greaterThan(0), reason: '找不到 SYMBOLS 常量的结尾');
    final block = rest.substring(0, end);

    final parts = <String>[];
    final literal = RegExp(r'"((?:[^"\\]|\\.)*)"');
    for (final m in literal.allMatches(block)) {
      parts.add(_unescapeKotlin(m.group(1)!));
    }
    return parts.join();
  }

  test('Kotlin 的 SYMBOLS 与官方 vocab 逐字符一致', () {
    final source = File(tokenizerFile).readAsStringSync();
    final ours = readSymbolsFromKotlin(source);

    expect(ours.length, official.length,
        reason: '表长不对：官方 ${official.length} 项，我们 ${ours.length} 项');
    for (var i = 0; i < official.length; i++) {
      expect(ours[i], official[i],
          reason: '第 $i 位不一致：官方 ${_describe(official[i])}，'
              '我们 ${_describe(ours[i])}');
    }
  });

  test('重复字符取最后出现的位置（与 Python dict 一致）', () {
    // Python 的 `{s: i for i, s in enumerate(seq)}` 遇到重复 key 时后面的覆盖前面的。
    // Kotlin 侧靠 `forEachIndexed` 覆盖写实现，改成 putIfAbsent 就会错位。
    final byChar = <String, int>{};
    for (var i = 0; i < official.length; i++) {
      byChar[official[i]] = i;
    }
    // 这四个是「抄错了就听得出」的锚点。
    expect(byChar['"'], 15, reason: '直引号 " 应该是 15（表里出现 3 次）');
    expect(byChar["'"], 176, reason: '撇号 \' 应该是 176（出现 2 次）');
    expect(byChar['\u0329'], 175, reason: 'combining vertical line below 是 175');
    expect(byChar['ᵻ'], 177, reason: 'ᵻ 是 177 —— 它是 discriminating 这类词的弱化元音');
  });

  test('Kotlin 建表用的是覆盖写，不是「不存在才写」', () {
    // 只看代码，不看注释 —— 文件里正好有一段注释在讲「别改成 putIfAbsent」。
    final code = File(tokenizerFile)
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//.*'), '');
    expect(code.contains('vocab[char.toString()] = idx'), isTrue,
        reason: '建表必须让后出现的下标覆盖前面的，与 Python dict 语义一致');
    expect(code.contains('putIfAbsent'), isFalse,
        reason: '「不存在才写」会让 " 停在 11、ᵻ 停在 176，元音就错了');
  });
}

String _describe(String ch) => "'$ch' (U+${ch.runes.first.toRadixString(16).toUpperCase().padLeft(4, '0')})";

/// Kotlin 字符串转义：`\uXXXX`、`\n`、`\t`、`\"`、`\$`、`\\`。
String _unescapeKotlin(String raw) {
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch != r'\' || i + 1 >= raw.length) {
      out.write(ch);
      continue;
    }
    final next = raw[i + 1];
    if (next == 'u') {
      out.writeCharCode(int.parse(raw.substring(i + 2, i + 6), radix: 16));
      i += 5;
    } else if (next == 'n') {
      out.write('\n');
      i += 1;
    } else if (next == 't') {
      out.write('\t');
      i += 1;
    } else {
      out.write(next);
      i += 1;
    }
  }
  return out.toString();
}
