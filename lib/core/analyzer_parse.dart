/// 精读 AI 结果解析：把用户从网页版 DeepSeek 粘回来的自由文本，解析成结构化数据。
///
/// 这里是「输入侧」——只认文本、只出数据，不发请求、不拼提示词（那在 `analyzer_prompt.dart`）。
/// 所有解析器都对脏输入宽容：表头行、分隔线、项目符号、多余竖线都吃掉，认不出就返回空。
library;

import 'dart:convert';

import '../models/document.dart';
import 'analyzer_shared.dart';
import 'ecdict.dart' show LemmaPair;
import 'vocab/analysis.dart' show ConfusableResult, PosRow, WordAnalysis;
import 'vocab/word.dart' show lemmaOf;
import 'word_select.dart' show wordSpans;
import '../models/vocab.dart' show VocabConfusable;

/// 把 AI 返回的一个「词条行」清成单词。
///
/// 去掉编号 / 项目符号 / markdown，去掉后面粘的注释（词性、中文、括号说明），
/// 只保留开头的英文词。例：`1. **impeachment (n.)** — 弹劾` → `impeachment`。
String cleanVocabWord(String raw) {
  var w = raw.replaceAll(RegExp(r'[*_`]'), '').trim();
  w = w.replaceFirst(RegExp(r'^[-–•·\s]*\d+\s*[).、]?\s*'), '');
  w = w.replaceFirst(RegExp(r'^[-–•·\s]+'), '');
  final parts = w.split(RegExp(r'[\s—–:：,，;；(（\[【"“”|/]+'));
  w = parts.isEmpty ? '' : parts.first;
  w = w.replaceFirst(RegExp(r"[^A-Za-z'-].*$"), '');
  return w.trim();
}

/// 提取词形列表：逗号 / 顿号 / 换行都能拆，去重。
List<String> parseWordList(String raw) {
  final out = <String>[];
  for (final part in raw.split(RegExp(r'[,，、;；\n]+'))) {
    final w = part
        .replaceFirst(RegExp(r'^[\s\-*•\d.]+'), '')
        .replaceFirst(RegExp(r'[.。!！?？"“”]+$'), '')
        .trim();
    if (w.isNotEmpty && !out.contains(w)) out.add(w);
  }
  return out;
}

({String text, String? translation}) _parseExample(String raw) {
  final parts = raw.split(RegExp(r'\s+[—–-]\s+'));
  if (parts.length >= 2) {
    return (
      text: cleanExampleText(parts.first),
      translation: cleanExampleText(parts.sublist(1).join(' — ')),
    );
  }
  return (text: cleanExampleText(raw), translation: null);
}

/// 表头判定：只看「首列 / 音标列」是不是表头标签，避免把正文里含 "word" 的正常行误删。
const Set<String> _headerFirst = <String>{'单词', '词语', '原形', '单词/原形'};
const Set<String> _headerPhonetic = <String>{
  '音标',
  '国际音标',
  'phonetic',
  'ipa',
};

/// 把一行按竖线切成列（Markdown 表格前后各带一个空列时去掉它们）。
List<String> _columns(String line) {
  final hadLead = line.startsWith('|') || line.startsWith('｜');
  final hadTrail = line.endsWith('|') || line.endsWith('｜');
  final cols = line.split(RegExp('[|｜]')).map((c) => c.trim()).toList();
  if (hadLead && cols.isNotEmpty && cols.first.isEmpty) cols.removeAt(0);
  if (hadTrail && cols.isNotEmpty && cols.last.isEmpty) cols.removeLast();
  return cols;
}

bool _isNoise(String trimmed) =>
    trimmed.isEmpty || RegExp(r'^[|\-\s:]+$').hasMatch(trimmed);

String _stripBullet(String raw) =>
    raw.replaceFirst(RegExp(r'^[\-*•\d.、\s]+'), '').trim();

/// 解析查词表格（`word | phonetic | pos | meaning | usage | example`）。
List<WordAnalysis> parseLookupTable(String raw) {
  final words = <WordAnalysis>[];
  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (_isNoise(trimmed)) continue;
    final cols = _columns(trimmed);
    if (cols.length < 2) continue;
    // 表头行：音标列写着「音标/phonetic」，或首列是「单词」这类标签。
    // 注意不能全文匹配 "word"——否则像 portmanteau 的释义 "a word formed by…" 会被误当表头。
    final c0 = cols[0].toLowerCase();
    final c1 = cols[1].toLowerCase();
    if (_headerPhonetic.contains(c1) || _headerFirst.contains(c0)) continue;
    var word = cols[0];
    var phonetic = cols.length > 1 ? cols[1] : '';
    final partOfSpeech = cols.length > 2 ? cols[2] : '';
    final meaning = cols.length > 3 ? cols[3] : '';
    final usage = cols.length > 4 ? cols[4] : '';
    final example = cols.length > 5 ? cols[5] : '';
    final definition = cols.length > 6 ? cols[6] : '';
    if (word.isEmpty) continue;
    // 只有音标格为空时，才从单词格里拆音标（"run /rʌn/" 或 "run [rʌn]"），避免误伤
    if (phonetic.isEmpty) {
      final m = RegExp(r'^(.+?)\s+(/.+)$').firstMatch(word) ??
          RegExp(r'^(.+?)\s+(\[.+\])$').firstMatch(word);
      if (m != null) {
        word = m.group(1)!.trim();
        phonetic = m.group(2)!.trim();
      }
    }
    final usageList = splitList(usage);
    final parsedExample = _parseExample(example);
    words.add(
      WordAnalysis(
        word: word,
        phonetic: phonetic.isEmpty ? null : phonetic,
        partOfSpeech: partOfSpeech.isEmpty ? null : partOfSpeech,
        meaning: meaning.isEmpty ? null : meaning,
        definition: definition.isEmpty ? null : definition,
        usage: usageList.isEmpty ? null : usageList,
        examples: example.isEmpty ? null : [parsedExample],
      ),
    );
  }
  return words;
}

/// 解析结果：查到的词 / 逐句翻译，两者至少有一个才非空。
class ParsedAnalysis {
  const ParsedAnalysis({this.words = const [], this.sentences = const []});

  final List<WordAnalysis> words;
  final List<TranslationRow> sentences;

  bool get isEmpty => words.isEmpty && sentences.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

ParsedAnalysis _normalizeJson(Object? value) {
  if (value is List) {
    final words = <WordAnalysis>[];
    final sents = <TranslationRow>[];
    for (final v in value) {
      if (v is! Map) continue;
      final map = <String, Object?>{};
      for (final e in v.entries) {
        map['${e.key}'] = e.value;
      }
      if (map.containsKey('word')) {
        words.add(_wordFromJson(map));
      } else if (map.containsKey('sentenceId') ||
          (map.containsKey('id') && map.containsKey('translation'))) {
        sents.add(
          TranslationRow(
            sentenceId: '${map['sentenceId'] ?? map['id'] ?? ''}',
            translation: '${map['translation'] ?? ''}',
          ),
        );
      }
    }
    if (sents.isNotEmpty) return ParsedAnalysis(sentences: sents);
    return ParsedAnalysis(words: words);
  }
  if (value is Map) {
    final map = <String, Object?>{};
    for (final e in value.entries) {
      map['${e.key}'] = e.value;
    }
    if (map['word'] != null) return ParsedAnalysis(words: [_wordFromJson(map)]);
    final words = <WordAnalysis>[];
    for (final w in map['words'] is List ? map['words']! as List : const []) {
      if (w is Map) {
        final m = <String, Object?>{};
        for (final e in w.entries) {
          m['${e.key}'] = e.value;
        }
        words.add(_wordFromJson(m));
      }
    }
    final sents = <TranslationRow>[];
    for (final s in map['sentences'] is List ? map['sentences']! as List : const []) {
      if (s is! Map) continue;
      sents.add(
        TranslationRow(
          sentenceId: '${s['sentenceId'] ?? s['id'] ?? ''}',
          translation: '${s['translation'] ?? ''}',
        ),
      );
    }
    return ParsedAnalysis(words: words, sentences: sents);
  }
  return const ParsedAnalysis();
}

WordAnalysis _wordFromJson(Map<String, Object?> m) {
  String? text(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  return WordAnalysis(
    word: text(m['word']) ?? '',
    phonetic: text(m['phonetic']),
    partOfSpeech: text(m['partOfSpeech']),
    meaning: text(m['meaning']),
    definition: text(m['definition']),
    usage: m['usage'] is List
        ? [
            for (final u in m['usage']! as List)
              if ('$u'.trim().isNotEmpty) '$u'.trim(),
          ]
        : null,
  );
}

/// 解析粘回来的结果：先试 JSON，再试翻译表，再试查词表，都不中返回空。
ParsedAnalysis parseAnalysis(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const ParsedAnalysis();
  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      return _normalizeJson(jsonDecode(text));
    } on FormatException {
      // 落到表格解析
    }
  }
  final sentences = parseTranslationTable(text);
  if (sentences.isNotEmpty) return ParsedAnalysis(sentences: sentences);
  final words = parseLookupTable(text);
  if (words.isNotEmpty) return ParsedAnalysis(words: words);
  return const ParsedAnalysis();
}

/// 把自由文本结果落到某一句上（翻译 / 语法 / 搭配 / 生词）。
Sentence applyToSentence(Sentence sentence, AnalysisTask task, String raw) {
  final text = raw.trim();
  if (text.isEmpty) return sentence;
  switch (task) {
    case AnalysisTask.translate:
      return sentence.copyWith(translation: () => text);
    case AnalysisTask.grammar:
      return sentence.copyWith(grammarNote: () => text);
    case AnalysisTask.collocations:
      return sentence.copyWith(
        collocations: <String>{
          ...sentence.collocations,
          ...splitList(text),
        }.toList(growable: false),
      );
    case AnalysisTask.extractVocab:
      return sentence.copyWith(
        vocab: <String>{
          ...sentence.vocab,
          ...parseWordList(text),
        }.toList(growable: false),
      );
    case AnalysisTask.lookup:
    case AnalysisTask.summarize:
    case AnalysisTask.autoVocab:
      return sentence;
  }
}

/// 例句是否**真的含该词**（词形还原后比较）；用来剔掉「用同义词糊弄」的例句。
bool _exampleHasWord(String text, String word) {
  final lemma = lemmaOf(word);
  final w = word.trim().toLowerCase();
  if (w.isEmpty) return true;
  for (final s in wordSpans(text)) {
    final t = s.text.toLowerCase();
    if (t == w || (lemma.isNotEmpty && lemmaOf(s.text) == lemma)) return true;
  }
  return false;
}

/// 判定「无 / 不适用 / -」这类占位写法。
bool _isNoneCell(String raw) =>
    RegExp(r'^(无|没有|不适用|none|n/a|nil|空|-|—|–)$', caseSensitive: false)
        .hasMatch(raw.trim());

/// 解析词组 / 习语表（`单词 | 词组1；词组2 | 习语1；习语2`）。
List<PhraseRow> parsePhraseTable(String raw) {
  final out = <PhraseRow>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (_isNoise(t)) continue;
    final cols = _columns(t);
    if (cols.length < 2) continue;
    final word = _stripBullet(cols[0]);
    if (word.isEmpty || RegExp(r'^(单词|word)$', caseSensitive: false).hasMatch(word)) {
      continue;
    }
    // 空 / 「无」= 没有该类的说法；**仍算「已标注」**（防止无限重复待办）
    final phrases = cols[1].isNotEmpty && !_isNoneCell(cols[1])
        ? splitList(cols[1])
        : const <String>[];
    final idioms = cols.length > 2 && cols[2].isNotEmpty && !_isNoneCell(cols[2])
        ? splitList(cols[2])
        : const <String>[];
    out.add(PhraseRow(word: word, phrases: phrases, idioms: idioms));
  }
  return out;
}

/// 受控的语法标记写法的别名表（容忍英文 / 简写）。
const Map<String, String> markAliases = <String, String>{
  '可数名词': '可数',
  'countable': '可数',
  '不可数名词': '不可数',
  'uncountable': '不可数',
  'noncount': '不可数',
  '及物动词': '及物',
  'transitive': '及物',
  'vt': '及物',
  '不及物动词': '不及物',
  'intransitive': '不及物',
  'vi': '不及物',
  'gradable': '可分级',
  'ungradable': '不可分级',
  'non-gradable': '不可分级',
};

/// 受控的语法标记集合。
const List<String> grammarMarks = <String>[
  '可数',
  '不可数',
  '及物',
  '不及物',
  '可分级',
  '不可分级',
];

String? _normalizeMark(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (grammarMarks.contains(t)) return t;
  final key = t.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (grammarMarks.contains(key)) return key;
  return markAliases[key];
}

/// 解析语法标记表（`单词 | 标记1；标记2`）。只保留受控词表内的标记。
List<GrammarMarkRow> parseGrammarMarkTable(String raw) {
  final out = <GrammarMarkRow>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (_isNoise(t)) continue;
    final cols = _columns(t);
    if (cols.length < 2) continue;
    final word = _stripBullet(cols[0]);
    if (word.isEmpty || RegExp(r'^(单词|word)$', caseSensitive: false).hasMatch(word)) {
      continue;
    }
    // 「无 / 不适用 / -」或留空 = 该词没有可标的标记；**仍算「已标注」**（防止无限重复待办）
    final marks = <String>[];
    if (!_isNoneCell(cols[1])) {
      for (final part in cols[1].split(RegExp(r'[;；,，、\s/]+'))) {
        final m = _normalizeMark(part);
        if (m != null && !marks.contains(m)) marks.add(m);
      }
    }
    out.add((word: word, marks: marks));
  }
  return out;
}

/// 解析用法示例表（`word | 英 | 中 | 英 | 中`）。
List<ExampleRow> parseExampleTable(String raw) {
  final out = <ExampleRow>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (_isNoise(t)) continue;
    final cols = _columns(t);
    if (cols.length < 3) continue;
    final word = _stripBullet(cols[0]);
    if (word.isEmpty || RegExp(r'^(单词|word)$', caseSensitive: false).hasMatch(word)) {
      continue;
    }
    final examples = <({String text, String? translation})>[];
    for (var i = 1; i + 1 < cols.length; i += 2) {
      final en = cleanExampleText(cols[i]);
      final zh = cleanExampleText(cols[i + 1]);
      if (en.isEmpty) continue;
      // 跑飞的长句（多半是 AI 跑题）直接丢
      if (en.split(RegExp(r'\s+')).length > 30) continue;
      if (examples.any((e) => e.text.toLowerCase() == en.toLowerCase())) {
        continue;
      }
      examples.add(zh.isEmpty ? (text: en, translation: null) : (text: en, translation: zh));
    }
    if (examples.isEmpty) continue;
    // 优先留「真的含该词」的例句；全都不含（AI 用同义词糊弄）时宽松保留，避免任务反复跑
    final withWord = examples.where((e) => _exampleHasWord(e.text, word)).toList();
    out.add(ExampleRow(word: word, examples: withWord.isNotEmpty ? withWord : examples));
  }
  return out;
}

/// 解析「id | 译文」逐句翻译表。
List<TranslationRow> parseTranslationTable(String raw) {
  final out = <TranslationRow>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (_isNoise(t)) continue;
    final i = t.indexOf(RegExp('[|｜]'));
    if (i < 0) continue;
    final id = t.substring(0, i).replaceAll(RegExp(r'[`*\s]'), '');
    final translation =
        t.substring(i + 1).replaceFirst(RegExp(r'^[|｜\s]+'), '').trim();
    if (RegExp(r'^s\d+$', caseSensitive: false).hasMatch(id) &&
        translation.isNotEmpty) {
      out.add(TranslationRow(sentenceId: id, translation: translation));
    }
  }
  return out;
}

/// 解析混淆项结果（`原词 | 词:释义 ; 词:释义`）。
List<ConfusableResult> parseConfusables(String raw) {
  final out = <ConfusableResult>[];
  for (final rawLine in raw.split('\n')) {
    final t = _stripBullet(rawLine.trim());
    if (t.isEmpty) continue;
    final i = t.indexOf(RegExp('[|｜]'));
    if (i < 0) continue;
    final word = t.substring(0, i).trim();
    if (word.isEmpty || RegExp('原词|易混|单词|word', caseSensitive: false).hasMatch(word)) {
      continue;
    }
    final confusables = <({String word, String? meaning})>[];
    for (final part in t.substring(i + 1).split(RegExp('[;；]'))) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final m = RegExp(r'^(.+?)\s*[:：]\s*(.+)$').firstMatch(p);
      if (m != null) {
        confusables.add((word: m.group(1)!.trim(), meaning: m.group(2)!.trim()));
      } else {
        confusables.add((word: p, meaning: null));
      }
    }
    if (confusables.isEmpty) continue;
    out.add(
      ConfusableResult(
        word: word,
        confusables: [
          for (final c in confusables)
            VocabConfusable(word: c.word, meaning: c.meaning),
        ],
      ),
    );
  }
  return out;
}

/// 解析「原词形 | 原形」表。
List<LemmaPair> parseLemmaTable(String raw) {
  final out = <LemmaPair>[];
  for (final rawLine in raw.split('\n')) {
    final t = _stripBullet(rawLine.trim());
    if (t.isEmpty) continue;
    final i = t.indexOf(RegExp('[|｜]'));
    if (i < 0) continue;
    final from = t.substring(0, i).trim();
    if (from.isEmpty ||
        RegExp('原词形|原形|单词|word', caseSensitive: false).hasMatch(from)) {
      continue;
    }
    final to = t
        .substring(i + 1)
        .replaceFirst(RegExp(r'^[|｜\s]+'), '')
        .trim()
        .split(RegExp(r'[\s（(,，;；]'))
        .first;
    if (to.isEmpty) continue;
    out.add(LemmaPair(from: from, to: to));
  }
  return out;
}

/// 解析 -ing/-ed 辨析表（8 列）。
List<PosRow> parsePosTable(String raw) {
  final out = <PosRow>[];
  for (final rawLine in raw.split('\n')) {
    final t = _stripBullet(rawLine.trim());
    if (t.isEmpty) continue;
    final cols = _columns(t);
    if (cols.length < 8) continue;
    final lemma = cols[0];
    final surface = cols[1];
    if (lemma.isEmpty || surface.isEmpty) continue;
    if (RegExp('原形|当前形式|lemma', caseSensitive: false).hasMatch(lemma)) {
      continue;
    }
    out.add(
      PosRow(
        lemma: lemma,
        surface: surface,
        pos: cols[2],
        syntax: cols[3],
        role: cols[4],
        meaning: cols[5],
        reason: cols[6],
        label: cols[7],
      ),
    );
  }
  return out;
}
