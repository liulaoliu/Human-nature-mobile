/// 自动标词：让 AI 按指定词汇水平从正文里挑出值得查的词。
///
/// 提示词早就在 `analyzer_prompt.dart:162 buildAutoVocabPrompt`，
/// 这里补的是**结果解析**与**去重**——AI 会自作多情地给编号、给短语、
/// 给中文注释、把同一个词写三遍，这些都得在进「待选」之前清掉。
///
/// 与 Web 的差别：Web 把结果塞进侧栏的「待选」页签，人工增删后再查词；
/// 手机上没那么多横向空间，直接给一张可勾选的清单，勾完一次收进本篇。
library;

import 'ecdict.dart' show EcdictLevel;

/// 词汇水平的短标签（给下拉框用；长说明在 `analyzer_prompt.dart` 的 `levelDesc`）。
const Map<EcdictLevel, String> autoVocabLevelLabel = <EcdictLevel, String>{
  EcdictLevel.cet4: '四级以上',
  EcdictLevel.cet6: '六级以上',
  EcdictLevel.kaoyan: '考研以上',
  EcdictLevel.ielts: '雅思 5.5+',
  EcdictLevel.ielts65: '雅思 6.5+',
};

/// 允许的词形：只有字母、连字符、撇号（`well-being`、`don't`）。
final RegExp _wordShape = RegExp(r"^[A-Za-z][A-Za-z'\-]*$");

/// 行首的噪声：编号、项目符号、`-`、`*`、`1.`、`1)`、`①`。
final RegExp _lineLead = RegExp(r'^(?:[-*•·\d]+[.、)?）]?\s*|[①-⑳]\s*)');

/// 行里的中文/解释部分：`word —— 释义`、`word（释义）`、`word: 释义`。
///
/// 短横线只在**前后有空格**时才算分隔：`well-being` 是一个词，不能从中间切断。
final RegExp _glossCut = RegExp(r'[—–]|\s+-\s*|\s*[（(：:]\s*');

/// 行里直接跟了中文（`hobble 蹒跚地走`）：中文之前的部分才是词。
final RegExp _cjk = RegExp(r'[\u4e00-\u9fff]');

/// 解析自动标词的结果：每行可能是一个词，也可能带编号/释义。
///
/// 只留**单个单词**：带空格的一律当短语丢掉（提示词明确要求不要短语，
/// 出现了说明 AI 没听话，而短语该走「语言点」而不是生词本）。
/// 顺序保留（提示词要求按文中出现先后），大小写统一小写，重复只留第一次。
List<String> parseAutoVocabWords(String raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final line in raw.split('\n')) {
    var text = line.trim();
    if (text.isEmpty) continue;
    // 去掉行首编号 / 项目符号。
    text = text.replaceFirst(_lineLead, '').trim();
    if (text.isEmpty) continue;
    // 带释义的只取词本身。
    final cut = text.indexOf(_glossCut);
    if (cut > 0) text = text.substring(0, cut).trim();
    // 直接跟中文的（没加破折号/括号）：中文之前才是词。
    final cjk = text.indexOf(_cjk);
    if (cjk > 0) text = text.substring(0, cjk).trim();
    // 逗号 / 分号分隔的一行多个词，拆开各自处理。
    for (final piece in text.split(RegExp(r'[,，;；/|]+'))) {
      final word = piece.trim().replaceAll(RegExp(r'^["“”\x27]+|["“”\x27]+$'), '');
      if (word.length < 3) continue;
      if (!_wordShape.hasMatch(word)) continue;
      final lower = word.toLowerCase();
      if (!seen.add(lower)) continue;
      out.add(lower);
    }
  }
  return out;
}

/// 待选清单：从 AI 结果里剔掉词库里已经有的。
///
/// [known] 是**已收进本篇**的原形集合（`ReaderViewModel.currentEntries`
/// 里那些词条的 lemma，已经是小写）。不在本篇的旧词仍然建议收——
/// 用户可能就是想把它挂到这一篇上。
List<String> autoVocabCandidates(String raw, {Set<String> known = const {}}) {
  final normalized = <String>{for (final k in known) k.toLowerCase()};
  return <String>[
    for (final w in parseAutoVocabWords(raw))
      if (!normalized.contains(w)) w,
  ];
}
