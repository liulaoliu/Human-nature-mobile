// 考试会话的序列化：题目往返、坏数据整卷作废、停位越界不算可恢复。
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/quiz.dart' show QuizKind, QuizQuestion;
import 'package:dlaoshi_app/core/quiz_pool.dart' show QuizMode, QuizScope;
import 'package:dlaoshi_app/core/quiz_session.dart';

QuizQuestion _q({
  String id = 'v1:spell',
  String itemId = 'v1',
  String lemma = 'alpha',
  QuizKind kind = QuizKind.spell,
  String? source,
  String word = 'alpha',
  String prompt = '第一个希腊字母',
  String? meaning = '第一个希腊字母',
  List<String>? options,
  String answer = 'alpha',
  List<String> accept = const <String>['alpha'],
}) =>
    QuizQuestion(
      id: id,
      itemId: itemId,
      lemma: lemma,
      kind: kind,
      source: source,
      word: word,
      prompt: prompt,
      meaning: meaning,
      partOfSpeech: 'n.',
      phonetic: '/ˈælfə/',
      context: 'Alpha is the first letter.',
      translation: 'Alpha 是第一个字母。',
      audioText: 'Alpha is the first letter.',
      options: options,
      answer: answer,
      accept: accept,
    );

QuizSession _session({
  QuizMode mode = QuizMode.vocab,
  QuizScope scope = QuizScope.all,
  List<QuizQuestion>? questions,
  int index = 0,
  List<QuizAnswerSnapshot> results = const <QuizAnswerSnapshot>[],
  int seconds = 42,
  String? articleId,
  int drillRound = 1,
  bool recorded = false,
}) =>
    QuizSession(
      mode: mode,
      scope: scope,
      questions: questions ?? <QuizQuestion>[_q()],
      index: index,
      results: results,
      seconds: seconds,
      articleId: articleId,
      drillRound: drillRound,
      recorded: recorded,
    );

void main() {
  group('题目往返', () {
    test('17 个字段一个不丢', () {
      final q = _q(
        kind: QuizKind.defineChoice,
        source: 'article',
        options: const <String>['a', 'b', 'c', 'd'],
        accept: const <String>['alpha', 'alphas'],
      );
      final single = parseQuizQuestion(<String, Object?>{
        'id': q.id,
        'itemId': q.itemId,
        'lemma': q.lemma,
        'kind': q.kind.name,
        'source': q.source,
        'word': q.word,
        'prompt': q.prompt,
        'meaning': q.meaning,
        'partOfSpeech': q.partOfSpeech,
        'phonetic': q.phonetic,
        'context': q.context,
        'translation': q.translation,
        'audioText': q.audioText,
        'options': q.options,
        'answer': q.answer,
        'accept': q.accept,
      });
      expect(single, isNotNull);
      expect(single!.id, q.id);
      expect(single.itemId, q.itemId);
      expect(single.lemma, q.lemma);
      expect(single.kind, q.kind);
      expect(single.source, 'article');
      expect(single.word, q.word);
      expect(single.prompt, q.prompt);
      expect(single.meaning, q.meaning);
      expect(single.partOfSpeech, q.partOfSpeech);
      expect(single.phonetic, q.phonetic);
      expect(single.context, q.context);
      expect(single.translation, q.translation);
      expect(single.audioText, q.audioText);
      expect(single.options, q.options);
      expect(single.answer, q.answer);
      expect(single.accept, q.accept);
    });

    test('可空字段存 null 读回还是 null', () {
      final q = _q(meaning: null);
      final single = parseQuizQuestion(<String, Object?>{
        'id': q.id,
        'itemId': q.itemId,
        'lemma': q.lemma,
        'kind': q.kind.name,
        'word': q.word,
        'prompt': q.prompt,
        'meaning': null,
        'options': null,
        'answer': q.answer,
        'accept': const <String>[],
      });
      expect(single!.meaning, isNull);
      expect(single.options, isNull);
      expect(single.accept, isEmpty);
    });
  });

  group('整卷往返', () {
    test('两题 + 一条已答记录，全字段一致', () {
      final q1 = _q();
      final q2 = _q(
        id: 'v2:meaning',
        itemId: 'v2',
        lemma: 'bravo',
        kind: QuizKind.meaning,
        word: 'bravo',
        prompt: 'bravo',
        meaning: '第二个字母',
        answer: '第二个字母',
        accept: const <String>['第二个字母'],
      );
      final s = _session(
        mode: QuizMode.article,
        scope: QuizScope.article,
        questions: <QuizQuestion>[q1, q2],
        index: 1,
        results: <QuizAnswerSnapshot>[
          QuizAnswerSnapshot(question: q1, input: 'alpha', correct: true),
        ],
        articleId: 'a1',
        drillRound: 2,
        recorded: true,
      );
      final back = parseQuizSession(quizSessionToJson(s));
      expect(back, isNotNull);
      expect(back!.mode, QuizMode.article);
      expect(back.scope, QuizScope.article);
      expect(back.questions, hasLength(2));
      expect(back.questions.first.id, q1.id);
      expect(back.questions.last.id, q2.id);
      expect(back.index, 1);
      expect(back.seconds, 42);
      expect(back.articleId, 'a1');
      expect(back.drillRound, 2);
      expect(back.recorded, isTrue);
      expect(back.results, hasLength(1));
      expect(back.results.single.input, 'alpha');
      expect(back.results.single.correct, isTrue);
      expect(back.results.single.question.id, q1.id);
    });

    test('听写 / 混合模式也认得', () {
      for (final m in <QuizMode>[QuizMode.dictation, QuizMode.mixed]) {
        final back = parseQuizSession(quizSessionToJson(_session(mode: m)));
        expect(back?.mode, m, reason: '${m.name} 应该能存回来');
      }
    });

    test('缺 articleId 存 null', () {
      final back = parseQuizSession(quizSessionToJson(_session()));
      expect(back!.articleId, isNull);
    });
  });

  group('坏数据', () {
    test('不是 Map → null', () {
      for (final bad in <Object?>[null, '', 42, <String>['x']]) {
        expect(parseQuizSession(bad), isNull);
      }
    });

    test('认不出的模式 → null', () {
      final json = quizSessionToJson(_session());
      json['mode'] = 'nonsense';
      expect(parseQuizSession(json), isNull);
    });

    test('没有题 → null（空卷不该占着恢复位）', () {
      final json = quizSessionToJson(_session());
      json['questions'] = <Object?>[];
      expect(parseQuizSession(json), isNull);
    });

    test('题里有一道坏的：只丢那一道，其余照旧', () {
      final json = quizSessionToJson(_session(questions: [_q(), _q(id: 'v2:spell')]));
      final list = json['questions']! as List<Object?>;
      list.insert(1, <String, Object?>{'id': 'broken'}); // 缺 kind / answer
      final back = parseQuizSession(json);
      expect(back, isNotNull);
      expect(back!.questions, hasLength(2));
      expect(back.questions.first.id, 'v1:spell');
      expect(back.questions.last.id, 'v2:spell');
    });

    test('已答记录里坏的那条丢掉，好题留着', () {
      final json = quizSessionToJson(_session(
        questions: [_q(), _q(id: 'v2:spell')],
        results: <QuizAnswerSnapshot>[
          QuizAnswerSnapshot(question: _q(id: 'v2:spell'), input: 'x', correct: false),
        ],
      ));
      final list = json['results']! as List<Object?>;
      list.add(<String, Object?>{'input': 'y', 'correct': true});
      final back = parseQuizSession(json);
      expect(back!.results, hasLength(1));
      expect(back.results.single.input, 'x');
    });

    test('停位越界 → 不给恢复', () {
      // index == questions.length（已交卷）与负数都不算可恢复。
      for (final idx in <int>[1, -1, 99]) {
        final json = quizSessionToJson(_session(index: 1));
        json['index'] = idx;
        expect(parseQuizSession(json), isNull, reason: 'index=$idx 不该恢复');
      }
    });
  });
}
