/// 「预生成朗读」的编排：逐句合成 → 写临时目录 → 一次性提交缓存。
///
/// 为什么逐句：Kokoro 一次只合成一小段，逐句能显示进度、能取消，也能让
/// 某一句失败时整篇不落盘（避免半篇缓存被当成完整音频）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/tts_audio_cache.dart';
import '../core/tts_text.dart';
import '../models/document.dart';
import '../models/tts_audio.dart';
import 'kokoro_speech.dart' show kokoroAssetsRevision;
import 'tts_audio_cache.dart';

/// 生成取消（用户点了取消，或页面已关闭）。
class TtsAudioCancelled implements Exception {
  const TtsAudioCancelled();

  @override
  String toString() => '生成已取消';
}

/// 生成结果。
class TtsAudioGeneration {
  const TtsAudioGeneration({required this.entry});

  final TtsAudioEntry entry;
}

/// 把一篇文章的所有句子合成成 AAC 文件。
class TtsAudioService {
  TtsAudioService({
    required this.cache,
    this.revision = kokoroAssetsRevision,
  });

  final TtsAudioCache cache;

  /// 模型版本；换模型后旧缓存不命中。
  final String revision;

  /// [synthesize] 必须把 [text] 写成 [path] 处的音频；抛异常即中止整篇。
  Future<TtsAudioGeneration> generate(
    SavedArticle article, {
    required String voice,
    required Future<void> Function(String text, String path) synthesize,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sentences = article.sentences
        .map((s) => normalizeTtsText(s.text))
        .where((t) => t.isNotEmpty)
        .toList();
    if (sentences.isEmpty) {
      throw StateError('这篇文章没有可朗读的句子');
    }

    final staging = await cache.createStagingDir(article.id);
    final files = <String, String>{};
    try {
      var done = 0;
      for (final text in sentences) {
        if (isCancelled?.call() ?? false) {
          throw const TtsAudioCancelled();
        }
        final key = ttsAudioKey(text, voice, revision);
        final name = '$key.$ttsAudioFileExtension';
        final path = p.join(staging.path, name);
        final file = File(path);
        final ready = await file.exists() && await file.length() > 0;
        if (!ready) {
          // 原生侧正常 2–3 秒一句；60 秒还没回来当故障处理，别让界面永远转圈。
          await synthesize(text, path).timeout(const Duration(seconds: 60));
        }
        if (!await file.exists() || await file.length() == 0) {
          throw StateError('这一句没生成出音频');
        }
        files[key] = name;
        done++;
        onProgress?.call(done, sentences.length);
      }

      var bytes = 0;
      for (final name in files.values.toSet()) {
        bytes += await File(p.join(staging.path, name)).length();
      }
      final rawTitle = article.title.trim();
      final title = rawTitle.isEmpty
          ? article.id
          : (rawTitle.length > 200
                ? rawTitle.substring(0, 200)
                : rawTitle);
      final entry = await cache.commitArticle(
        articleId: article.id,
        title: title,
        voice: voice,
        revision: revision,
        stagingDir: staging,
        files: files,
        bytes: bytes,
        sentenceCount: sentences.length,
      );
      debugPrint(
        '离线朗读生成完成：${entry.sentenceCount} 句 / ${entry.bytes} B '
        '（${article.id}）',
      );
      return TtsAudioGeneration(entry: entry);
    } catch (_) {
      await cache.discardStaging(staging);
      if (isCancelled?.call() ?? false) throw const TtsAudioCancelled();
      rethrow;
    }
  }
}
