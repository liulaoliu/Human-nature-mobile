import '../../models/vocab.dart';

/// 一条词卡的「义项一致性」：词性、中文释义、英英释义必须说的是**同一个义项**。
///
/// 三类数据在这里汇合，谁的话更可靠是不一样的：
///   - AI 查词：看过**这句话**，词性/释义/搭配/例句是同一行答案 → 可信，成组写入；
///   - 离线词典（ECDICT / M-W）：只有**词头首义**的词性和释义 → 只能占位，不能单独定词性；
///   - 用户手改：一律不动。
///
/// 所以这个文件只做机械可判的裁决，不做语义猜测：
///   1. [reconcileSense]：释义自带词性标记（"n. 誓约" / "vt. 引起"）时它是硬证据，词性跟它走；
///   2. [senseConflict]：把「词典占位的词性 + AI 的语境释义」这种必然可能打架的组合标出来，
///      由写入方决定清掉还是重查。
/// 与 Web 版 `src/core/vocab/sense.ts` 一一对应。

/// 词性写法 → 归类。认不出来的原样返回（体检会把它当异常）。
const Map<String, String> _class = {
  'n': 'n',
  'noun': 'n',
  'v': 'v',
  'vt': 'v',
  'vi': 'v',
  'verb': 'v',
  'a': 'adj',
  'adj': 'adj',
  'adjective': 'adj',
  'ad': 'adv',
  'adv': 'adv',
  'adverb': 'adv',
  'prep': 'prep',
  'preposition': 'prep',
  'conj': 'conj',
  'conjunction': 'conj',
  'pron': 'pron',
  'pronoun': 'pron',
  'num': 'num',
  'numeral': 'num',
  'art': 'art',
  'article': 'art',
  'interj': 'interj',
  'interjection': 'interj',
};

String _stripDots(String s) => s.replaceFirst(RegExp(r'\.+$'), '');

/// 归类词性；`v./n.` 这种并写取第一个认得的。
String posClassOf(String? pos) {
  final raw = _stripDots((pos ?? '').trim().toLowerCase());
  if (raw.isEmpty) return '';
  final direct = _class[raw];
  if (direct != null) return direct;
  for (final part in raw.split(RegExp(r'[/、,，]'))) {
    final key = _stripDots(part.trim());
    final hit = _class[key];
    if (hit != null) return hit;
  }
  return raw;
}

/// 释义开头的词性标记（"n. 誓约" / "vt. 引起"）→ 规范缩写；没有就 null。
String? posFromGloss(String? meaning) {
  final m = RegExp(r'^([a-z]{1,6})\.\s*\S', caseSensitive: false)
      .firstMatch((meaning ?? '').trim());
  if (m == null) return null;
  final cls = _class[m.group(1)!.toLowerCase()];
  if (cls == null) return null;
  return '$cls.';
}

/// 只有「单词卡片」才有词性可言：词组 / 用法笔记（kind 非空或 word 带空格）不在这一套里。
bool isWordCard(VocabItem item) {
  if (item.kind != null) return false;
  return !item.word.trim().contains(' ');
}

Map<VocabField, VocabFieldSource> _sources(VocabItem item) => item.fieldSources ?? const {};

/// 让词性跟释义对齐：释义带着词性标记（那份释义就是这么标的）时，以标记为准。
/// 用户手填的词性不动（`fieldSources.partOfSpeech == manual`）。
VocabItem reconcileSense(VocabItem item) {
  if (!isWordCard(item)) return item;
  final src = _sources(item);
  if (src[VocabField.partOfSpeech] == VocabFieldSource.manual) return item;
  final fromGloss = posFromGloss(item.meaning);
  if (fromGloss == null) return item;
  final pos = item.partOfSpeech;
  if (pos != null && posClassOf(pos) == posClassOf(fromGloss)) return item;
  return item.copyWith(
    partOfSpeech: () => fromGloss,
    fieldSources: () => {
      ...src,
      // 释义是 AI 给的，说明这个标记出自 AI 那行答案；否则只能是词典行
      VocabField.partOfSpeech: src[VocabField.meaning] == VocabFieldSource.ai
          ? VocabFieldSource.ai
          : VocabFieldSource.dict,
    },
  );
}

/// 自相矛盾的地方（没有就 null）。给体检用，写作时也会被 [reconcileSense] 挡住一部分。
String? senseConflict(VocabItem item) {
  if (!isWordCard(item)) return null;
  final src = _sources(item);
  final posSrc = src[VocabField.partOfSpeech];
  final meaningSrc = src[VocabField.meaning];
  // 词典给的词性是词头首义，AI 给的释义是语境义：这一对天然可能说的不是一回事
  if (item.partOfSpeech != null &&
      posSrc == VocabFieldSource.dict &&
      meaningSrc == VocabFieldSource.ai) {
    return 'dict-pos-with-ai-meaning';
  }
  final fromGloss = posFromGloss(item.meaning);
  final pos = item.partOfSpeech;
  if (fromGloss != null && pos != null && posClassOf(fromGloss) != posClassOf(pos)) {
    return 'pos-gloss-mismatch';
  }
  return null;
}
