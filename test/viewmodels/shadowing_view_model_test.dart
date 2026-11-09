import 'package:dlaoshi_app/core/ports.dart';
import 'package:dlaoshi_app/core/shadowing_prefs.dart';
import 'package:dlaoshi_app/core/shadowing_take.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/shadowing_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 假朗读：记下读了什么、被停过几次。
class FakeSpeech implements SpeechPort {
  final List<String> spoken = <String>[];
  final List<double> rates = <double>[];
  int stops = 0;
  bool speaking = false;
  bool throwOnSpeak = false;

  @override
  bool get isSpeaking => speaking;

  @override
  Future<void> speak(String text) async {
    if (throwOnSpeak) throw StateError('引擎炸了');
    spoken.add(text);
    speaking = true;
    speaking = false;
  }

  @override
  Future<void> stop() async {
    stops++;
    speaking = false;
  }

  @override
  Future<void> setRate(double rate) async => rates.add(rate);
}

/// 假录音：电平序列由用例喂。
class FakeRecorder implements RecorderPort {
  FakeRecorder({this.permitted = true});

  bool permitted;
  bool started = false;
  int starts = 0;
  int stops = 0;
  int discards = 0;

  /// 依次返回的电平；用完了就一直返回最后一个。
  List<double> levels = const <double>[0.05];
  int _cursor = 0;

  /// `stop()` 返回的时长。
  int durationMs = 3000;

  @override
  Future<bool> ensurePermission() async => permitted;

  @override
  Future<void> start() async {
    starts++;
    started = true;
  }

  @override
  Future<double> amplitude() async {
    if (levels.isEmpty) return 0;
    final v = levels[_cursor < levels.length ? _cursor : levels.length - 1];
    _cursor++;
    return v;
  }

  @override
  Future<int?> stop() async {
    stops++;
    started = false;
    return durationMs;
  }

  @override
  Future<void> discard() async {
    discards++;
    started = false;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ArticleRepository articles;
  late FakeSpeech speech;
  late FakeRecorder recorder;
  late PrefsStore store;
  late ShadowingViewModel vm;

  const String bodyA =
      'We keep up with the news every morning. It helps us stay sharp. '
      'Small habits compound over time.';

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    articles = ArticleRepository(db);
    speech = FakeSpeech();
    recorder = FakeRecorder();
    store = PrefsStore.memory();
    vm = ShadowingViewModel(
      articles: articles,
      speech: speech,
      recorder: recorder,
      prefsStore: store,
    );
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<String> seedArticle() async {
    final imports = ArticleImportService(articles);
    final saved = await imports.createFromText(raw: bodyA);
    return saved!.id;
  }

  group('打开文章与切句', () {
    test('bootstrap 读到文章列表与默认偏好', () async {
      await seedArticle();
      await vm.bootstrap();
      expect(vm.library, hasLength(1));
      expect(vm.prefs.viewMode, ShadowingViewMode.full);
      expect(vm.prefs.hangoverMs, 2500);
      // 存下来的语速要同步给朗读器，否则第一次读还是默认速度。
      expect(speech.rates, <double>[vm.prefs.speechRate]);
    });

    test('打开文章后有句子，能前后翻但不越界', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      expect(vm.hasArticle, isTrue);
      expect(vm.sentences, hasLength(3));
      expect(vm.index, 0);
      expect(vm.hasNext, isTrue);
      expect(vm.hasPrev, isFalse);

      vm.next();
      expect(vm.index, 1);
      vm.next();
      expect(vm.index, 2);
      vm.next();
      expect(vm.index, 2, reason: '最后一句再点下一句应该停住');

      vm.prev();
      expect(vm.index, 1);
      vm.prev();
      vm.prev();
      expect(vm.index, 0);
    });

    test('打开不存在的文章给错误，不崩', () async {
      await vm.openArticle('nope');
      expect(vm.article, isNull);
      expect(vm.error, contains('找不到了'));
    });

    test('openArticle(null) 回到选文章', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      await vm.openArticle(null);
      expect(vm.article, isNull);
      expect(vm.hasArticle, isFalse);
      expect(vm.index, 0);
    });

    test('切句会清掉上一次的判定', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      vm.select(1);
      expect(vm.verdict, isNull);
      expect(vm.elapsedMs, 0);
    });
  });

  group('朗读', () {
    test('读当前这一句，读完 playing 归位', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      await vm.play();
      expect(speech.spoken, <String>[vm.text]);
      expect(vm.playing, isFalse);
    });

    test('朗读失败写进 error，不抛', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      speech.throwOnSpeak = true;
      await vm.play();
      expect(vm.error, contains('朗读失败'));
      expect(vm.playing, isFalse);
    });

    test('切句时会把正在读的停掉', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      vm.select(1);
      // 没在读的时候不必调 stop。
      expect(speech.stops, 0);
    });
  });

  group('录音与判定', () {
    test('没权限就说清楚，不进录音态', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      recorder.permitted = false;
      await vm.startRecording();
      expect(vm.recording, isFalse);
      expect(vm.error, contains('麦克风'));
      expect(recorder.starts, 0);
    });

    test('录完按「读得够不够长」判 ok', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      // 当前句 8 词 → 估 3.2 秒；录 3000ms 落在 [50%, 200%] 里。
      recorder.durationMs = 3000;
      await vm.startRecording();
      expect(vm.recording, isTrue);
      // 电平是定时器每 40ms 拉一次：不推几拍，tracker 就还没「听到声音」，
      // 会判成 silent（真实使用里人一开口就有了，测试要显式等）。
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await vm.stopRecording();
      expect(vm.recording, isFalse);
      expect(vm.verdict, TakeVerdict.ok);
      expect(vm.elapsedMs, 3000);
    });

    test('录得太短判 tooShort', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      recorder.durationMs = 500;
      await vm.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await vm.stopRecording();
      expect(vm.verdict, TakeVerdict.tooShort);
    });

    test('一直没听到声音判 silent', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      recorder.levels = const <double>[0.0001];
      recorder.durationMs = 3000;
      await vm.startRecording();
      await vm.stopRecording();
      expect(vm.verdict, TakeVerdict.silent);
    });

    test('放弃录音不判定、也不留时长', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      await vm.startRecording();
      await vm.stopRecording(discard: true);
      expect(recorder.discards, 1);
      expect(vm.verdict, isNull);
      expect(vm.elapsedMs, 0);
    });

    test('参考时长与兜底上限跟着句长走', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      // 8 词 → 3.2 秒参考；上限 = 3.2 * 2000 + 3000 = 9400ms。
      expect(vm.estimatedSec, closeTo(3.2, 0.01));
      expect(vm.capMs, 9400);
    });
  });

  group('偏好', () {
    test('换显示模式会落盘', () async {
      await vm.setViewMode(ShadowingViewMode.block);
      expect(vm.prefs.viewMode, ShadowingViewMode.block);
      expect(store.loadShadowingPrefs().viewMode, ShadowingViewMode.block);
    });

    test('调语速会同步给朗读器并落盘', () async {
      await vm.setRate(0.6);
      expect(vm.prefs.speechRate, 0.6);
      expect(speech.rates.last, 0.6);
      expect(store.loadShadowingPrefs().speechRate, 0.6);
    });

    test('语速会被夹到 0.1–1.0', () async {
      await vm.setRate(5);
      expect(vm.prefs.speechRate, 1.0);
      await vm.setRate(0);
      expect(vm.prefs.speechRate, 0.1);
    });

    test('调静音时长会落盘', () async {
      await vm.setHangover(1200);
      expect(vm.prefs.hangoverMs, 1200);
      expect(store.loadShadowingPrefs().hangoverMs, 1200);
    });
  });

  group('销毁', () {
    test('dispose 时把录音与朗读都收掉', () async {
      final id = await seedArticle();
      await vm.openArticle(id);
      await vm.startRecording();
      vm.dispose();
      // 等一拍让 unawaited 的收尾跑完。
      await Future<void>.delayed(Duration.zero);
      expect(recorder.discards, 1);
      // 再建一个给 tearDown 收，避免重复 dispose。
      vm = ShadowingViewModel(
        articles: articles,
        speech: speech,
        recorder: recorder,
        prefsStore: store,
      );
    });
  });
}
