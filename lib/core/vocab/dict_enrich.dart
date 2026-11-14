/// 用**离线词典**给词条补音标 / 词性 / 中文释义 / 英英释义（纯函数，不联网、不调 AI）。
///
/// 对应 Web 版 `src/core/dictEnrich.ts`。只补**空着的字段**，不动已有的
/// （用户改过的、AI 给过的都保留）；一个字段都没补到就返回同一个引用，
/// 调用方据此跳过写库（幂等）。
///
/// M-W 那条可选释义源没搬：App 没打包 `mwld.tsv`，词典就 ECDICT 一份。
library;

import '../../models/vocab.dart';
import '../ecdict.dart'
    show Ecdict, glossForPos, guessCompoundPos, resolveWord;
import 'sense.dart' show reconcileSense;
import 'word.dart' show cleanGloss, normalizePos;

/// 补完的结果：词库 + 这次补了多少条。
class DictEnrichResult {
  const DictEnrichResult({required this.library, required this.filled});

  final VocabLibrary library;

  /// 这次补了多少条（不是补了多少个字段）。
  final int filled;
}

/// 全库补一遍。
///
/// 只填空：已有值、以及 `fieldSources` 标了 `manual` 的字段一律跳过。
/// 词典查不到整词时，连字符复合词按末段后缀给词性（不记来源 ——
/// 那不是词典的结论，也不能冒充 AI 看过语境）。
DictEnrichResult enrichWithDict(
  VocabLibrary library,
  Ecdict dict, {
  DateTime? now,
}) {
  final iso = (now ?? DateTime.now()).toIso8601String();
  var filled = 0;
  final items = library.items.map((it) {
    final hit = resolveWord(dict, it.word) ?? resolveWord(dict, it.lemma);
    final compoundPos = hit == null ? guessCompoundPos(it.word) : null;
    if (hit == null && compoundPos == null) return it;

    final sources = <VocabField, VocabFieldSource>{...?it.fieldSources};
    String? phonetic;
    String? partOfSpeech;
    String? meaning;
    String? definition;

    final ph = _text(hit?.entry.phonetic);
    if (sources[VocabField.phonetic] != VocabFieldSource.manual &&
        _blank(it.phonetic) &&
        ph != null) {
      phonetic = '/${ph.replaceAll(RegExp(r'^/+|/+$'), '')}/';
      sources[VocabField.phonetic] = VocabFieldSource.dict;
    }

    final pos = normalizePos(hit?.entry.pos ?? '');
    // 词性只在「这条还没有释义」时补：词典给的词性是**词头最常用**的那个义项，
    // 而 AI 查词给的是**语境里**那个义项。两者不是一回事 —— 宁可少一个词性，
    // 也不能让卡上出现「n. 交往；厮混」这种自相矛盾。
    final meaningFromDict = _blank(it.meaning) && _text(hit?.entry.zh) != null;
    if (sources[VocabField.partOfSpeech] != VocabFieldSource.manual &&
        _blank(it.partOfSpeech) &&
        pos.isNotEmpty &&
        meaningFromDict) {
      partOfSpeech = pos;
      sources[VocabField.partOfSpeech] = VocabFieldSource.dict;
    }
    // 复合词：按后缀判出来的词性，不记来源。
    if (_blank(it.partOfSpeech) && partOfSpeech == null && compoundPos != null) {
      partOfSpeech = compoundPos;
    }

    final zh = _text(hit?.entry.zh);
    final gloss = zh == null
        ? ''
        : cleanGloss(glossForPos(zh, pos.isEmpty ? (hit?.entry.pos ?? '') : pos));
    if (sources[VocabField.meaning] != VocabFieldSource.manual &&
        _blank(it.meaning) &&
        gloss.isNotEmpty) {
      meaning = gloss;
      sources[VocabField.meaning] = VocabFieldSource.dict;
    }

    final en = _text(hit?.entry.en);
    final english = en == null ? '' : cleanGloss(glossForPos(en, pos));
    if (sources[VocabField.definition] != VocabFieldSource.manual &&
        _blank(it.definition) &&
        english.isNotEmpty) {
      definition = english;
      sources[VocabField.definition] = VocabFieldSource.dict;
    }

    if (phonetic == null &&
        partOfSpeech == null &&
        meaning == null &&
        definition == null) {
      return it;
    }
    filled++;
    final meaningNow = meaning ?? it.meaning;
    return reconcileSense(
      it.copyWith(
        phonetic: phonetic == null ? null : () => phonetic,
        partOfSpeech: partOfSpeech == null ? null : () => partOfSpeech,
        meaning: meaning == null ? null : () => meaning,
        definition: definition == null ? null : () => definition,
        status: it.status == VocabStatus.unqueried && !_blank(meaningNow)
            ? VocabStatus.queried
            : null,
        fieldSources: () => sources.isEmpty ? null : sources,
        updatedAt: iso,
      ),
    );
  }).toList(growable: false);

  return DictEnrichResult(
    library: filled == 0 ? library : library.copyWith(items: items),
    filled: filled,
  );
}

String? _text(String? value) {
  final t = (value ?? '').trim();
  return t.isEmpty ? null : t;
}

bool _blank(String? value) => _text(value) == null;
