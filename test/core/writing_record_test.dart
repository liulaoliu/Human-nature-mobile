/// `core/writing_record.dart` 的测试：记录身份、来源白名单、叫法、分页、按题取历史。
///
/// 用例对齐 Web 版 `src/core/writing.test.ts`（369 行）的后 200 行。
library;

import 'package:dlaoshi_app/core/activity/activity.dart' show dayKeyLocal;
import 'package:dlaoshi_app/core/writing.dart';
import 'package:flutter_test/flutter_test.dart';

WritingRecord _rec({
  String at = '2026-10-31T00:00:00.000Z',
  String articleId = 'a',
  String text = 'T',
  String? sentenceId,
  String? examId,
  ImitationTask? task,
  WritingSource? source,
}) =>
    WritingRecord(
      at: at,
      articleId: articleId,
      text: text,
      feedback: const WritingFeedback(),
      sentenceId: sentenceId,
      examId: examId,
      task: task,
      source: source,
    );

void main() {
  group('writingRecordKey', () {
    test('同一内容稳定；换句/换稿/换正文会变', () {
      const baseTask = ImitationTask(task: 't', model: 'm', round: 1);
      String key({
        String text = 'I go to school.',
        String? sentenceId = 's1',
        int? round = 1,
      }) =>
          writingRecordKey(
            at: '2026-10-31T00:00:00.000Z',
            articleId: 'a',
            text: text,
            sentenceId: sentenceId,
            task: baseTask.copyWith(round: () => round),
          );

      expect(key(), key());
      expect(key(), isNot(key(text: 'I went to school.')));
      expect(key(), isNot(key(sentenceId: 's2')));
      expect(key(), isNot(key(round: 2)));
    });
  });

  group('isGoldenWritingRecord', () {
    test('单句仿写 / 整课考试 / 错因订正都算金句课记录', () {
      expect(isGoldenWritingRecord(_rec(source: WritingSource.goldenSentence)), isTrue);
      expect(isGoldenWritingRecord(_rec(source: WritingSource.goldenExam)), isTrue);
      expect(isGoldenWritingRecord(_rec(source: WritingSource.goldenError)), isTrue);
      expect(isGoldenWritingRecord(_rec()), isFalse);
      expect(isGoldenWritingRecord(_rec(source: WritingSource.writing)), isFalse);
    });
  });

  group('addWritingRecord', () {
    test('新记录插到最前', () {
      final out = addWritingRecord(
        <WritingRecord>[_rec(at: '1')],
        _rec(at: '2'),
      );
      expect(out.map((r) => r.at).toList(), <String>['2', '1']);
    });

    test('默认不截断（真丢数据），只在超过提醒线时提示导出', () {
      var list = <WritingRecord>[];
      for (var i = 0; i < 300; i++) {
        list = addWritingRecord(list, _rec(at: '$i'));
      }
      expect(list, hasLength(300));
      for (var i = 300; i < writingHistoryWarnAt + 5; i++) {
        list = addWritingRecord(list, _rec(at: '$i'));
      }
      // 超过提醒线也照收，不能悄悄把旧批改截掉
      expect(list, hasLength(writingHistoryWarnAt + 5));
    });

    test('超过上限截断', () {
      var list = <WritingRecord>[];
      for (var i = 0; i < 5; i++) {
        list = addWritingRecord(list, _rec(at: '$i'), cap: 3);
      }
      expect(list, hasLength(3));
      expect(list.map((r) => r.at).toList(), <String>['4', '3', '2']);
    });
  });

  group('writingRecordLabel：一条记录叫什么', () {
    test('普通仿写 / 整课考试 / 单句仿写 / 语言点造句各叫各的', () {
      expect(writingRecordLabel(_rec(source: WritingSource.writing)), '仿写');
      expect(writingRecordLabel(_rec(source: WritingSource.goldenExam)), '整课考试');
      expect(writingRecordLabel(_rec(source: WritingSource.goldenError)), '错因订正');
      expect(
        writingRecordLabel(_rec(
          source: WritingSource.goldenSentence,
          task: const ImitationTask(task: 'x', model: 'm'),
        )),
        '单句仿写',
      );
      expect(
        writingRecordLabel(_rec(
          source: WritingSource.goldenSentence,
          task: const ImitationTask(
            task: 'x',
            model: 'm',
            mustUse: <String>['come with'],
            focus: 'come with',
          ),
        )),
        '语言点造句 · come with',
      );
      expect(writingRecordLabel(_rec(source: WritingSource.drillSentence)), '拷打造句');
      expect(writingRecordLabel(_rec(source: WritingSource.production)), '奶牛工棚');
      expect(
        writingRecordLabel(_rec(
          source: WritingSource.production,
          task: const ImitationTask(task: 'x', model: 'm', focus: 'follow up'),
        )),
        '奶牛工棚 · follow up',
      );
      expect(writingRecordLabel(_rec()), '仿写');
    });

    test('第二稿在名字里标出来（第 2 稿）', () {
      expect(
        writingRecordLabel(_rec(
          source: WritingSource.goldenSentence,
          task: const ImitationTask(
            task: 'x',
            model: 'm',
            mustUse: <String>['come with'],
            focus: 'come with',
            round: 2,
          ),
        )),
        '语言点造句 · come with（第 2 稿）',
      );
      expect(
        writingRecordLabel(_rec(
          source: WritingSource.goldenSentence,
          task: const ImitationTask(task: 'x', model: 'm', round: 2),
        )),
        '单句仿写（第 2 稿）',
      );
    });
  });

  group('normalizeWritingRecord：外部数据里的来源只认白名单', () {
    test('合法来源原样保留（金句课历史才会出现在小课堂）', () {
      expect(
        normalizeWritingRecord(_rec(source: WritingSource.goldenExam, examId: 'e1')).source,
        WritingSource.goldenExam,
      );
      expect(
        normalizeWritingRecord(_rec(source: WritingSource.goldenSentence, sentenceId: 's1')).sentenceId,
        's1',
      );
      expect(
        normalizeWritingRecord(_rec(source: WritingSource.goldenError, sentenceId: 's1')).source,
        WritingSource.goldenError,
      );
      expect(
        normalizeWritingRecord(_rec(source: WritingSource.writing)).source,
        WritingSource.writing,
      );
      expect(
        normalizeWritingRecord(_rec(source: WritingSource.production)).source,
        WritingSource.production,
      );
      expect(
        normalizeWritingRecord(_rec(source: WritingSource.drillSentence)).source,
        WritingSource.drillSentence,
      );
    });

    test('坏来源当普通仿写；id 不是字符串就丢掉（和服务端同一口径）', () {
      final bad = WritingRecord(
        at: '2026-10-30T00:00:00.000Z',
        articleId: 'a1',
        text: 'T',
        feedback: const WritingFeedback(),
        sentenceId: '42',
        examId: '',
      );
      final out = normalizeWritingRecord(bad);
      expect(out.source, isNull);
      expect(out.sentenceId, '42');
      expect(out.examId, isNull);
      expect(out.recordKey, isNotNull);
    });

    test('已经带了 recordKey 就原样保留（不重算）', () {
      final rec = _rec(sentenceId: 's1').copyWith(recordKey: () => 'fixed-key');
      expect(normalizeWritingRecord(rec).recordKey, 'fixed-key');
    });

    test('WritingSource.byId 认不出返回 null', () {
      expect(WritingSource.byId('bogus'), isNull);
      expect(WritingSource.byId(42), isNull);
      expect(WritingSource.byId('production'), WritingSource.production);
    });
  });

  group('historyPage：学习历史只分页显示，不删记录', () {
    test('默认一页 100 条，返回剩余条数和下一页上限', () {
      final list = List<int>.generate(250, (i) => i);
      final res = historyPage(list, writingHistoryPage);
      expect(res.rows, hasLength(100));
      expect(res.rows.first, 0);
      expect(res.rest, 150);
      expect(res.next, 200);
    });

    test('点「显示更多」翻倍；到底了 rest = 0', () {
      final list = List<int>.generate(250, (i) => i);
      expect(historyPage(list, 200).rest, 50);
      final done = historyPage(list, 300);
      expect(done.rows, hasLength(250));
      expect(done.rest, 0);
    });

    test('空列表 / 坏入参不崩（小于一页按一页算）', () {
      expect(historyPage(<int>[], 200).rows, isEmpty);
      expect(historyPage(<int>[], 200).rest, 0);
      expect(historyPage(<int>[], 200).next, 300);
      expect(historyPage(<int>[1, 2, 3], 0).rows, hasLength(3));
    });
  });

  group('countWritesOnDay', () {
    test('只数逻辑日当天（04:00 结算）', () {
      final list = <WritingRecord>[
        _rec(at: DateTime(2026, 10, 20, 9).toUtc().toIso8601String()),
        _rec(at: DateTime(2026, 10, 20, 2).toUtc().toIso8601String()),
      ];
      expect(countWritesOnDay(list, '2026-10-20'), 1);
      expect(countWritesOnDay(list, '2026-10-19'), 1);
      expect(dayKeyLocal(DateTime(2026, 10, 20, 2)), '2026-10-19');
    });

    test('坏时间戳忽略，不抛错', () {
      expect(countWritesOnDay(<WritingRecord>[_rec(at: '不是时间')], '2026-10-20'), 0);
    });
  });

  group('writingAttemptsFor：同一题的历史批改', () {
    test('只取同篇同句同 focus，按时间正序（最后一条是最新）', () {
      const taskComeWith = ImitationTask(
        task: 'x',
        model: 'M',
        focus: 'come with',
      );
      const taskServed = ImitationTask(task: 'x', model: 'M', focus: 'served');
      final list = <WritingRecord>[
        _rec(at: '2026-10-29T02:00:00.000Z', text: 'second', sentenceId: 's1', task: taskComeWith),
        _rec(at: '2026-10-29T01:00:00.000Z', text: 'first', sentenceId: 's1', task: taskComeWith),
        _rec(at: '2026-10-29T03:00:00.000Z', text: 'other focus', sentenceId: 's1', task: taskServed),
        _rec(at: '2026-10-29T04:00:00.000Z', articleId: 'a2', text: 'other article', sentenceId: 's1'),
        _rec(at: '2026-10-29T05:00:00.000Z', text: 'other sentence', sentenceId: 's2'),
      ];
      final out = writingAttemptsFor(
        list,
        const WritingAttemptIdentity(articleId: 'a', sentenceId: 's1', focus: 'come with'),
      );
      expect(out.map((x) => x.text).toList(), <String>['first', 'second']);
    });

    test('整课考试按 examId 取', () {
      final list = <WritingRecord>[
        _rec(at: '2026-10-29T01:00:00.000Z', sentenceId: 's1', examId: 'e1'),
        _rec(at: '2026-10-29T02:00:00.000Z', sentenceId: 's1', examId: 'e2'),
      ];
      final out = writingAttemptsFor(
        list,
        const WritingAttemptIdentity(articleId: 'a', examId: 'e1'),
      );
      expect(out, hasLength(1));
      expect(out.first.examId, 'e1');
    });
  });
}
