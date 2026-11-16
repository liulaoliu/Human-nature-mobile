/// 离线朗读缓存的纯规则：key、容量、LRU 淘汰、索引解析。
///
/// 这里不碰文件系统；实际读写见 `lib/services/tts_audio_cache.dart`。
/// 放到 core 是为了能单测：手机存储有限，最多留几篇、怎么淘汰、坏索引
/// 怎么丢弃，全是可验证的规则。
library;

import 'dart:convert';

import '../models/tts_audio.dart';

/// 最多保留几篇的音频。用户 2026-11-16 明确要求「只存 2 篇」。
const int ttsAudioMaxArticles = 2;

/// 预生成朗读用 Kokoro 原始 PCM：24kHz / 16bit / 单声道 = 48KB/s。
///
/// 不走 AAC：vivo 的 MediaCodec 输出 ADTS 时帧边界错位，缓存音频会“读不准”。
/// 代价是一篇 800 词约 15MB，两篇约 30MB；先保证正确。
const int ttsAudioSampleRate = 24000;
const int ttsAudioBytesPerSecond = ttsAudioSampleRate * 2;

/// 估算语速（词/分钟）。Kokoro 默认语速大致在这个量级，界面只用来给个预期。
const int ttsAudioWordsPerMinute = 150;

/// 索引最多接受多少条；超出的当坏数据丢弃，避免一个巨大 JSON 拖慢启动。
const int ttsAudioMaxIndexEntries = 16;

/// 句子缓存的稳定 key（FNV-1a 32 位）。
///
/// 不用 `String.hashCode`：Dart 的字符串哈希不保证跨进程稳定，
/// 重启后就会全部 miss。FNV-1a 自己算，结果永远一样。
String ttsAudioKey(String text, String voice, String revision) {
  var hash = 0x811c9dc5;
  void mix(String value) {
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
  }

  mix(voice);
  mix('\u0000');
  mix(revision);
  mix('\u0000');
  mix(text);
  return hash.toRadixString(16).padLeft(8, '0');
}

/// 音频文件名：只用 key，查询时按 key 查索引里的映射。
String ttsAudioFileName(String text, String voice, String revision) =>
    '${ttsAudioKey(text, voice, revision)}.wav';

/// 文章缓存目录名：保留可读的 id + 稳定后缀，避免 `saved:123` 这类字符。
String ttsAudioArticleDirName(String articleId) {
  final safe = articleId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final short = safe.length <= 40 ? safe : safe.substring(0, 40);
  return '$short-${ttsAudioKey(articleId, '', '')}';
}

/// 估算一篇的 WAV 体积（字节）。只用于界面提示，不是精确值。
int estimateTtsAudioBytes(String text) {
  final words = RegExp(r"[A-Za-z0-9'’\-]+")
      .allMatches(text)
      .length;
  if (words == 0) return 0;
  final seconds = words * 60 / ttsAudioWordsPerMinute;
  return (seconds * ttsAudioBytesPerSecond).round();
}

/// 给人看的体积：1.3 MB / 860 KB。
String formatTtsAudioBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// 选出要淘汰的文章 id，保证留下来的不超过 [maxArticles]。
///
/// [keepArticleId] 永远不淘汰（刚生成 / 正在看的那篇）。其余按
/// `lastUsedMs` 从旧到新淘汰；时间相同按 id 排，保证结果确定。
List<String> ttsAudioEvictions(
  List<TtsAudioEntry> articles, {
  required String keepArticleId,
  int maxArticles = ttsAudioMaxArticles,
}) {
  if (articles.length <= maxArticles) return const [];
  final keepCount = articles.where((e) => e.articleId == keepArticleId).length;
  final others = articles
      .where((e) => e.articleId != keepArticleId)
      .toList()
    ..sort((a, b) {
      final byTime = a.lastUsedMs.compareTo(b.lastUsedMs);
      return byTime != 0 ? byTime : a.articleId.compareTo(b.articleId);
    });
  final allowed = maxArticles - keepCount;
  final overflow = others.length - (allowed < 0 ? 0 : allowed);
  if (overflow <= 0) return const [];
  return others.take(overflow).map((e) => e.articleId).toList();
}

/// 索引解析结果：好数据 + 丢弃条数。
class TtsAudioIndexParseResult {
  const TtsAudioIndexParseResult({
    required this.index,
    required this.dropped,
  });

  final TtsAudioIndex index;
  final int dropped;
}

/// 解析 `index.json`；坏条目逐条丢弃，不因为一条坏数据把整库清空。
TtsAudioIndexParseResult parseTtsAudioIndex(String raw) {
  const empty = TtsAudioIndex();
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const TtsAudioIndexParseResult(index: empty, dropped: 1);
  }
  if (decoded is! Map) {
    return const TtsAudioIndexParseResult(index: empty, dropped: 1);
  }
  final version = decoded['version'];
  if (version is! num || version.toInt() != 1) {
    return const TtsAudioIndexParseResult(index: empty, dropped: 1);
  }
  final rows = decoded['articles'];
  if (rows is! List) {
    return const TtsAudioIndexParseResult(index: empty, dropped: 1);
  }

  final entries = <TtsAudioEntry>[];
  final seen = <String>{};
  var dropped = 0;
  for (final row in rows) {
    if (entries.length >= ttsAudioMaxIndexEntries) {
      dropped++;
      continue;
    }
    final entry = _parseEntry(row);
    if (entry == null || !seen.add(entry.articleId)) {
      dropped++;
      continue;
    }
    entries.add(entry);
  }
  return TtsAudioIndexParseResult(
    index: TtsAudioIndex(version: 1, articles: entries),
    dropped: dropped,
  );
}

TtsAudioEntry? _parseEntry(Object? raw) {
  if (raw is! Map) return null;
  final articleId = _nonEmptyString(raw['articleId']);
  final title = _nonEmptyString(raw['title']);
  final voice = _nonEmptyString(raw['voice']);
  final revision = _nonEmptyString(raw['revision']);
  final createdAtMs = _nonNegativeInt(raw['createdAtMs']);
  final lastUsedMs = _nonNegativeInt(raw['lastUsedMs']);
  final bytes = _nonNegativeInt(raw['bytes']);
  final sentenceCount = _nonNegativeInt(raw['sentenceCount']);
  if (articleId == null ||
      title == null ||
      voice == null ||
      revision == null ||
      createdAtMs == null ||
      lastUsedMs == null ||
      bytes == null ||
      sentenceCount == null) {
    return null;
  }

  final rawFiles = raw['files'];
  if (rawFiles is! Map || rawFiles.length > 512) return null;
  final files = <String, String>{};
  for (final row in rawFiles.entries) {
    final key = row.key;
    final name = row.value;
    if (key is! String || name is! String) return null;
    if (!_validKey(key) || !_validFileName(name)) return null;
    files[key] = name;
  }
  return TtsAudioEntry(
    articleId: articleId,
    title: title,
    voice: voice,
    revision: revision,
    createdAtMs: createdAtMs,
    lastUsedMs: lastUsedMs,
    bytes: bytes,
    sentenceCount: sentenceCount,
    files: files,
  );
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 500) return null;
  return trimmed;
}

int? _nonNegativeInt(Object? value) {
  if (value is! num || !value.isFinite) return null;
  final intValue = value.toInt();
  if (intValue < 0 || intValue.toDouble() != value.toDouble()) return null;
  return intValue;
}

bool _validKey(String key) => RegExp(r'^[0-9a-f]{8}$').hasMatch(key);

/// 只允许我们自己生成的 `xxxxxxxx.wav`，杜绝 `../` 之类的路径穿越。
bool _validFileName(String name) =>
    RegExp(r'^[0-9a-f]{8}\.wav$').hasMatch(name);

/// 索引写盘用的 JSON（服务层调用；模型自身不碰序列化）。
Map<String, Object?> ttsAudioIndexToJson(TtsAudioIndex index) {
  return {
    'version': index.version,
    'articles': [
      for (final entry in index.articles)
        {
          'articleId': entry.articleId,
          'title': entry.title,
          'voice': entry.voice,
          'revision': entry.revision,
          'createdAtMs': entry.createdAtMs,
          'lastUsedMs': entry.lastUsedMs,
          'bytes': entry.bytes,
          'sentenceCount': entry.sentenceCount,
          'files': entry.files,
        },
    ],
  };
}

String encodeTtsAudioIndex(TtsAudioIndex index) =>
    jsonEncode(ttsAudioIndexToJson(index));
