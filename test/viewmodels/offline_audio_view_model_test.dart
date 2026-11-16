import 'dart:io';

import 'package:dlaoshi_app/core/tts_provider.dart' show TtsProvider;
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/tts_prefs.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/tts_audio_cache.dart';
import 'package:dlaoshi_app/services/tts_audio_service.dart';
import 'package:dlaoshi_app/viewmodels/offline_audio_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late TtsPrefs ttsPrefs;
  late TtsAudioCache cache;
  late TtsAudioService service;

  setUp(() async {
    ttsPrefs = TtsPrefs(PrefsStore.memory());
    await ttsPrefs.saveProvider(TtsProvider.kokoro);
    await ttsPrefs.saveVoice('af_heart');
    temp = await Directory.systemTemp.createTemp('dlaoshi_offline_vm_');
    cache = TtsAudioCache(rootDir: temp);
    service = TtsAudioService(cache: cache, revision: 'test-rev');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  OfflineAudioViewModel makeVm({
    Future<void> Function(String text, String path)? synthesize,
  }) {
    return OfflineAudioViewModel(
      cache: cache,
      service: service,
      prefs: ttsPrefs,
      synthesizeToFile: synthesize ??
          (text, path) async {
            await File(path).writeAsBytes([1, 2, 3]);
          },
    );
  }

  test('生成后状态变 ready，按原文能命中缓存；删除后回 idle', () async {
    final article = _article('saved:1', [
      'Global growth slowed down.',
      'The outlook is uncertain.',
    ]);
    final vm = makeVm();
    addTearDown(vm.dispose);
    await vm.load(article.id);
    expect(vm.status, OfflineAudioStatus.idle);

    await vm.generate(article);
    expect(vm.status, OfflineAudioStatus.ready);
    expect(vm.error, isNull);
    expect(vm.entry, isNotNull);
    expect(vm.entry!.sentenceCount, article.sentences.length);
    expect(vm.bytes, greaterThan(0));

    final hit = await cache.lookup(
      text: article.sentences.first.text,
      voice: 'af_heart',
      revision: 'test-rev',
    );
    expect(hit, isNotNull);
    expect(await hit!.exists(), isTrue);

    await vm.delete();
    expect(vm.status, OfflineAudioStatus.idle);
    expect(vm.entry, isNull);
    expect(vm.bytes, 0);
  });

  test('重新 load 能读回缓存状态', () async {
    final article = _article('saved:1', ['One.', 'Two.']);
    final first = makeVm();
    addTearDown(first.dispose);
    await first.load(article.id);
    await first.generate(article);
    final bytes = first.bytes;

    final second = makeVm();
    addTearDown(second.dispose);
    await second.load(article.id);
    expect(second.status, OfflineAudioStatus.ready);
    expect(second.entry, isNotNull);
    expect(second.bytes, bytes);
  });

  test('不是 Kokoro 档时不生成，并给出提示', () async {
    final article = _article('saved:1', ['One.']);
    final vm = makeVm();
    addTearDown(vm.dispose);
    await vm.load(article.id);
    await ttsPrefs.saveProvider(TtsProvider.system);

    await vm.generate(article);
    expect(vm.status, OfflineAudioStatus.failed);
    expect(vm.error, contains('Kokoro'));
    expect(vm.entry, isNull);
  });

  test('取消后不落盘，状态回到 idle', () async {
    late OfflineAudioViewModel vm;
    vm = makeVm(
      synthesize: (text, path) async {
        await File(path).writeAsBytes([1, 2, 3]);
        vm.cancel();
      },
    );
    addTearDown(vm.dispose);
    final article = _article('saved:1', ['One.', 'Two.']);
    await vm.load(article.id);

    await vm.generate(article);
    expect(vm.status, OfflineAudioStatus.idle);
    expect(vm.entry, isNull);
    expect(await cache.entryOf(article.id), isNull);
  });
}
