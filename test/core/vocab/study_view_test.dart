import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab/study_view.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

VocabLibrary libraryWith(List<VocabItem> items) => createLibrary().copyWith(items: items);

/// 四个义项各不相同，`canQuizMeaning` 才出得了「正确 + 3 个干扰项」。
VocabLibrary quizLibrary({
  ReviewState reviewState = defaultReviewState,
  List<String> tags = const [],
}) =>
    libraryWith([
      vocabItem(id: 'vocab:a', word: 'alpha', meaning: '甲', reviewState: reviewState, tags: tags),
      vocabItem(id: 'vocab:b', word: 'beta', meaning: '乙'),
      vocabItem(id: 'vocab:c', word: 'gamma', meaning: '丙'),
      vocabItem(id: 'vocab:d', word: 'delta', meaning: '丁'),
    ]);

void main() {
  group('studyCardView：当前卡与门禁', () {
    test('取词库里的最新版本，而不是队列快照', () {
      final snapshot = vocabItem(id: 'vocab:a', word: 'old', meaning: '旧');
      final latest = vocabItem(id: 'vocab:a', word: 'new', meaning: '新');
      final view = studyCardView(StudyCardViewParams(
        library: libraryWith([latest]),
        queue: [snapshot],
        index: 0,
        roundTotal: 1,
        retrying: false,
        meaningCleared: false,
      ));
      expect(view.card!.word, 'new');
    });

    test('词库里找不到时退回队列快照', () {
      final snapshot = vocabItem(id: 'vocab:a', word: 'snapshot');
      final view = studyCardView(StudyCardViewParams(
        library: libraryWith([]),
        queue: [snapshot],
        index: 0,
        roundTotal: 1,
        retrying: false,
        meaningCleared: false,
      ));
      expect(view.card!.word, 'snapshot');
    });

    test('组末拼写测试的词优先于队列', () {
      final view = studyCardView(StudyCardViewParams(
        library: libraryWith([vocabItem(id: 'vocab:a', word: 'queue')]),
        queue: [vocabItem(id: 'vocab:a')],
        index: 0,
        roundTotal: 1,
        retrying: false,
        meaningCleared: false,
        roundCard: vocabItem(id: 'vocab:round', word: 'round'),
      ));
      expect(view.card!.word, 'round');
    });

    test('index 越过 roundTotal 才算加练卡', () {
      final lib = quizLibrary();
      final queue = [vocabItem(id: 'vocab:a')];
      StudyCardView at(int index, int roundTotal) => studyCardView(StudyCardViewParams(
            library: lib,
            queue: queue,
            index: index,
            roundTotal: roundTotal,
            retrying: false,
            meaningCleared: false,
          ));
      expect(at(1, 1).isExtraCard, isTrue);
      expect(at(0, 1).isExtraCard, isFalse);
      expect(at(3, 0).isExtraCard, isFalse);
    });

    test('重学卡不套「选释义」门禁（它走锤炼门禁）', () {
      const relearnState = ReviewState(relearn: 1);
      final card = vocabItem(id: 'vocab:a', reviewState: relearnState);
      final view = studyCardView(StudyCardViewParams(
        library: quizLibrary(reviewState: relearnState),
        queue: [card],
        index: 0,
        roundTotal: 1,
        retrying: false,
        meaningCleared: true,
      ));
      expect(view.relearning, isTrue);
      expect(view.meaningRequired, isFalse);
    });

    test('标过不认识且没重建记忆 → 先选释义；清掉门禁后放行', () {
      final card = vocabItem(id: 'vocab:a', tags: const ['不认识']);
      final lib = quizLibrary(tags: const ['不认识']);
      StudyCardView at({required bool meaningCleared}) => studyCardView(StudyCardViewParams(
            library: lib,
            queue: [card],
            index: 0,
            roundTotal: 1,
            retrying: false,
            meaningCleared: meaningCleared,
          ));
      final pending = at(meaningCleared: false);
      expect(pending.meaningRequired, isTrue);
      expect(pending.meaningGate, isTrue);
      expect(at(meaningCleared: true).meaningGate, isFalse);
    });

    test('词库出不了四个选项时退回普通卡片，不卡门禁', () {
      final card = vocabItem(id: 'vocab:a', tags: const ['不认识']);
      final view = studyCardView(StudyCardViewParams(
        library: libraryWith([card]),
        queue: [card],
        index: 0,
        roundTotal: 1,
        retrying: false,
        meaningCleared: false,
      ));
      expect(view.meaningRequired, isFalse);
    });
  });
}
