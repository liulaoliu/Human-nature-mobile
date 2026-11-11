import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/core/study_prefs.dart';
import 'package:dlaoshi_app/core/study_round_hint.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

VocabItem mkWord(String word) => VocabItem(
      id: 'vocab:$word',
      word: word,
      lemma: word,
      meaning: 'x-$word',
      status: VocabStatus.queried,
      createdAt: '2026-11-11T00:00:00.000Z',
      updatedAt: '2026-11-11T00:00:00.000Z',
    );

String hint(
  StudyEntry entry, {
  List<VocabItem> source = const <VocabItem>[],
  StudyPrefs prefs = defaultStudyPrefs,
  StudyDeck deck = StudyDeck.word,
  String? articleId,
}) =>
    emptyRoundReason(
      entry: entry,
      source: source,
      prefs: prefs,
      deck: deck,
      articleId: articleId,
    );

void main() {
  group('学习入口空队列', () {
    test('额度先于一切：池子里有词也说额度用完', () {
      final prefs = defaultStudyPrefs.copyWith(newLimit: 5, newToday: 5);
      final s = hint(
        StudyEntry.learn,
        source: [mkWord('alpha')],
        prefs: prefs,
        articleId: 'a1',
      );
      expect(s, contains('额度用完'));
      expect(s, contains('5/5'));
    });

    test('没打开文章：先去精读收词', () {
      expect(hint(StudyEntry.learn), contains('还没打开过文章'));
    });

    test('文章打开着但还没收词', () {
      expect(hint(StudyEntry.learn, articleId: 'a1'), contains('先去精读里点词收词'));
    });

    test('这篇的都学过了：指向复习', () {
      final s = hint(
        StudyEntry.learn,
        source: [mkWord('alpha')],
        articleId: 'a1',
      );
      expect(s, contains('都学过了'));
      expect(s, contains('复习'));
    });

    test('背搭配时措辞是「搭配」', () {
      final s = hint(
        StudyEntry.learn,
        articleId: 'a1',
        deck: StudyDeck.collocation,
      );
      expect(s, contains('搭配'));
      expect(s, isNot(contains('可学的词')));
    });
  });

  group('复习入口空队列', () {
    test('没到期：指向学习', () {
      final s = hint(StudyEntry.review, prefs: defaultStudyPrefs);
      expect(s, contains('没有到期的复习'));
      expect(s, contains('学习'));
    });

    test('有词时也说没有到期的', () {
      expect(
        hint(StudyEntry.review, source: [mkWord('alpha')]),
        '没有到期的复习词',
      );
    });
  });

  group('回顾入口空队列', () {
    test('没打开文章', () {
      expect(hint(StudyEntry.recall), contains('还没打开过文章'));
    });

    test('没学过', () {
      expect(hint(StudyEntry.recall, articleId: 'a1'), contains('还没有学过的词'));
    });

    test('有词时是「没有可回顾的」', () {
      expect(
        hint(
          StudyEntry.recall,
          source: [mkWord('alpha')],
          articleId: 'a1',
        ),
        '这篇没有可回顾的词',
      );
    });
  });
}
