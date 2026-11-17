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

/// 把一篇文章的所有句子合成成音频文件（默认 AAC；原生编码器故障时退成 WAV）。
class TtsAudioService {
  TtsAudioService({
    required this.cache,
    this.revision = kokoroAssetsRevision,
    this.sentenceTimeout = const Duration(seconds: 60),
  });

  final TtsAudioCache cache;

  /// 模型版本；换模型后旧缓存不命中。
  final String revision;

  /// 单句最多等多久「醒着的时间」。
  ///
  /// 为什么不是 `Future.timeout`：Android 会把后台 App 整个进程冻结，原生合成
  /// 线程和 Dart 定时器一起停摆。按墙钟算超时，用户切出去再回来就会收到
  /// `TimeoutException`（2026-11-17 真机复现两次），整篇白跑。这里只累计
  /// 定时器真正跑起来的时间 —— 冻结/深度睡眠留下的空档不计。
  final Duration sentenceTimeout;

  /// [synthesize] 把 [text] 合成为音频，返回**实际**写出的文件路径
  /// （原生在 AAC 编码器故障时会退成 `.wav`，扩展名不能想当然）；抛异常即中止整篇。
  Future<TtsAudioGeneration> generate(
    SavedArticle article, {
    required String voice,
    required Future<String> Function(String text, String path) synthesize,
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
        final path = p.join(staging.path, '$key.$ttsAudioFileExtension');
        final file = File(path);
        final ready = await file.exists() && await file.length() > 0;
        var written = path;
        if (!ready) {
          // 原生侧正常几秒一句；醒着等满 [sentenceTimeout] 还没回来当故障处理，
          // 别让界面永远转圈。
          written = await _awakeTimeout(
            synthesize(text, path),
            '第 ${done + 1}/${sentences.length} 句',
          );
        }
        final out = File(written);
        if (!await out.exists() || await out.length() == 0) {
          throw StateError('这一句没生成出音频');
        }
        // 索引里存实际文件名：AAC 失败时原生写的是同名 `.wav`，扩展名会变。
        files[key] = p.basename(written);
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
          : (rawTitle.length > 200 ? rawTitle.substring(0, 200) : rawTitle);
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

  /// 等 [future]，但只累计进程「醒着」的时间。
  ///
  /// 定时器两次回调之间隔得比 [_freezeGap] 还久，说明进程被系统冻结 / 深度
  /// 睡眠过（Android 对后台 App 很常见），那一段不算超时。前台真卡死时
  /// 定时器正常走，[sentenceTimeout] 到了照样抛 —— 「别让界面永远转圈」还在。
  Future<T> _awakeTimeout<T>(Future<T> future, String what) {
    final done = Completer<T>();
    var last = DateTime.now();
    var awake = Duration.zero;
    late final Timer timer;
    timer = Timer.periodic(_tick, (_) {
      final now = DateTime.now();
      final delta = now.difference(last);
      last = now;
      if (delta <= _freezeGap) awake += delta;
      if (awake < sentenceTimeout) return;
      timer.cancel();
      if (!done.isCompleted) {
        done.completeError(
          TimeoutException(
            '$what 醒着算了 ${sentenceTimeout.inSeconds} 秒还没合成完',
            sentenceTimeout,
          ),
        );
      }
    });
    future
        .then<void>(
          (value) {
            if (!done.isCompleted) done.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!done.isCompleted) done.completeError(error, stack);
          },
        )
        .whenComplete(timer.cancel);
    return done.future;
  }

  /// 看门狗的检查间隔。
  static const Duration _tick = Duration(milliseconds: 250);

  /// 两次回调间隔超过它，就当中间被冻结过，不计入超时。
  static const Duration _freezeGap = Duration(seconds: 3);
}
