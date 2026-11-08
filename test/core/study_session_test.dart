import 'package:dlaoshi_app/core/study_session.dart';
import 'package:dlaoshi_app/core/vocab/extra.dart';
import 'package:dlaoshi_app/core/vocab/learn_step.dart';
import 'package:dlaoshi_app/core/vocab/review.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

final DateTime _now = DateTime.parse('2026-03-10T12:00:00.000Z');

/// 一条没学过的新词（有释义，能背）。
VocabItem _fresh(String id, {String? word}) => vocabItem(
      id: id,
      word: word ?? 'word$id',
      lemma: word ?? 'word$id',
      meaning: '释义$id',
    );

VocabLibrary _lib(List<VocabItem> items) =>
    VocabLibrary(schemaVersion: 1, items: items);

/// 造一个四词词库（够出选义题）。
List<VocabItem> _four() => [
      _fresh('1', word: 'alpha'),
      _fresh('2', word: 'beta'),
      _fresh('3', word: 'gamma'),
      _fresh('4', word: 'delta'),
    ];

void main() {
  group('装轮', () {
    test('start：队列 / 分母 / 指针 / 计数都归零', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      expect(s.queue.length, 4);
      expect(s.roundTotal, 4);
      expect(s.index, 0);
      expect(s.counts.total, 0);
      expect(s.card?.id, '1');
      expect(s.retrying, isFalse);
      expect(s.spelling, isNull);
    });

    test('start：重新装一轮会清掉上一轮的小结与提示', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      s.grade(ReviewGrade.good);
      expect(s.counts.total, 1);
      s.start(_four());
      expect(s.counts.total, 0);
      expect(s.gradeInfo, isEmpty);
      expect(s.index, 0);
    });

    test('空队列：card 为 null，评分不炸', () {
      final s = StudySession(library: _lib(const []), now: _now);
      s.start(const []);
      expect(s.card, isNull);
      final out = s.grade(ReviewGrade.good);
      expect(out.advanced, isFalse);
      expect(s.counts.total, 0);
    });
  });

  group('评分', () {
    test('认识：写进词库、间隔 1 天、推进到下一张', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      final out = s.grade(ReviewGrade.good);
      expect(out.advanced, isTrue);
      expect(out.requeued, isFalse);
      expect(out.interval, 1);
      expect(out.label, '认识');
      expect(s.index, 1);
      // 词库确实改了
      final item = s.library.items.firstWhere((it) => it.id == '1');
      expect(item.reviewState.repetitions, 1);
      expect(item.reviewState.due, isNotNull);
      expect(s.counts.know, 1);
      expect(s.gradeInfo, contains('1 天后'));
    });

    test('忘记：追加到队尾加练、计入忘记', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      final out = s.grade(ReviewGrade.again);
      expect(out.requeued, isTrue);
      expect(s.queue.length, 5);
      expect(s.queue.last.id, '1');
      expect(s.counts.forgot, 1);
      expect(s.forgotIds, ['1']);
      expect(s.extraCount, 1);
      // 进了重学：relearn +1
      final item = s.library.items.firstWhere((it) => it.id == '1');
      expect(item.reviewState.relearn, 1);
    });

    test('模糊：不追加到队尾（模糊就是本轮收尾，不是再来一遍）', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      final out = s.grade(ReviewGrade.hard);
      expect(out.requeued, isFalse);
      expect(s.queue.length, 4);
      expect(s.counts.fuzzy, 1);
      expect(s.counts.forgot, 0);
    });

    test('同一张卡连续评两次忘记，会一直回队尾（不封顶）', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      s.grade(ReviewGrade.again); // 队尾加 '1'
      s.start(s.queue); // 用新队列再跑
      expect(s.queue.length, 5);
    });

    test('learnPass：一次写库同时记 rating 与「选对次数」', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      s.grade(ReviewGrade.hard, learnPass: true);
      final item = s.library.items.firstWhere((it) => it.id == '1');
      expect(item.reviewState.repetitions, 1);
      expect(item.reviewState.meaningPasses, 1);
    });

    test('learnPass: false 把选对次数归零', () {
      final base = _four();
      base[0] = base[0].copyWith(
        reviewState: base[0].reviewState.copyWith(meaningPasses: 2),
      );
      final s = StudySession(library: _lib(base), now: _now);
      s.start(base);
      s.grade(ReviewGrade.again, learnPass: false);
      final item = s.library.items.firstWhere((it) => it.id == '1');
      expect(item.reviewState.meaningPasses, 0);
    });

    test('takeFirstNewBump：同一个新词只算一次', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      final item = s.library.items.first;
      expect(s.takeFirstNewBump(item), isTrue);
      expect(s.takeFirstNewBump(item), isFalse);
    });

    test('takeFirstNewBump：已经学过的词不算', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      final learned = s.library.items.first.copyWith(
        reviewState: const ReviewState(due: '2026-04-01T00:00:00.000Z', interval: 5, repetitions: 2),
      );
      expect(s.takeFirstNewBump(learned), isFalse);
    });
  });

  group('选中文释义', () {
    test('词库够 4 个选项时给出四个选项且只有一个正确', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      final opts = s.options;
      expect(opts.length, 4);
      expect(opts.where((o) => o.correct).length, 1);
      expect(s.correctOption, greaterThanOrEqualTo(0));
      expect(opts[s.correctOption].correct, isTrue);
    });

    test('词库不够（少于 4 个释义）时没有选项，learn 退回 fallback', () {
      final s = StudySession(
        library: _lib([_fresh('1', word: 'alpha')]),
        now: _now,
      );
      s.start([_fresh('1', word: 'alpha')]);
      expect(s.options, isEmpty);
      expect(s.correctOption, -1);
      final step = s.learn(LearnAction.correct);
      expect(step.kind, LearnStepKind.fallback);
      // fallback 不改词库
      expect(s.library.items.single.reviewState.repetitions, 0);
    });

    test('第一次选对：判模糊（hard）并进卡', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      final step = s.learn(LearnAction.correct);
      expect(step.kind, LearnStepKind.card);
      expect(step.grade, ReviewGrade.hard);
      expect(step.pass, isTrue);
      expect(step.label, '模糊 · 第一次选对');
      expect(s.counts.fuzzy, 1);
      expect(s.index, 1);
    });

    test('第二次选对：判认识（good）', () {
      final base = _four();
      base[0] = base[0].copyWith(
        reviewState: base[0].reviewState.copyWith(meaningPasses: 1),
      );
      final s = StudySession(library: _lib(base), now: _now);
      s.start(base);
      final step = s.learn(LearnAction.correct);
      expect(step.grade, ReviewGrade.good);
      expect(step.label, '认识 · 又选对一次');
      expect(s.counts.know, 1);
    });

    test('看答案：判 hold + again + 自动，但不写库（等 UI 过场后再评）', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      final step = s.learn(LearnAction.reveal);
      expect(step.kind, LearnStepKind.hold);
      expect(step.grade, ReviewGrade.again);
      expect(step.auto, isTrue);
      expect(step.label, '不认识 · 看了答案');
      expect(s.library.items.first.reviewState.relearn, 0);
      expect(s.index, 0);
    });

    test('选错：判 hold + again + 标红，不自动', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      final step = s.learn(LearnAction.wrong);
      expect(step.kind, LearnStepKind.hold);
      expect(step.wrong, isTrue);
      expect(step.auto, isFalse);
      expect(step.label, '不认识 · 选错了');
    });
  });

  group('组末拼写', () {
    test('每组 2 词：走满本组就停下来拼写，不直接换卡', () {
      final s = StudySession(library: _lib(_four()), now: _now, groupSize: 2);
      s.start(_four());
      // 第 1 张评完 → index 1（还没到组末）
      expect(s.grade(ReviewGrade.good).advanced, isTrue);
      expect(s.index, 1);
      expect(s.spelling, isNull);
      // 第 2 张评完 → 到组末，进拼写测试
      final out = s.grade(ReviewGrade.good);
      expect(out.advanced, isFalse);
      expect(s.index, 1);
      expect(s.spelling?.active, isTrue);
      expect(s.spelling?.total, 2);
      expect(s.card?.id, '1', reason: '拼写期间当前卡换成测试词');
    });

    test('组末拼写：拼对进下一词，全部拼完指针推到组末', () {
      final s = StudySession(library: _lib(_four()), now: _now, groupSize: 2);
      s.start(_four());
      s.grade(ReviewGrade.good);
      s.grade(ReviewGrade.good);
      expect(s.spelling?.card?.id, '1');
      expect(s.checkSpelling('alpha'), isTrue);
      expect(s.spelling?.index, 1);
      expect(s.spelling?.card?.id, '2');
      expect(s.checkSpelling('beta'), isTrue);
      expect(s.spelling, isNull);
      expect(s.index, 2);
    });

    test('组末拼写：拼错落库判重学、打标签，并等着重打', () {
      final s = StudySession(library: _lib(_four()), now: _now, groupSize: 2);
      s.start(_four());
      s.grade(ReviewGrade.good);
      s.grade(ReviewGrade.good);
      expect(s.checkSpelling('alph'), isFalse);
      expect(s.spelling?.miss?.typed, 'alph');
      expect(s.spelling?.miss?.word, 'alpha');
      expect(s.spelling?.miss?.meaning, contains('释义1'));
      expect(s.spelling?.input, isEmpty);
      final item = s.library.items.firstWhere((it) => it.id == '1');
      expect(item.tags, contains(spellingMissTag));
      expect(item.reviewState.relearn, 1);
      // 组末拼错不重排（验收，不是加练）
      expect(s.queue.length, 4);
      expect(s.counts.forgot, 1);
    });

    test('组末拼写：重打阶段再错就清空输入、原文继续显示', () {
      final s = StudySession(library: _lib(_four()), now: _now, groupSize: 2);
      s.start(_four());
      s.grade(ReviewGrade.good);
      s.grade(ReviewGrade.good);
      s.checkSpelling('alph');
      expect(s.checkSpelling('alp'), isFalse);
      expect(s.spelling?.miss?.typed, 'alp');
      expect(s.spelling?.input, isEmpty);
      // 判定已定，不会再写一次库
      expect(s.counts.forgot, 1);
    });

    test('拼写测试期间 forward 不生效', () {
      final s = StudySession(library: _lib(_four()), now: _now, groupSize: 2);
      s.start(_four());
      s.grade(ReviewGrade.good);
      s.grade(ReviewGrade.good);
      expect(s.spelling?.active, isTrue);
      expect(s.forward(), isFalse);
      expect(s.index, 1);
    });

    test('setSpellingInput：受控输入框写回状态', () {
      final s = StudySession(library: _lib(_four()), now: _now, groupSize: 2);
      s.start(_four());
      s.grade(ReviewGrade.good);
      s.grade(ReviewGrade.good);
      s.setSpellingInput('alp');
      expect(s.spelling?.input, 'alp');
    });

    test('groupSize 为 0（不分组）：一路换卡，不做组末拼写', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      for (var i = 0; i < 3; i++) {
        expect(s.grade(ReviewGrade.good).advanced, isTrue);
      }
      expect(s.spelling, isNull);
      expect(s.index, 3);
    });
  });

  group('卡面拼写', () {
    test('拼对 = 认识', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      expect(s.checkSpelling('alpha'), isTrue);
      expect(s.counts.know, 1);
      expect(s.index, 1);
    });

    test('拼错 = 忘记 + 打标签 + 回队尾', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      expect(s.checkSpelling('alfa'), isFalse);
      expect(s.queue.last.id, '1');
      final item = s.library.items.firstWhere((it) => it.id == '1');
      expect(item.tags, contains(spellingMissTag));
      expect(s.gradeInfo, contains('拼错了'));
    });

    test('大小写与多余空格不算错', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      expect(s.checkSpelling('  ALPHA  '), isTrue);
    });
  });

  group('导航', () {
    test('back：回上一张，第一张时无效', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      expect(s.back(), isFalse);
      s.grade(ReviewGrade.good);
      expect(s.index, 1);
      expect(s.back(), isTrue);
      expect(s.index, 0);
    });

    test('forward：不评分直接换；队尾时无效', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      expect(s.forward(), isTrue);
      expect(s.index, 1);
      expect(s.counts.total, 0, reason: '没评分，不该记账');
      s.forward();
      s.forward();
      expect(s.index, 3);
      expect(s.forward(), isFalse);
    });

    test('clearMeaningGate：选释义后放行门禁', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      s.clearMeaningGate();
      expect(s.meaningCleared, isTrue);
      s.forward();
      expect(s.meaningCleared, isFalse, reason: '换卡要重置');
    });

    test('clearGradeInfo：清掉提示文案', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      s.grade(ReviewGrade.good);
      expect(s.gradeInfo, isNotEmpty);
      s.clearGradeInfo();
      expect(s.gradeInfo, isEmpty);
    });
  });

  group('收尾重练', () {
    test('没有忘记过任何词时不开重练', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      s.grade(ReviewGrade.good);
      expect(s.retryForgot(), isFalse);
    });

    test('忘记过的词重练：本轮只发起一次', () {
      final s = StudySession(library: _lib(_four()), now: _now);
      s.start(_four());
      s.grade(ReviewGrade.again);
      expect(s.canRetryForgot, isTrue);
      expect(s.retryForgot(), isTrue);
      expect(s.retrying, isTrue);
      expect(s.queue.length, 1);
      expect(s.queue.single.id, '1');
      expect(s.roundTotal, 1);
      expect(s.index, 0);
      expect(s.counts.total, 0, reason: '重练是新账本');
      expect(s.canRetryForgot, isFalse);
      // 第二次不发起
      expect(s.retryForgot(), isFalse);
    });
  });

  group('fmtInterval', () {
    test('四档文案', () {
      expect(fmtInterval(0), '稍后');
      expect(fmtInterval(1), '1 天后');
      expect(fmtInterval(6), '6 天后');
      expect(fmtInterval(29), '29 天后');
      expect(fmtInterval(30), '1 个月后');
      expect(fmtInterval(90), '3 个月后');
    });
  });

  group('ExtraRound 与队列的配合', () {
    test('beginExtraRound 记首见出场次数', () {
      final round = beginExtraRound(['a', 'b', 'a']);
      expect(round.appearances['a'], 2);
      expect(round.appearances['b'], 1);
      expect(round.retried, isFalse);
    });
  });
}
