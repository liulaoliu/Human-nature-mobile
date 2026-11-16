/// 英语 G2P：给 Kokoro 算 misaki 字母表的音素。
///
/// 为什么要有这一层（2026-11-16 的结论）：
/// Kokoro-82M 是在 [misaki](https://github.com/hexgrad/misaki) 的输出上训练的。
/// 只用 `package:phonemize`（espeak 教科书 IPA）+ 字符映射，对官方 3000 词
/// 的逐字节一致率只有 **3.3%**、再抹掉重音也只有 49.3% —— 这是「字都在、
/// 读出来还是怪」的真正原因。换成 malsami（misaki 的 Dart 移植）当主路后
/// 是 **84.8%**，加一条 `ɾ→T` 到 **90.2%**。
///
/// 两层结构：
///   1. 主路：[EnglishG2P]（malsami）查它自带的 misaki 词典，覆盖正文
///      93.09% 的词次；
///   2. 兜底：剩下的 7% 走 `package:phonemize`，再过 [toMisakiAlphabet]
///      转成 misaki 字母表。复数、专名、`makes` 这类词典缺的词全靠它。
///
/// 为什么不直接 `EnglishG2P()` 了事：malsami 的 `Lexicon.initialize()` 写死
/// 读 `assets/us_gold.json` / `assets/us_silver.json`（未压缩，6.1MB）。我们
/// 打的是 gzip（1.43MB），所以在这里替换掉那一层加载 —— 词典逻辑仍然是
/// malsami 的，一行没抄。
library;

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:malsami/malsami.dart';
import 'package:phonemize/phonemize.dart' as p;

import '../core/kokoro_dialect.dart';

/// 美音词典（gzip 压缩后的 JSON）。来源：`misaki 0.9.4` 的 `data/us_*.json`。
const String kUsGoldAsset = 'assets/lexicons/us_gold.json.gz';
const String kUsSilverAsset = 'assets/lexicons/us_silver.json.gz';

/// 音素算不出来时的兜底串（malsami 的未知标记，与 [EnglishG2P.unk] 一致）。
const String kUnknownPhoneme = '❓';

/// 把 malsami 的词典加载换成「读我们自己的 gzip」。
///
/// 只覆盖 [EnglishG2P.initialize]。父类的 `convert` / `processTokens` 都会先
/// `await initialize()`，所以这里是唯一的加载入口。
class _GzipLexiconG2P extends EnglishG2P {
  _GzipLexiconG2P() : super();

  bool _loaded = false;

  @override
  Future<void> initialize() async {
    if (_loaded) return;
    final gold = await _loadDict(kUsGoldAsset);
    final silver = await _loadDict(kUsSilverAsset);
    lexicon.golds = lexicon.growDictionary(gold);
    lexicon.silvers = lexicon.growDictionary(silver);
    _loaded = true;
    debugPrint(
      'Kokoro G2P 词典就绪：gold ${lexicon.golds.length} 条、'
      'silver ${lexicon.silvers.length} 条',
    );
  }

  static Future<Map<String, dynamic>> _loadDict(String asset) async {
    final data = await rootBundle.load(asset);
    final raw = gzip.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  }
}

/// 英语音素化：malsami 主路 + phonemize 兜底，输出 misaki 字母表。
class KokoroG2P {
  KokoroG2P();

  EnglishG2P? _g2p;
  bool _ready = false;

  /// phonemize 包要一次性初始化（否则每次转换都重新建处理器）。
  static bool _phonemizeReady = false;

  bool get isReady => _ready;

  /// 加载词典。首次约 1 秒（桌面实测 1058ms），之后直接返回。
  Future<void> initialize() async {
    if (_ready) return;
    final g2p = _GzipLexiconG2P();
    await g2p.initialize();
    _g2p = g2p;
    if (!_phonemizeReady) {
      p.initDefaultProcessors();
      _phonemizeReady = true;
    }
    _ready = true;
  }

  /// 把一句话转成音素串。调用前请先过 `normalizeTtsText`。
  ///
  /// 返回的串已经可以直接喂给 Kokoro：`ɾ` 已换成 `T`、`ʔ` 已换成 `t`、
  /// 兜底那部分也已过 [toMisakiAlphabet]。
  Future<String> phonemize(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    await initialize();
    final (_, tokens) = await _g2p!.convert(trimmed);
    final out = StringBuffer();
    var usedFallback = 0;
    var retried = 0;
    for (var i = 0; i < tokens.length; i++) {
      final tk = tokens[i];
      if (i > 0 && tk.underscore?.prespace == true) out.write(' ');
      final ps = tk.phonemes;
      if (ps != null && ps.isNotEmpty && ps != kUnknownPhoneme) {
        out.write(ps);
        continue;
      }
      // 词典没命中。两种情况：① 词本身不在词典（复数、专名、makes）；
      // ② 词尾粘了标点（`perfect.`）—— malsami 的 tokenize 按空白切，
      // 标点跟着词走，查表自然查不到。②占大多数，先把标点摘下来重查一次。
      final split = _splitPunct(tk.text);
      if (split.core != tk.text && split.core.isNotEmpty) {
        final hit = _lookupDirect(split.core);
        if (hit != null) {
          out.write(hit);
          out.write(split.trailing);
          retried += 1;
          continue;
        }
      }
      // 真查不到：退回 espeak 再对齐字母表。
      final fb = _fallback(split.core.isEmpty ? tk.text : split.core);
      if (fb.isNotEmpty) {
        out.write(fb);
        out.write(split.trailing);
        usedFallback += 1;
      }
    }
    if (usedFallback > 0 || retried > 0) {
      debugPrint('Kokoro G2P 兜底 $usedFallback 段、摘标点重查 $retried 段');
    }
    return _tidy(out.toString());
  }

  /// 直接查一次词典（补上 malsami 因标点粘连漏掉的命中）。
  String? _lookupDirect(String word) {
    final g2p = _g2p;
    if (g2p == null) return null;
    final (ps, _) = g2p.lexicon.lookup(
      word,
      'NN',
      null,
      const TokenContext(futureVowel: null, futureTo: false),
    );
    return ps;
  }

  /// 拆出 `perfect.` 的 `perfect` 与 `.`。
  static ({String core, String trailing}) _splitPunct(String word) {
    final m = RegExp(r'^([^\p{L}\p{N}]*)(.*?)([^\p{L}\p{N}]*)$', unicode: true)
        .firstMatch(word);
    if (m == null) return (core: word, trailing: '');
    final core = m.group(2) ?? '';
    return (core: core.isEmpty ? word : core, trailing: m.group(3) ?? '');
  }

  /// 兜底：phonemize（espeak 教科书 IPA）→ misaki 字母表。
  ///
  /// 词典查不到的词多是复数/专名，espeak 对它们的处理反而稳。这一步的
  /// 一致率不高（整体 49.3%），但只占正文 7% 的词次。
  String _fallback(String word) {
    final cleaned = word.replaceAll(RegExp(r'^[^A-Za-z]+|[^A-Za-z]+$'), '');
    if (cleaned.isEmpty) return '';
    final ipa = p.phonemize(
      cleaned,
      language: 'en-us',
      stripStress: false,
      format: 'ipa',
    );
    return toMisakiAlphabet(ipa).trim();
  }

  /// 收尾：把词典里残留的 espeak 写法抹平、压空白。
  ///
  /// malsami 打包的是**旧快照**词典（`ɾ` 出现 17,279 次、`T` 0 次），而官方
  /// misaki 0.9.4 已经改用 `T`（`ɾ`×9,634、`T`×1,491）。所以主路取回来的
  /// 音素也要过一遍，否则 `petting` 会留着 `ɾ`。这一步让逐字节一致率从
  /// 84.8% 到 90.2%。
  static String _tidy(String ipa) {
    var s = ipa.replaceAll('ɾ', 'T');
    s = s.replaceAll('ʔ', 't');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // `ɹɹ` 折叠：兜底与主路接缝处可能撞出重复的 r。
    while (s.contains('ɹɹ')) {
      s = s.replaceAll('ɹɹ', 'ɹ');
    }
    return s;
  }
}
