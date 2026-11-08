/// 查词结果的「离线词典兜底」。
///
/// 对应 Web 版 `src/reader/apply/analysis.ts:37-85` 里的 `wordsForApply`：
/// 把 AI 粘回来的行先用离线词典校验一遍 —— 原形归一、补齐缺失的音标 / 词性 /
/// 中英释义，并**逐字段**记来源（AI 给的记 `ai`，词典补的记 `dict`）。
///
/// 三条不能破的口径：
///   1. **词性 / 释义 / 英英必须同源**。AI 给了释义却没给词性时，**不能**拿词典的词性
///      顶上 —— 词典给的是词头首义（rival 一定是 `n.`），AI 给的是语境义，
///      凑一起就变成「n. 与……匹敌」这种自相矛盾的卡。
///   2. 词典释义是多行的、每行自带词性标记，要按词性挑（`glossForPos`），
///      不能硬取第一行（否则 vow 会变成「v. n. 誓约」）。
///   3. 词形能归到原形就归（`resolveWord` 返回的 `lemma`），查不到就保留 AI 写的词。
///
/// 这里只吃「已经解析好的结构」，不碰 JSON / 表格文本。
library;

import '../ecdict.dart' show Ecdict, glossForPos, resolveWord;
import '../vocab/word.dart' show normalizePos;
import '../../models/vocab.dart';
import 'analysis.dart' show WordAnalysis, applyWordAnalysis;
import 'merge.dart' show dedupeLibrary;
import 'sense.dart' show posFromGloss;

/// 用离线词典补一份查词结果里缺的字段。
///
/// [dict] 为 null（安卓侧没加载到词典）时只做原形归一以外的事：原样返回词形，
/// 一个字段都不补，也不改来源。
WordAnalysis fillFromDict(WordAnalysis input, Ecdict? dict) {
  final hit = dict == null ? null : resolveWord(dict, input.word);
  final entry = hit?.entry;

  final phonetic = _withSlashes(input.phonetic) ?? _withSlashes(entry?.phonetic);

  // 释义先定下来 —— 词性要不要从词典取，取决于「释义是谁给的」。
  final fromAiMeaning = _text(input.meaning);
  final meaning = fromAiMeaning ?? _dictGloss(entry?.zh, input.partOfSpeech ?? '');

  String? partOfSpeech;
  if (_text(input.partOfSpeech) != null) {
    partOfSpeech = normalizePos(input.partOfSpeech);
    if (partOfSpeech.isEmpty) partOfSpeech = null;
  } else if (fromAiMeaning == null) {
    // 释义来自词典（或都没有）：词性取释义同一行的标记，再退到词典的 pos 列。
    partOfSpeech = posFromGloss(meaning);
    if (partOfSpeech == null) {
      final p = normalizePos(entry?.pos);
      partOfSpeech = p.isEmpty ? null : p;
    }
  }
  // AI 给了释义却没给词性：partOfSpeech 保持 null，宁可空着也不混源。

  final definition = _text(input.definition) ??
      _dictGloss(entry?.en, partOfSpeech ?? '');

  final fieldSources = <VocabField, VocabFieldSource>{};
  if (phonetic != null) {
    fieldSources[VocabField.phonetic] =
        _withSlashes(input.phonetic) != null ? VocabFieldSource.ai : VocabFieldSource.dict;
  }
  if (partOfSpeech != null) {
    fieldSources[VocabField.partOfSpeech] = _text(input.partOfSpeech) != null
        ? VocabFieldSource.ai
        : VocabFieldSource.dict;
  }
  if (meaning != null) {
    fieldSources[VocabField.meaning] =
        fromAiMeaning != null ? VocabFieldSource.ai : VocabFieldSource.dict;
  }
  if (definition != null) {
    fieldSources[VocabField.definition] =
        _text(input.definition) != null ? VocabFieldSource.ai : VocabFieldSource.dict;
  }

  // 词典只补空缺：AI 自己给过的 usage / 例句一律照旧。
  return WordAnalysis(
    word: hit?.lemma ?? input.word,
    phonetic: phonetic,
    partOfSpeech: partOfSpeech,
    meaning: meaning,
    definition: definition,
    usage: input.usage,
    examples: input.examples,
    fieldSources: fieldSources.isEmpty ? null : fieldSources,
  );
}

/// 批量版：逐个补，保序。
List<WordAnalysis> fillAllFromDict(List<WordAnalysis> words, Ecdict? dict) =>
    words.map((w) => fillFromDict(w, dict)).toList(growable: false);

/// **只靠离线词典**得到一份查词结果（不经过 AI）。
///
/// 阅读页「点一下就查」走这条：选中词时立刻能从 7.8MB 的 ECDICT 里拿出
/// 音标 / 词性 / 中英释义，不用复制提示词、不用等网络。
/// 词典里查不到就返回 null（界面提示「词典里没有，用 AI 查」）。
///
/// 词性 / 释义 / 英英同源：释义取释义行的词性标记，英英用同一词性再挑一行。
WordAnalysis? wordAnalysisFromDict(Ecdict? dict, String word) {
  final hit = dict == null ? null : resolveWord(dict, word);
  final entry = hit?.entry;
  if (hit == null) return null;

  final pos = _entryPos(entry!.zh, entry.pos);
  final meaning = _dictGloss(entry.zh, pos ?? '');
  final definition = _dictGloss(entry.en, pos ?? '');

  final fieldSources = <VocabField, VocabFieldSource>{};
  if (_withSlashes(entry.phonetic) != null) {
    fieldSources[VocabField.phonetic] = VocabFieldSource.dict;
  }
  if (pos != null) fieldSources[VocabField.partOfSpeech] = VocabFieldSource.dict;
  if (meaning != null) fieldSources[VocabField.meaning] = VocabFieldSource.dict;
  if (definition != null) {
    fieldSources[VocabField.definition] = VocabFieldSource.dict;
  }

  if (meaning == null && definition == null && pos == null) return null;

  return WordAnalysis(
    word: hit.lemma,
    phonetic: _withSlashes(entry.phonetic),
    partOfSpeech: pos,
    meaning: meaning,
    definition: definition,
    fieldSources: fieldSources.isEmpty ? null : fieldSources,
  );
}

/// 词典词性：优先取中文释义行的标记（比 `pos` 列更贴中文义项），退到 `pos` 列。
///
/// 退路要补点：词典 `pos` 列写的是 `adj` / `n` 这种裸缩写，而释义行标记是
/// `adj.` / `n.`。同一张卡上两种写法混着显示很别扭，统一成带点的。
String? _entryPos(String? zh, String? pos) {
  final fromGloss = posFromGloss(_firstNonEmptyLine(zh));
  if (fromGloss != null) return fromGloss;
  final p = normalizePos(pos);
  if (p.isEmpty) return null;
  return p.endsWith('.') ? p : '$p.';
}

String? _firstNonEmptyLine(String? text) {
  final t = _text(text);
  if (t == null) return null;
  for (final line in t.split('\n')) {
    if (line.trim().isNotEmpty) return line.trim();
  }
  return null;
}


/// 把一批（已用词典补过的）查词结果写回词库，并记上**本篇**来源。
///
/// 与 Web 版 `applyAnalysisResult` 一致：**逐词**写（`applyWordAnalysis` 一次一个），
/// 这样每个词都能带上它在本文里的那句原文；最后统一 `dedupeLibrary`。
///
/// 来源只在「这句真的提到这个词」时才挂 —— 一次粘回来的表里可能有好几个词，
/// 把同一句硬挂给所有词，会在词条里留下一堆对不上的例句。
VocabLibrary applyFilledWords(
  VocabLibrary library,
  List<WordAnalysis> words, {
  required String articleId,
  String? fileName,
  String? sentenceId,
  String? sentenceText,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  var applied = library;
  for (final w in words) {
    final mentioned = _mentions(sentenceText, w.word);
    applied = applyWordAnalysis(
      applied,
      [w],
      now: at,
      defaultSource: VocabSource(
        articleId: articleId,
        fileName: fileName,
        sentenceId: mentioned ? sentenceId : null,
        sentenceText: mentioned ? (sentenceText ?? '') : '',
      ),
    );
  }
  return dedupeLibrary(applied);
}

/// 这句里有没有提到这个词（按词边界比，`run` 不该被 `running` 命中）。
bool _mentions(String? text, String word) {
  final t = text ?? '';
  final w = word.trim();
  if (t.isEmpty || w.isEmpty) return false;
  final re = RegExp(
    '(?<![A-Za-z])${RegExp.escape(w)}(?![A-Za-z])',
    caseSensitive: false,
  );
  return re.hasMatch(t);
}

String? _text(String? v) {
  if (v == null) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// 音标统一包一层斜杠：`rʌn` / `/rʌn/` / `[rʌn]` 都变成 `/rʌn/`。
String? _withSlashes(String? raw) {
  final t = _text(raw);
  if (t == null) return null;
  final bare = t.replaceAll(RegExp(r'^[/\[]+|[/\]]+$'), '').trim();
  return bare.isEmpty ? null : '/$bare/';
}

/// 词典释义按词性挑一行；挑不到就第一行。
String? _dictGloss(String? zh, String pos) {
  final t = _text(zh);
  if (t == null) return null;
  final line = glossForPos(t, pos).trim();
  return line.isEmpty ? null : line;
}
