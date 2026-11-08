/// 已保存文章 → JSON（落盘形状）。
///
/// 只管**写出**：读回来一律走 `lib/core/backup_parse.dart` 的守卫
/// （`parseBackupPayload` 会逐句校验、补默认值、丢弃坏条目）。
/// 这样「写出去的形状」永远只有一份定义，读进来也只有一份校验。
///
/// 形状照 Web 版文章 payload（`src/types/document.ts` 的 `SavedArticle`），
/// 空列表 / null 一律**不写**：JSON 小一截，且写两遍结果一致
/// （否则「保存 → 读回 → 再保存」会一直认为内容变了，白白重压一次 gzip）。
library;

import '../models/document.dart';
import '../models/vocab.dart';

/// 评论状态：七个字段全写（它是算法输入，缺一个就会让复习节奏漂移）。
Map<String, Object?> reviewStateJson(ReviewState state) => <String, Object?>{
      'ease': state.ease,
      'due': state.due,
      'interval': state.interval,
      'repetitions': state.repetitions,
      'lapses': state.lapses,
      'relearn': state.relearn,
      'meaningPasses': state.meaningPasses,
    };

/// 单句。
Map<String, Object?> sentenceToJson(Sentence s) {
  final out = <String, Object?>{
    'id': s.id,
    'paraId': s.paraId,
    'text': s.text,
  };
  final audio = s.audio;
  if (audio != null) {
    out['audio'] = <String, Object?>{'start': audio.start, 'end': audio.end};
  }
  _put(out, 'translation', s.translation);
  _put(out, 'grammarNote', s.grammarNote);
  _putList(out, 'collocations', s.collocations);
  _putList(out, 'vocab', s.vocab);
  final language = s.language;
  if (language != null) out['language'] = languageToJson(language);
  final languages = s.languages;
  if (languages != null && languages.isNotEmpty) {
    out['languages'] = [for (final l in languages) languageToJson(l)];
  }
  _putList(out, 'tags', s.tags);
  out['reviewState'] = reviewStateJson(s.reviewState);
  return out;
}

/// 句子级语言点。
Map<String, Object?> languageToJson(SentenceLanguage l) {
  final out = <String, Object?>{};
  _put(out, 'structure', l.structure);
  _put(out, 'grammar', l.grammar);
  _putList(out, 'idioms', l.idioms);
  _putList(out, 'phrases', l.phrases);
  _putList(out, 'usage', l.usage);
  final source = l.source;
  if (source != null) out['source'] = source.name;
  _put(out, 'at', l.at);
  return out;
}

/// 段落。
Map<String, Object?> paragraphToJson(Paragraph p) => <String, Object?>{
      'id': p.id,
      'sentenceIds': List<String>.from(p.sentenceIds),
    };

/// 整篇。
Map<String, Object?> articleToJson(SavedArticle a) {
  final out = <String, Object?>{
    'id': a.id,
    'title': a.title,
    'text': a.text,
    'paragraphs': [for (final p in a.paragraphs) paragraphToJson(p)],
    'sentences': [for (final s in a.sentences) sentenceToJson(s)],
    'updatedAt': a.updatedAt,
  };
  _put(out, 'book', a.book);
  _put(out, 'sourceKey', a.sourceKey);
  final origin = a.origin;
  if (origin != null) out['origin'] = origin.name;
  final createdAt = a.createdAt;
  if (createdAt != null) out['createdAt'] = createdAt;
  final golden = a.golden;
  if (golden != null && golden.isNotEmpty) {
    out['golden'] = Map<String, Object?>.from(golden);
  }
  return out;
}

/// 这篇里出现过的生词数（去重）。
///
/// 与 Web 版 `saveArticle` 同一口径：按句子里 `vocab` 的词形算，
/// **不比词库**——词库里删了词，文章的计数也不跟着变，它是「当时标了多少」。
int articleWordCount(SavedArticle a) {
  final seen = <String>{};
  for (final s in a.sentences) {
    for (final w in s.vocab) {
      final t = w.trim();
      if (t.isNotEmpty) seen.add(t);
    }
  }
  return seen.length;
}

void _put(Map<String, Object?> out, String key, String? value) {
  if (value == null || value.isEmpty) return;
  out[key] = value;
}

void _putList(Map<String, Object?> out, String key, List<String>? value) {
  if (value == null || value.isEmpty) return;
  out[key] = List<String>.from(value);
}
