/// 词库 → 落盘 JSON 的**唯一序列化口径**。
///
/// 为什么需要它：Web 版词库是普通对象，`JSON.stringify(library)` 直接就是落盘形状；
/// Dart 是强类型，不写这一层就只能各处手搓 Map，迟早出现「两个地方序列化结果不一样」，
/// 进而让「内容没变就别写库」的快路径失效（每次都判成变了，白写一次整库）。
///
/// 规矩：
/// - **只输出有值的可选字段**：Web 版靠 `undefined` 被 `JSON.stringify` 丢掉，
///   这里照它来，别写成 `"kind": null`（否则同一份数据在两边序列化结果不同）；
/// - 明确定义为 `null` 的四个核心字段（phonetic / partOfSpeech / meaning / definition）
///   与 `source` 始终输出，形状稳定好对账；
/// - **反序列化不在这里**：一律走 `lib/core/migrations.dart:363` 的
///   `migrateLibrary`（它负责丢弃坏条目、补默认值、去重、把共享句子原文补回来）。
///
/// 字段名与 Web 版 `src/types/document.ts` 一一对应，不改名。
library;

import 'dart:convert';

import '../../models/vocab.dart';
import '../vocab_fields.dart';

/// 单个词条 → JSON。
Map<String, Object?> vocabItemToJson(VocabItem item) {
  final out = <String, Object?>{
    'id': item.id,
    'word': item.word,
    'lemma': item.lemma,
  };
  // 类型缺省 = 普通单词；写出来只会让 JSON 变脏。
  if (item.kind != null) out['kind'] = item.kind!.name;
  if (item.langPointId != null) out['langPointId'] = item.langPointId;
  out['phonetic'] = item.phonetic;
  out['partOfSpeech'] = item.partOfSpeech;
  out['meaning'] = item.meaning;
  if (item.grammarMarks != null && item.grammarMarks!.isNotEmpty) {
    out['grammarMarks'] = List<String>.of(item.grammarMarks!);
  }
  out['definition'] = item.definition;

  final sources = item.fieldSources;
  if (sources != null && sources.isNotEmpty) {
    out['fieldSources'] = <String, Object?>{
      for (final field in vocabFields)
        if (sources[field] != null)
          vocabFieldName(field): vocabFieldSourceName(sources[field]!),
    };
  }

  out['usage'] = List<String>.of(item.usage);
  if (item.phrases != null && item.phrases!.isNotEmpty) {
    out['phrases'] = List<String>.of(item.phrases!);
  }
  if (item.idioms != null && item.idioms!.isNotEmpty) {
    out['idioms'] = List<String>.of(item.idioms!);
  }
  out['examples'] = item.examples.map(_exampleToJson).toList(growable: false);
  out['source'] = item.source == null ? null : _sourceToJson(item.source!);
  if (item.contexts != null && item.contexts!.isNotEmpty) {
    out['contexts'] = item.contexts!.map(_contextToJson).toList(growable: false);
  }
  out['status'] = vocabStatusName(item.status);
  out['note'] = item.note;
  out['tags'] = List<String>.of(item.tags);
  if (item.lastPrintedAt != null) out['lastPrintedAt'] = item.lastPrintedAt;
  if (item.confusables != null && item.confusables!.isNotEmpty) {
    out['confusables'] =
        item.confusables!.map(_confusableToJson).toList(growable: false);
  }
  if (item.confusablesSource != null) {
    out['confusablesSource'] = item.confusablesSource!.name;
  }
  if (item.priorityUntil != null) out['priorityUntil'] = item.priorityUntil;
  out['reviewState'] = reviewStateToJson(item.reviewState);
  out['createdAt'] = item.createdAt;
  out['updatedAt'] = item.updatedAt;
  return out;
}

/// 复习状态 → JSON。
///
/// 七个字段**全部**输出（包括 0 与 null 的 `due`）：复习排期是增量算出来的，
/// 少一个字段读回来就得靠猜，猜错的代价是「到期队列乱掉」。
Map<String, Object?> reviewStateToJson(ReviewState state) => <String, Object?>{
      'ease': state.ease,
      'due': state.due,
      'interval': state.interval,
      'repetitions': state.repetitions,
      'lapses': state.lapses,
      'relearn': state.relearn,
      'meaningPasses': state.meaningPasses,
    };

Map<String, Object?> _exampleToJson(VocabExample ex) => <String, Object?>{
      'text': ex.text,
      if (ex.translation != null) 'translation': ex.translation,
      if (ex.articleId != null) 'articleId': ex.articleId,
      if (ex.fileName != null) 'fileName': ex.fileName,
      if (ex.sentenceId != null) 'sentenceId': ex.sentenceId,
      if (ex.origin != null) 'origin': ex.origin!.name,
    };

Map<String, Object?> _sourceToJson(VocabSource source) => <String, Object?>{
      'articleId': source.articleId,
      'fileName': source.fileName,
      'sentenceId': source.sentenceId,
      'sentenceText': source.sentenceText,
    };

Map<String, Object?> _contextToJson(VocabContext ctx) => <String, Object?>{
      'articleId': ctx.articleId,
      'fileName': ctx.fileName,
      'sentenceId': ctx.sentenceId,
      'sentenceText': ctx.sentenceText,
      if (ctx.meaning != null) 'meaning': ctx.meaning,
      'at': ctx.at,
    };

Map<String, Object?> _confusableToJson(VocabConfusable c) => <String, Object?>{
      'word': c.word,
      if (c.meaning != null) 'meaning': c.meaning,
    };

/// 按篇收录条目 → JSON。
Map<String, Object?> articleVocabEntryToJson(ArticleVocabEntry entry) =>
    <String, Object?>{
      'articleId': entry.articleId,
      'lemma': entry.lemma,
      'origin': entry.origin.name,
      if (entry.via != null) 'via': entry.via!.name,
      'addedAt': entry.addedAt,
      if (entry.sentenceId != null) 'sentenceId': entry.sentenceId,
      if (entry.sentenceText != null) 'sentenceText': entry.sentenceText,
      if (entry.meaning != null) 'meaning': entry.meaning,
      if (entry.meaningSource != null) 'meaningSource': entry.meaningSource!.name,
      if (entry.printedAt != null) 'printedAt': entry.printedAt,
    };

/// 墓碑 → JSON。
Map<String, Object?> vocabTombstoneToJson(VocabTombstone stone) =>
    <String, Object?>{
      'kind': stone.kind.name,
      'key': stone.key,
      'at': stone.at,
      if (stone.lemma != null) 'lemma': stone.lemma,
    };

/// 整库 → JSON。
///
/// `articleEntries` / `tombstones` / `sentenceTexts` 为空时**不输出**：
/// 老库没有这三段，读完再写回时也不该凭空多出三个空字段。
Map<String, Object?> vocabLibraryToJson(VocabLibrary library) {
  final out = <String, Object?>{
    'schemaVersion': library.schemaVersion,
    'items': library.items.map(vocabItemToJson).toList(growable: false),
  };
  if (library.articleEntries.isNotEmpty) {
    out['articleEntries'] = library.articleEntries
        .map(articleVocabEntryToJson)
        .toList(growable: false);
  }
  if (library.tombstones.isNotEmpty) {
    out['tombstones'] =
        library.tombstones.map(vocabTombstoneToJson).toList(growable: false);
  }
  if (library.sentenceTexts.isNotEmpty) {
    out['sentenceTexts'] = <String, Object?>{
      for (final e in library.sentenceTexts.entries) e.key: e.value,
    };
  }
  return out;
}

/// 落盘用的紧凑 JSON（不含空白）。
///
/// 单独提出来，保证「写库」与「内容没变就跳过」比较的一定是同一份口径。
String encodeVocabLibrary(VocabLibrary library) =>
    jsonEncode(vocabLibraryToJson(library));
