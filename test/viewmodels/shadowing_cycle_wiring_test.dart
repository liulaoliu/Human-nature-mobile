// 复读在 ViewModel 这一层的接线：走完一圈会自己下一句、切句会停。
//
// 编排器本身的步序在 `test/services/shadowing_cycler_test.dart`；
// 这里只验「钩子接对了没有」。
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/ports.dart';
import 'package:dlaoshi_app/core/shadowing_cycle.dart';
import 'package:dlaoshi_app/data/db/migrations.dart' show ensureSchema;
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/viewmodels/shadowing_view_model.dart';

/// 假朗读：记下读了什么，读完立刻返回。
class _Speech implements SpeechPort {
  final List<String> spoken = <String>[];

  @override
  bool get isSpeaking => false;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}

  @override
  Future<void> setRate(double rate) async {}
}

/// 假录音：开录即有文件，`stop` 立刻返回，不会自己超时。
class _Recorder implements RecorderPort {
  String? path;
  bool discarding = false;

  @override
  String? get lastPath => path;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> start() async {
    path = '/tmp/take.wav';
    discarding = false;
  }

  @override
  Future<double> amplitude() async => 0.05;

  @override
  Future<int?> stop() async => 3000;

  @override
  Future<void> clearTake() async => path = null;

  @override
  Future<void> discard() async {
    discarding = true;
    path = null;
  }
}

/// 假回放：`play` 之后立刻算放完（`isPlaying` 恒 false），
/// 这样复读编排器的「等回放结束」不会真的等 30 秒。
class _Playback implements PlaybackPort {
  final List<String> played = <String>[];

  @override
  bool get isPlaying => false;

  @override
  double? get progress => null;

  @override
  Future<void> play(String path) async => played.add(path);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

SavedArticle _article() => const SavedArticle(
      id: 'a1',
      title: 'Growth',
      sentences: [
        Sentence(id: 's1', paraId: 'p1', text: 'We keep up with the news.'),
        Sentence(id: 's2', paraId: 'p1', text: 'It helps us stay sharp.'),
      ],
      paragraphs: [
        Paragraph(id: 'p1', sentenceIds: ['s1', 's2']),
      ],
      updatedAt: '2026-11-10T00:00:00.000Z',
    );

void main() {
  setUpAll(sqfliteFfiInit);

  Future<({ShadowingViewModel vm, _Speech speech, _Playback playback})> make(
    Database db,
  ) async {
    final articles = ArticleRepository(db);
    final speech = _Speech();
    final playback = _Playback();
    final vm = ShadowingViewModel(
      articles: articles,
      speech: speech,
      recorder: _Recorder(),
      playback: playback,
    );
    addTearDown(vm.dispose);
    await articles.save(_article());
    await vm.bootstrap();
    await vm.openArticle('a1');
    return (vm: vm, speech: speech, playback: playback);
  }

  Future<Database> openMem() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await ensureSchema(db);
    return db;
  }

  test('复读一圈：先放标准音，再录，再放我读的', () async {
    final db = await openMem();
    addTearDown(db.close);
    final env = await make(db);

    // 一圈走完会自动翻到下一句，所以先把「这一句」记下来再断言。
    final first = env.vm.text;
    final ok = await env.vm.cycle.start();

    expect(ok, isTrue);
    expect(env.speech.spoken, hasLength(1), reason: '标准音只该读一遍');
    expect(env.speech.spoken.single, first, reason: '读的应该是开始那一句');
    expect(env.playback.played, hasLength(1), reason: '录完该放一遍');
    expect(env.vm.cycle.step, ShadowCycleStep.idle);
  });

  test('一圈走完自动下一句（「放一句、读一句」的节奏）', () async {
    final db = await openMem();
    addTearDown(db.close);
    final env = await make(db);

    expect(env.vm.index, 0);
    expect(env.vm.sentences, hasLength(2), reason: '造的文章得有两句');
    await env.vm.cycle.start();

    expect(env.vm.index, 1, reason: '读完最后一遍该自己翻到下一句');
    expect(env.vm.cycle.step, ShadowCycleStep.idle);
  });

  test('切句会把复读停掉（不在新句子上接着放旧录音）', () async {
    final db = await openMem();
    addTearDown(db.close);
    final env = await make(db);

    env.vm.cycle.stop();
    env.vm.select(1);

    expect(env.vm.cycle.step, ShadowCycleStep.idle);
    expect(env.vm.index, 1);
  });

  test('换篇会把复读停掉', () async {
    final db = await openMem();
    addTearDown(db.close);
    final env = await make(db);

    await env.vm.openArticle(null);

    expect(env.vm.cycle.step, ShadowCycleStep.idle);
    expect(env.vm.hasArticle, isFalse);
  });

  test('手动开录会打断正在跑的复读（不自己再放一遍）', () async {
    final db = await openMem();
    addTearDown(db.close);
    final env = await make(db);

    // 手动开录时如果编排器还在跑，它会自己接着放回放 —— 用户没点就出声。
    await env.vm.startRecording();
    expect(env.vm.cycle.step, ShadowCycleStep.idle);
    await env.vm.stopRecording(discard: true);
  });
}
