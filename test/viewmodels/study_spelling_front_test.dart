import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/viewmodels/study_spelling_front.dart';
import 'package:dlaoshi_app/viewmodels/study_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 卡面拼写状态机（`StudySpellingFront`）的用例。
///
/// 覆盖 TODO ② 清单里的四条：前置条件、检查、拼错确认、换卡重置。
void main() {
  sqfliteFfiInit();

  late Database db;
  late VocabRepository vocabRepo;
  late StudyViewModel vm;

  Future<void> openMem() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await ensureSchema(db);
    vocabRepo = VocabRepository(db);
  }

  List<VocabItem> words() => [
        for (final w in ['alpha', 'bravo', 'charlie', 'delta'])
          VocabItem(
            id: 'v-$w',
            word: w,
            lemma: w,
            meaning: '$w 的意思',
            status: VocabStatus.queried,
            createdAt: '2026-01-01T00:00:00.000Z',
            updatedAt: '2026-01-01T00:00:00.000Z',
          ),
      ];

  VocabLibrary lib(List<VocabItem> items) => VocabLibrary(items: items);

  Future<void> seed(List<VocabItem> items) async {
    await vocabRepo.save(lib(items));
    await vm.bootstrap();
  }

  setUp(() async {
    await openMem();
    vm = StudyViewModel(
      vocab: vocabRepo,
      learning: LearningRepository(db),
    );
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('前置条件', () {
    test('设置里没开卡面拼写：不出输入框', () async {
      await seed(words());
      vm.startRound();
      final sp = StudySpellingFront(vm);
      addTearDown(sp.dispose);
      expect(vm.prefs.spelling, isFalse);
      expect(sp.front, isFalse);
    });

    test('开了卡面拼写：生词正面出输入框', () async {
      await seed(words());
      await vm.settings.setSpelling(true);
      vm.startRound();
      final sp = StudySpellingFront(vm);
      addTearDown(sp.dispose);
      expect(sp.front, isTrue);
      expect(sp.checked, isFalse);
    });

    test('重学卡跳过卡面拼写（先看词看释义）', () async {
      final relearning = [
        for (final w in ['alpha', 'bravo', 'charlie', 'delta'])
          VocabItem(
            id: 'v-$w',
            word: w,
            lemma: w,
            meaning: '$w 的意思',
            status: VocabStatus.queried,
            createdAt: '2026-01-01T00:00:00.000Z',
            updatedAt: '2026-01-01T00:00:00.000Z',
            reviewState: const ReviewState(
              ease: 2.5,
              interval: 0,
              repetitions: 0,
              lapses: 1,
              relearn: 1,
              due: '2026-01-01T00:00:00.000Z',
            ),
          ),
      ];
      await seed(relearning);
      await vm.settings.setSpelling(true);
      vm.startRound();
      final sp = StudySpellingFront(vm);
      addTearDown(sp.dispose);
      expect(sp.front, isFalse);
    });
  });

  group('检查', () {
    test('拼对：不写库、不推进，只解锁评分', () async {
      await seed(words());
      await vm.settings.setSpelling(true);
      vm.startRound();
      final sp = StudySpellingFront(vm);
      addTearDown(sp.dispose);

      final beforeIndex = vm.session!.index;
      final beforeWord = vm.session!.card!.word;
      sp.setInput(beforeWord);
      await sp.check();

      expect(sp.checked, isTrue);
      expect(sp.ok, isTrue);
      expect(sp.miss, isNull);
      // 拼对不推进：还在同一张
      expect(vm.session!.index, beforeIndex);
      expect(vm.session!.card!.word, beforeWord);
    });

    test('拼错：判 again + 打「不认识」标签 + 回队尾', () async {
      await seed(words());
      await vm.settings.setSpelling(true);
      vm.startRound();
      final sp = StudySpellingFront(vm);
      addTearDown(sp.dispose);

      sp.setInput('alph');
      await sp.check();

      expect(sp.checked, isTrue);
      expect(sp.ok, isFalse);
      expect(sp.miss, isNotNull);
      expect(sp.miss!.word, 'alpha');
      expect(sp.miss!.typed, 'alph');

      final saved = (await vocabRepo.load())!;
      final alpha = saved.items.firstWhere((it) => it.id == 'v-alpha');
      expect(alpha.tags, contains('不认识'));
      expect(alpha.reviewState.relearn > 0, isTrue);
    });

    test('已经检查过：再点不重复判卷', () async {
      await seed(words());
      await vm.settings.setSpelling(true);
      vm.startRound();
      final sp = StudySpellingFront(vm);
      addTearDown(sp.dispose);

      sp.setInput('alph');
      await sp.check();
      sp.setInput('alpha');
      await sp.check(); // 第二次应该无效
      expect(sp.ok, isFalse);
      expect(sp.miss!.typed, 'alph');
    });
  });

  group('拼错确认', () {
    test('点「知道了」推进到下一张，拼错卡消失', () async {
      await seed(words());
      await vm.settings.setSpelling(true);
      vm.startRound();
      final sp = StudySpellingFront(vm);
      addTearDown(sp.dispose);

      sp.setInput('alph');
      await sp.check();
      expect(sp.miss, isNotNull);

      await sp.ack();
      expect(sp.miss, isNull);
      // 拼错已重排在队尾，推进到原来第二张
      expect(vm.session!.index, 1);
    });
  });

  group('换卡重置', () {
    test('换到下一张：输入 / 检查态全清', () async {
      await seed(words());
      await vm.settings.setSpelling(true);
      vm.startRound();
      final sp = StudySpellingFront(vm);
      addTearDown(sp.dispose);

      sp.setInput('alpha');
      await sp.check();
      expect(sp.checked, isTrue);

      vm.forward();
      expect(sp.checked, isFalse);
      expect(sp.input, isEmpty);
      expect(sp.front, isTrue);
    });
  });
}
