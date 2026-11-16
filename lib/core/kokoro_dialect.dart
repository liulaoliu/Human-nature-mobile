/// 把 espeak 教科书 IPA 转成 Kokoro 训练时用的 misaki 字母表。
///
/// 为什么需要这一步（2026-11-16 查证）：
/// Kokoro-82M 是在 [misaki](https://github.com/hexgrad/misaki) 的输出上训练的。
/// misaki 把双元音和塞擦音写成**单个**符号（`ʧ` `ʤ` `A` `I` `O` `W` `Y`），
/// 美音输出**不带**长音符 `ː`。而 `package:phonemize` 吐的是教科书 IPA：
/// `tʃ` `dʒ` `eɪ` `aɪ` `oʊ` `ɾ`，还带 `ː`。
///
/// 要命的是：**这些 espeak 写法的符号全部都在 Kokoro 的 vocab 里**，所以
/// tokenizer 一个都不会丢、不会报错 —— 模型只是收到了训练时从没见过的
/// token 组合，音频于是「跑偏」。这就是「字都在、读出来还是怪」的根子，
/// 也是 2026-11-16 只补 `ɝ`/`ɫ` 两条映射没治好它的原因。
///
/// 规则来源：官方实现的音素方言转换（CrispASR #316 的 `phoneme_dialect.h`、
/// skadoosh 的 `normalize_ipa`），并用 16 组「我们的输出 → misaki 实际输出」
/// 的逐字节样本校验（见 `test/core/kokoro_dialect_test.dart`）。
library;

/// 双字符规则：espeak 拼法 → misaki 拼法。**最长优先**，替换结果不回扫。
const Map<String, String> kMisakiPairs = <String, String>{
  'tʃ': 'ʧ',
  'dʒ': 'ʤ',
  'eɪ': 'A',
  'aɪ': 'I',
  'oʊ': 'O',
  'əʊ': 'O', // en-gb 写法的同一个音
  'aʊ': 'W',
  'ɔɪ': 'Y',
  'ɜː': 'ɜɹ', // NURSE 保留 r：只删长音符会得到 wˈɜld，少一个 r
};

/// 单字符规则：espeak 拼法 → misaki 拼法。
const Map<String, String> kMisakiSingles = <String, String>{
  'ɝ': 'ɜɹ',
  'ɚ': 'əɹ',
  'ɾ': 'T', // 美音闪音
  'ʔ': 't', // 喉塞化：espeak 会在成音节鼻音前插 ʔ（certainly → sˈɜɹʔnli）
  'r': 'ɹ', // espeak 有时直接写 r
  'ɫ': 'l',
  'ê': 'e',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 's',
  '’': "'",
  '‘': "'",
  '-': ' ',
  '–': ' ',
  '—': ' ',
  '[': ' ',
  ']': ' ',
  '【': ' ',
  '】': ' ',
  '（': ' ',
  '）': ' ',
  '|': ' ',
  '#': ' ',
};

/// 转换后不应再出现在串里的 espeak 专属写法。留一个都是 bug。
const List<String> kEspeakOnlyResidue = <String>[
  'ː',
  'tʃ',
  'dʒ',
  'eɪ',
  'aɪ',
  'oʊ',
  'aʊ',
  'ɔɪ',
  'ɚ',
  'ɝ',
  'ɾ',
  'ʔ',
];

/// 把 [ipa] 从 espeak 字母表转成 misaki 字母表。
///
/// 幂等：已转换的串再走一遍不会变（misaki 符号里没有会命中源规则的了）。
String toMisakiAlphabet(String ipa) {
  if (ipa.isEmpty) return ipa;
  final out = StringBuffer();
  var i = 0;
  while (i < ipa.length) {
    // ɚ 紧跟 ɹ 时整体吃掉，只吐一个 əɹ：espeak 把 "parameters" 写成 pɚɹ…，
    // 天真的 ɚ→əɹ 会得到 əɹɹ，misaki 从不这么写。
    if (i + 1 < ipa.length &&
        ipa.codeUnitAt(i) == 0x025A &&
        ipa[i + 1] == 'ɹ') {
      out.write('əɹ');
      i += 2;
      continue;
    }
    if (i + 1 < ipa.length) {
      final pair = kMisakiPairs[ipa.substring(i, i + 2)];
      if (pair != null) {
        out.write(pair);
        i += 2;
        continue;
      }
    }
    final ch = ipa[i];
    if (ch == 'ː') {
      // 长音符直接丢：美音输出没有它，留着会被读成 RP 腔。
      i += 1;
      continue;
    }
    out.write(kMisakiSingles[ch] ?? ch);
    i += 1;
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// [ipa] 里还残留的 espeak 专属写法（正常应为空）。
Set<String> espeakResidue(String ipa) {
  final left = <String>{};
  for (final bad in kEspeakOnlyResidue) {
    if (ipa.contains(bad)) left.add(bad);
  }
  return left;
}
