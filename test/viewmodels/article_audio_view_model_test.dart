import 'dart:async';
import 'dart:io';

import 'package:dlaoshi_app/core/tts_audio_cache.dart'
    show ttsAudioArticleDirName, ttsAudioKey;
import 'package:dlaoshi_app/core/tts_text.dart' show normalizeTtsText;
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/services/tts_audio_cache.dart';
import 'package:dlaoshi_app/services/tts_audio_player.dart';
import 'package:dlaoshi_app/viewmodels/article_audio_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _voice = 'af_heart';
const String _rev = 'test-rev';

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
    updatedAt: '2026-11-17T00:00:00Z',
  );
}

/// 假播放器：不会真的出声；把「开始播放」挂起，测试才好检查中间状态。
class _FakePlayer implements TtsAudioSequencePlayback {
  List<File> files = const [];
  void Function(int index)? onIndex;
  bool stopped = false;
  bool disposed = false;
  /// 最近一次开播用的速率（33.10：整篇朗读要跟朗读语速走）。
  double rate = 1.0;
  Completer<void> _gate = Completer<void>();

  @override
  Future<void> play(
    List<File> files, {
    required void Function(int index) onIndex,
    double rate = 1.0,
  }) {
    stopped = false;
    _gate = Completer<void>();
    this.files = files;
    this.onIndex = onIndex;
    this.rate = rate;
    onIndex(0);
    return _gate.future;
  }

  void finish() {
    if (!_gate.isCompleted) _gate.complete();
  }

  void tick(int index) => onIndex?.call(index);

  @override
  Future<void> stop() async {
    stopped = true;
    finish();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    finish();
  }
}

Future<void> _commitArticle(TtsAudioCache cache, SavedArticle article) async {
  final staging = await cache.createStagingDir(article.id);
  final files = <String, String>{};
  for (final s in article.sentences) {
    final key = ttsAudioKey(normalizeTtsText(s.text), _voice, _rev);
    final name = '$key.aac';
    await File(p.join(staging.path, name)).writeAsBytes([1, 2, 3]);
    files[key] = name;
  }
  await cache.commitArticle(
    articleId: article.id,
    title: article.title,
    voice: _voice,
    revision: _rev,
    stagingDir: staging,
    files: files,
    bytes: 3 * article.sentences.length,
    sentenceCount: article.sentences.length,
  );
}

void main() {
  late Directory temp;
  late TtsAudioCache cache;
  late _FakePlayer player;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dlaoshi_article_audio_');
    cache = TtsAudioCache(rootDir: temp);
    player = _FakePlayer();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ArticleAudioViewModel makeVm({double Function()? rateOf}) =>
      ArticleAudioViewModel(
        audioCache: cache,
        player: player,
        rateOf: rateOf,
      );

  test('没生成过离线音频：不开播，给出提示', () async {
    final vm = makeVm();
    addTearDown(vm.dispose);
    await vm.play(_article('saved:1', ['One.']));
    expect(vm.playing, isFalse);
    expect(player.files, isEmpty);
    expect(vm.error, contains('还没生成离线朗读'));
  });

  test('已生成：按句顺序播放并回报当前句；播完清状态', () async {
    final article = _article('saved:1', ['One.', 'Two.']);
    await _commitArticle(cache, article);
    final vm = makeVm();
    addTearDown(vm.dispose);

    await vm.play(article);
    expect(vm.playing, isTrue);
    expect(vm.articleId, article.id);
    expect(vm.sentenceId, 's1');
    expect(player.files, hasLength(2));

    player.tick(1);
    expect(vm.sentenceId, 's2');

    player.finish();
    await Future<void>.delayed(Duration.zero);
    expect(vm.playing, isFalse);
    expect(vm.sentenceId, isNull);
    expect(vm.articleId, isNull);
  });

  test('从选中句开始播：只传这一句之后的文件', () async {
    final article = _article('saved:1', ['One.', 'Two.', 'Three.']);
    await _commitArticle(cache, article);
    final vm = makeVm();
    addTearDown(vm.dispose);

    await vm.play(article, fromSentenceId: 's2');
    expect(vm.sentenceId, 's2');
    expect(player.files, hasLength(2));
    player.finish();
  });

  test('stop 会打断播放并清状态', () async {
    final article = _article('saved:1', ['One.']);
    await _commitArticle(cache, article);
    final vm = makeVm();
    addTearDown(vm.dispose);

    await vm.play(article);
    expect(vm.playing, isTrue);
    await vm.stop();
    expect(vm.playing, isFalse);
    expect(vm.sentenceId, isNull);
    expect(player.stopped, isTrue);
  });

  test('缓存缺句：整篇不播，提示重新生成', () async {
    final article = _article('saved:1', ['One.', 'Two.']);
    await _commitArticle(cache, article);
    // 删掉第二句的文件，模拟缓存被外部清理过。
    final entry = await cache.entryOf(article.id);
    final name =
        entry!.files[ttsAudioKey(normalizeTtsText('Two.'), _voice, _rev)]!;
    final dir = Directory(
      p.join(
        temp.path,
        'tts_audio',
        'articles',
        ttsAudioArticleDirName(article.id),
      ),
    );
    await File(p.join(dir.path, name)).delete();

    final vm = makeVm();
    addTearDown(vm.dispose);
    await vm.play(article);
    expect(vm.playing, isFalse);
    expect(vm.error, contains('不完整'));
    expect(player.files, isEmpty);
  });

  group('整篇朗读跟着朗读语速走（33.10）', () {
    test('默认语速 0.45：按 0.95 倍播（与点句朗读的缓存播放同一个口径）', () async {
      final article = _article('saved:1', ['One.']);
      await _commitArticle(cache, article);
      final vm = makeVm();
      addTearDown(vm.dispose);

      await vm.play(article);
      // neuralRateOf(0.45) = 0.5 + 0.45 = 0.95。
      expect(player.rate, closeTo(0.95, 1e-9));
      player.finish();
    });

    test('Kokoro 调到 1.5：整篇也是 2.0 倍，不再是原速', () async {
      final article = _article('saved:1', ['One.']);
      await _commitArticle(cache, article);
      final vm = makeVm(rateOf: () => 1.5);
      addTearDown(vm.dispose);

      await vm.play(article);
      expect(player.rate, closeTo(2.0, 1e-9));
      player.finish();
    });

    test('播到一半改语速：这一轮不变，下次开播才用新值', () async {
      final article = _article('saved:1', ['One.', 'Two.']);
      await _commitArticle(cache, article);
      var current = 0.45;
      final vm = makeVm(rateOf: () => current);
      addTearDown(vm.dispose);

      await vm.play(article);
      expect(player.rate, closeTo(0.95, 1e-9));

      // 播放中改设置：不该打断当前这一轮（否则会突然变速）。
      current = 1.5;
      player.tick(1);
      expect(player.rate, closeTo(0.95, 1e-9));

      // 重新开播才吃新值。
      player.finish();
      await Future<void>.delayed(Duration.zero);
      await vm.play(article);
      expect(player.rate, closeTo(2.0, 1e-9));
      player.finish();
    });
  });
}
