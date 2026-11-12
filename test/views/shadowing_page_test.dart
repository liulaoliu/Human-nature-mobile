// 跟读页的 smoke：空态文案 + 录完能「听自己读的」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dlaoshi_app/core/ports.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/viewmodels/shadowing_view_model.dart';
import 'package:dlaoshi_app/views/shadowing_page.dart';
import 'smoke_harness.dart';

/// 假朗读：什么都不做。
class _FakeSpeech implements SpeechPort {
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

/// 假录音：一开录就有个临时文件，`lastPath` 指向它。
class _FakeRecorder implements RecorderPort {
  String? path;

  @override
  String? get lastPath => path;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> start() async => path ??= '/tmp/take.wav';

  @override
  Future<double> amplitude() async => 0.05;

  @override
  Future<int?> stop() async => 3000;

  @override
  Future<void> clearTake() async => path = null;

  @override
  Future<void> discard() async => path = null;
}

/// 假回放：记下播过什么。
class _FakePlayback implements PlaybackPort {
  final List<String> played = <String>[];
  bool playing = false;

  @override
  bool get isPlaying => playing;

  @override
  double? get progress => null;

  @override
  Future<void> play(String path) async {
    played.add(path);
    playing = true;
  }

  @override
  Future<void> stop() async => playing = false;

  @override
  Future<void> dispose() async => playing = false;
}

const String _body = 'We keep up with the news every morning. '
    'It helps us stay sharp.';

SavedArticle _article() => const SavedArticle(
      id: 'a1',
      title: 'Growth',
      sentences: [
        Sentence(id: 's1', paraId: 'p1', text: _body),
      ],
      paragraphs: [
        Paragraph(id: 'p1', sentenceIds: ['s1']),
      ],
      updatedAt: '2026-11-10T00:00:00.000Z',
    );

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('ShadowingPage 空库：标题与「先去精读」空态', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);

    await smokePump(tester, smokeApp(db, const ShadowingPage()));

    expect(find.text('跟读'), findsOneWidget);
    expect(find.text('还没有文章。先去「精读」粘一篇原文，再回来跟读。'),
        findsOneWidget);

    await smokeFinish(tester);
  });

  testWidgets('录完之后出现「听自己读的」，点了真的开始回放', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final articles = ArticleRepository(db);
    final playback = _FakePlayback();
    final vm = ShadowingViewModel(
      articles: articles,
      speech: _FakeSpeech(),
      recorder: _FakeRecorder(),
      playback: playback,
    );
    addTearDown(vm.dispose);

    await tester.runAsync(() async {
      await articles.save(_article());
      await vm.bootstrap();
      await vm.openArticle('a1');
    });

    await smokePump(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShadowingViewModel>.value(value: vm),
        ],
        child: const MaterialApp(home: ShadowingPage()),
      ),
    );

    // 还没录：没有可回放的东西，按钮不该出现。
    expect(find.text('听自己读的'), findsNothing);

    await tester.runAsync(() async {
      await vm.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await vm.stopRecording();
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('听自己读的'), findsOneWidget);

    await tester.tap(find.text('听自己读的'));
    await tester.pump();
    expect(playback.played, hasLength(1));

    await smokeFinish(tester);
  });
}
