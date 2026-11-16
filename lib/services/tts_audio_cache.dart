/// 离线朗读音频的文件缓存。
///
/// 目录：
///   `<支持目录>/tts_audio/index.json`
///   `<支持目录>/tts_audio/articles/<文章目录>/<key>.wav`
///   `<支持目录>/tts_audio/staging/...`（生成中的临时文件，失败/取消即删）
///
/// 规则（最多 2 篇、LRU 淘汰、坏索引守卫）全在
/// `lib/core/tts_audio_cache.dart`，这里只负责落盘。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/tts_audio_cache.dart';
import '../models/tts_audio.dart';

/// 离线朗读缓存的文件实现。
class TtsAudioCache {
  TtsAudioCache({Directory? rootDir, this.maxArticles = ttsAudioMaxArticles})
    : _rootOverride = rootDir;

  /// 测试用：直接指定缓存根目录；不传就走应用支持目录。
  final Directory? _rootOverride;

  /// 最多保留几篇。
  final int maxArticles;

  TtsAudioIndex _index = const TtsAudioIndex();
  bool _loaded = false;
  Future<void>? _loading;
  Directory? _root;

  /// 全部索引（按最近使用时间不保证排序）。
  Future<List<TtsAudioEntry>> entries() async {
    await ensureLoaded();
    return List.unmodifiable(_index.articles);
  }

  /// 某篇的缓存条目；没有返回 null。
  Future<TtsAudioEntry?> entryOf(String articleId) async {
    await ensureLoaded();
    for (final entry in _index.articles) {
      if (entry.articleId == articleId) return entry;
    }
    return null;
  }

  /// 按「原文 + 音色 + 模型版本」找音频文件；命中返回文件，否则 null。
  Future<File?> lookup({
    required String text,
    required String voice,
    required String revision,
  }) async {
    await ensureLoaded();
    final key = ttsAudioKey(text, voice, revision);
    final root = await _ensureRoot();
    for (final entry in _index.articles) {
      if (entry.voice != voice || entry.revision != revision) continue;
      final name = entry.files[key];
      if (name == null) continue;
      final file = File(
        p.join(
          root.path,
          'articles',
          ttsAudioArticleDirName(entry.articleId),
          name,
        ),
      );
      try {
        if (await file.exists() && await file.length() > 0) return file;
      } catch (e) {
        debugPrint('离线朗读缓存检查失败：$e');
      }
    }
    return null;
  }

  /// 建一个本次生成专用的临时目录。
  Future<Directory> createStagingDir(String articleId) async {
    await ensureLoaded();
    final root = await _ensureRoot();
    final dir = Directory(
      p.join(
        root.path,
        'staging',
        '${ttsAudioArticleDirName(articleId)}-'
            '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// 丢掉一次没完成的生成（取消 / 出错）。
  Future<void> discardStaging(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('清理离线朗读临时目录失败：$e');
    }
  }

  /// 生成成功后提交：临时目录改名为正式目录，写索引，顺带淘汰旧文章。
  Future<TtsAudioEntry> commitArticle({
    required String articleId,
    required String title,
    required String voice,
    required String revision,
    required Directory stagingDir,
    required Map<String, String> files,
    required int bytes,
    required int sentenceCount,
  }) async {
    await ensureLoaded();
    final root = await _ensureRoot();
    final articlesDir = Directory(p.join(root.path, 'articles'));
    await articlesDir.create(recursive: true);
    final target = Directory(
      p.join(articlesDir.path, ttsAudioArticleDirName(articleId)),
    );
    if (await target.exists()) await target.delete(recursive: true);
    await stagingDir.rename(target.path);

    final now = DateTime.now().millisecondsSinceEpoch;
    TtsAudioEntry? old;
    for (final e in _index.articles) {
      if (e.articleId == articleId) {
        old = e;
        break;
      }
    }
    final entry = TtsAudioEntry(
      articleId: articleId,
      title: title,
      voice: voice,
      revision: revision,
      createdAtMs: old?.createdAtMs ?? now,
      lastUsedMs: now,
      bytes: bytes,
      sentenceCount: sentenceCount,
      files: Map.unmodifiable(files),
    );
    var next = [
      ..._index.articles.where((e) => e.articleId != articleId),
      entry,
    ];
    final evicted = ttsAudioEvictions(
      next,
      keepArticleId: articleId,
      maxArticles: maxArticles,
    );
    for (final id in evicted) {
      next = next.where((e) => e.articleId != id).toList();
      await _deleteArticleDir(root, id);
    }
    _index = TtsAudioIndex(version: 1, articles: next);
    await _writeIndex(root);
    return entry;
  }

  /// 删掉某篇的缓存；返回是否真的删了条目。
  Future<bool> deleteArticle(String articleId) async {
    await ensureLoaded();
    final had = _index.articles.any((e) => e.articleId == articleId);
    if (!had) return false;
    final root = await _ensureRoot();
    _index = TtsAudioIndex(
      version: 1,
      articles: _index.articles.where((e) => e.articleId != articleId).toList(),
    );
    await _deleteArticleDir(root, articleId);
    await _writeIndex(root);
    return true;
  }

  /// 更新「最近使用时间」（LRU 用）。60 秒内重复调用不写盘。
  Future<void> touch(String articleId) async {
    await ensureLoaded();
    final index = _index.articles.indexWhere((e) => e.articleId == articleId);
    if (index < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = _index.articles[index];
    if (now - old.lastUsedMs < 60000) return;
    final articles = List<TtsAudioEntry>.of(_index.articles);
    articles[index] = old.copyWith(lastUsedMs: now);
    _index = TtsAudioIndex(version: 1, articles: articles);
    try {
      await _writeIndex(await _ensureRoot());
    } catch (e) {
      debugPrint('更新离线朗读缓存时间失败：$e');
    }
  }

  /// 载入索引（只读一次）；失败 / 坏条目不会让 App 起不来。
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    final loading = _loading;
    if (loading != null) return loading;
    final future = _load();
    _loading = future;
    return future.whenComplete(() {
      _loading = null;
    });
  }

  Future<void> _load() async {
    final root = await _ensureRoot();
    // 上次 App 被杀时留下的 staging 一定是没完成的生成，直接清掉。
    final staging = Directory(p.join(root.path, 'staging'));
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } catch (e) {
      debugPrint('清理离线朗读 staging 失败：$e');
    }
    final indexFile = File(p.join(root.path, 'index.json'));
    try {
      if (await indexFile.exists()) {
        final parsed = parseTtsAudioIndex(await indexFile.readAsString());
        _index = parsed.index;
        if (parsed.dropped > 0) {
          debugPrint('离线朗读索引丢弃了 ${parsed.dropped} 条坏数据');
        }
      }
    } catch (e) {
      debugPrint('读取离线朗读索引失败，按空缓存处理：$e');
      _index = const TtsAudioIndex();
    }
    _loaded = true;
  }

  Future<Directory> _ensureRoot() async {
    final existing = _root;
    if (existing != null) return existing;
    final base = _rootOverride ?? await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'tts_audio'));
    await root.create(recursive: true);
    _root = root;
    return root;
  }

  Future<void> _writeIndex(Directory root) async {
    final file = File(p.join(root.path, 'index.json'));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encodeTtsAudioIndex(_index), flush: true);
    try {
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (e) {
      // Windows 上 rename 覆盖偶发失败；退化成直接写。
      debugPrint('离线朗读索引改名失败，改为直接写：$e');
      await file.writeAsString(encodeTtsAudioIndex(_index), flush: true);
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {
        // 忽略。
      }
    }
  }

  Future<void> _deleteArticleDir(Directory root, String articleId) async {
    final dir = Directory(
      p.join(root.path, 'articles', ttsAudioArticleDirName(articleId)),
    );
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('删除离线朗读目录失败：$e');
    }
  }
}
