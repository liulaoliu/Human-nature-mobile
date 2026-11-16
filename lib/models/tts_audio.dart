/// 离线朗读音频缓存的数据模型（纯数据，不含 JSON 解析）。
///
/// 缓存本身不是用户资料：坏了最多重新生成，所以解析守卫放在
/// `lib/core/tts_audio_cache.dart`，坏条目丢弃并计数，不静默清空整个索引。
library;

/// 一篇文章已经生成好的离线朗读。
class TtsAudioEntry {
  const TtsAudioEntry({
    required this.articleId,
    required this.title,
    required this.voice,
    required this.revision,
    required this.createdAtMs,
    required this.lastUsedMs,
    required this.bytes,
    required this.sentenceCount,
    required this.files,
  });

  final String articleId;
  final String title;

  /// 生成时用的音色 id（换了音色就重新生成，不混放）。
  final String voice;

  /// 模型版本（`kokoroAssetsRevision`）；换模型后旧缓存不再命中。
  final String revision;

  final int createdAtMs;
  final int lastUsedMs;

  /// 这一篇所有音频文件的总字节数（界面显示用）。
  final int bytes;

  /// 生成时处理的非空句子数。
  final int sentenceCount;

  /// 句子 key → 音频文件名（只存文件名，目录由 articleId 推导）。
  final Map<String, String> files;

  TtsAudioEntry copyWith({
    String? articleId,
    String? title,
    String? voice,
    String? revision,
    int? createdAtMs,
    int? lastUsedMs,
    int? bytes,
    int? sentenceCount,
    Map<String, String>? files,
  }) {
    return TtsAudioEntry(
      articleId: articleId ?? this.articleId,
      title: title ?? this.title,
      voice: voice ?? this.voice,
      revision: revision ?? this.revision,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      lastUsedMs: lastUsedMs ?? this.lastUsedMs,
      bytes: bytes ?? this.bytes,
      sentenceCount: sentenceCount ?? this.sentenceCount,
      files: files ?? this.files,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TtsAudioEntry &&
        other.articleId == articleId &&
        other.title == title &&
        other.voice == voice &&
        other.revision == revision &&
        other.createdAtMs == createdAtMs &&
        other.lastUsedMs == lastUsedMs &&
        other.bytes == bytes &&
        other.sentenceCount == sentenceCount &&
        _mapEq(other.files, files);
  }

  @override
  int get hashCode => Object.hash(
    articleId,
    title,
    voice,
    revision,
    createdAtMs,
    lastUsedMs,
    bytes,
    sentenceCount,
  );

  @override
  String toString() =>
      'TtsAudioEntry($articleId, "$title", $sentenceCount 句, $bytes B)';
}

/// 缓存索引（`index.json`）的内存形态。
class TtsAudioIndex {
  const TtsAudioIndex({this.version = 1, this.articles = const []});

  final int version;
  final List<TtsAudioEntry> articles;

  TtsAudioIndex copyWith({int? version, List<TtsAudioEntry>? articles}) {
    return TtsAudioIndex(
      version: version ?? this.version,
      articles: articles ?? this.articles,
    );
  }
}

bool _mapEq(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
