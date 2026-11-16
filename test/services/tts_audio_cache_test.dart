import 'dart:io';

import 'package:dlaoshi_app/core/tts_audio_cache.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/tts_audio_cache.dart';
import 'package:dlaoshi_app/services/tts_audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

SavedArticle _article(String id, List<String> texts) {
  final sentences = [
    for (var i = 0; i < texts.length; i++)
      Sentence(id: 's${i + 1}', paraId: 'p1', text: texts[i]),
  ];
  return SavedArticle(
    id: id,
    title: 'Title $id',
    sentences: sentences,
    paragraphs: [
      Paragraph(id: 'p1', sentenceIds: [for (final s in sentences) s.id]),
    ],
    updatedAt: '2026-11-16T00:00:00Z',
  );
}

void main() {
  late Directory temp;
  late TtsAudioCache cache;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dlaoshi_tts_cache_');
    cache = TtsAudioCache(rootDir: temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<Directory> writeStaging(
    String articleId,
    String key,
    int bytes,
  ) async {
    final staging = await cache.createStagingDir(articleId);
    await File(
      p.join(staging.path, '$key.wav'),
    ).writeAsBytes(List.filled(bytes, 7));
    return staging;
  }

  group('TtsAudioCache', () {
    test('提交后能按原文 + 音色 + 版本命中', () async {
      const text = 'Hello world.';
      const voice = 'af_heart';
      const revision = 'rev';
      final key = ttsAudioKey(text, voice, revision);
      final staging = await writeStaging('saved:1', key, 3);
      final entry = await cache.commitArticle(
        articleId: 'saved:1',
        title: 'Title',
        voice: voice,
        revision: revision,
        stagingDir: staging,
        files: {key: '$key.wav'},
        bytes: 3,
        sentenceCount: 1,
      );

      expect(entry.bytes, 3);
      expect(await cache.entryOf('saved:1'), entry);
      final hit = await cache.lookup(
        text: text,
        voice: voice,
        revision: revision,
      );
      expect(hit, isNotNull);
      expect(await hit!.length(), 3);
      expect(
        await cache.lookup(text: text, voice: voice, revision: 'other'),
        isNull,
      );
    });

    test('最多保留 2 篇，第三篇淘汰最久没用的', () async {
      Future<void> commit(String id) async {
        final key = ttsAudioKey(id, 'af_heart', 'rev');
        final staging = await writeStaging(id, key, 1);
        await cache.commitArticle(
          articleId: id,
          title: id,
          voice: 'af_heart',
          revision: 'rev',
          stagingDir: staging,
          files: {key: '$key.wav'},
          bytes: 1,
          sentenceCount: 1,
        );
      }

      await commit('a');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await commit('b');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await commit('c');

      expect(await cache.entryOf('a'), isNull);
      expect(await cache.entryOf('b'), isNotNull);
      expect(await cache.entryOf('c'), isNotNull);
      final entries = await cache.entries();
      expect(entries.length, 2);
    });

    test('删除会同时删索引和文件', () async {
      const text = 'Hello.';
      const voice = 'af_heart';
      const revision = 'rev';
      final key = ttsAudioKey(text, voice, revision);
      final staging = await writeStaging('saved:1', key, 1);
      await cache.commitArticle(
        articleId: 'saved:1',
        title: 'T',
        voice: voice,
        revision: revision,
        stagingDir: staging,
        files: {key: '$key.wav'},
        bytes: 1,
        sentenceCount: 1,
      );
      final hit = await cache.lookup(
        text: text,
        voice: voice,
        revision: revision,
      );
      expect(hit, isNotNull);
      expect(await cache.deleteArticle('saved:1'), isTrue);
      expect(await cache.entryOf('saved:1'), isNull);
      expect(await hit!.exists(), isFalse);
    });

    test('坏索引按空缓存处理，不抛异常', () async {
      final root = Directory(p.join(temp.path, 'tts_audio'));
      await root.create(recursive: true);
      await File(
        p.join(root.path, 'index.json'),
      ).writeAsString('{not json');
      final broken = TtsAudioCache(rootDir: temp);
      expect(await broken.entries(), isEmpty);
    });

    test('启动时清掉上次没完成的 staging', () async {
      final staging = await cache.createStagingDir('saved:1');
      expect(await staging.exists(), isTrue);
      final again = TtsAudioCache(rootDir: temp);
      await again.ensureLoaded();
      expect(await staging.exists(), isFalse);
    });
  });

  group('TtsAudioService', () {
    TtsAudioService service() =>
        TtsAudioService(cache: cache, revision: 'test-rev');

    test('逐句合成、重复句子只合成一次、进度到齐', () async {
      final article = _article('saved:1', [
        'Hello world.',
        'Second sentence.',
        'Hello world.',
      ]);
      final calls = <String>[];
      final progress = <String>[];
      final result = await service().generate(
        article,
        voice: 'af_heart',
        synthesize: (text, path) async {
          calls.add(text);
          await File(path).writeAsBytes(List.filled(100, 7));
        },
        onProgress: (done, total) => progress.add('$done/$total'),
      );

      expect(calls, ['Hello world.', 'Second sentence.']);
      expect(progress, ['1/3', '2/3', '3/3']);
      expect(result.entry.sentenceCount, 3);
      expect(result.entry.bytes, 200);
      expect(calls.length, 2);

      final hit = await cache.lookup(
        text: 'Second sentence.',
        voice: 'af_heart',
        revision: 'test-rev',
      );
      expect(hit, isNotNull);
    });

    test('取消会删临时目录，不落盘', () async {
      final article = _article('saved:1', ['One.', 'Two.', 'Three.']);
      var calls = 0;
      await expectLater(
        service().generate(
          article,
          voice: 'af_heart',
          synthesize: (text, path) async {
            calls++;
            await File(path).writeAsBytes([1, 2, 3]);
          },
          isCancelled: () => calls >= 1,
        ),
        throwsA(isA<TtsAudioCancelled>()),
      );
      expect(calls, 1);
      expect(await cache.entryOf('saved:1'), isNull);
      final staging = Directory(p.join(temp.path, 'tts_audio', 'staging'));
      final left = staging.existsSync()
          ? await staging.list().toList()
          : const <FileSystemEntity>[];
      expect(left, isEmpty);
    });

    test('某一句失败会整篇不落盘', () async {
      final article = _article('saved:1', ['One.', 'Two.']);
      await expectLater(
        service().generate(
          article,
          voice: 'af_heart',
          synthesize: (text, path) async {
            if (text == 'Two.') throw StateError('boom');
            await File(path).writeAsBytes([1]);
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(await cache.entryOf('saved:1'), isNull);
    });

    test('空文章直接报错', () async {
      final article = _article('saved:1', ['   ']);
      await expectLater(
        service().generate(
          article,
          voice: 'af_heart',
          synthesize: (text, path) async {},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
