import 'package:dlaoshi_app/core/writing.dart';
import 'package:dlaoshi_app/core/writing_history.dart';
import 'package:flutter_test/flutter_test.dart';

WritingRecord _record({
  String at = '2026-11-01T00:00:00.000Z',
  String articleId = 'A',
  String text = 'I ran.',
  WritingSource? source,
  String? sentenceId,
  String? examId,
  ImitationTask? task,
}) =>
    WritingRecord(
      at: at,
      articleId: articleId,
      text: text,
      feedback: const WritingFeedback(total: 8, max: 10),
      source: source,
      sentenceId: sentenceId,
      examId: examId,
      task: task,
    );

WritingHistoryFilter _filter({
  WritingHistorySource source = WritingHistorySource.all,
  WritingHistoryScope scope = WritingHistoryScope.article,
  String articleId = 'A',
}) =>
    WritingHistoryFilter(source: source, scope: scope, articleId: articleId);

void main() {
  group('writingHistorySourceOf：来源分组', () {
    test('旧记录 / writing 归普通仿写，production / drill 各自分组，金句课也归 writing', () {
      expect(writingHistorySourceOf(_record()), WritingHistorySource.writing);
      expect(
        writingHistorySourceOf(_record(source: WritingSource.writing)),
        WritingHistorySource.writing,
      );
      expect(
        writingHistorySourceOf(_record(source: WritingSource.production)),
        WritingHistorySource.production,
      );
      expect(
        writingHistorySourceOf(_record(source: WritingSource.drillSentence)),
        WritingHistorySource.drillSentence,
      );
      expect(
        writingHistorySourceOf(_record(source: WritingSource.goldenSentence)),
        WritingHistorySource.writing,
      );
    });
  });

  group('filterWritingHistory：范围 + 来源 + 时间倒序', () {
    final history = <WritingRecord>[
      _record(at: '2026-11-01T00:00:00.000Z', text: 'old'),
      _record(
        at: '2026-11-04T00:00:00.000Z',
        text: 'A drill',
        source: WritingSource.drillSentence,
        sentenceId: 'drill:A',
      ),
      _record(
        at: '2026-11-03T00:00:00.000Z',
        text: 'A production',
        source: WritingSource.production,
      ),
      _record(
        at: '2026-11-05T00:00:00.000Z',
        articleId: 'B',
        text: 'B drill',
        source: WritingSource.drillSentence,
      ),
      _record(
        at: '2026-11-06T00:00:00.000Z',
        text: 'golden',
        source: WritingSource.goldenSentence,
      ),
    ];

    test('本篇 + 全部来源：只含本篇非金句记录，最近的在前', () {
      expect(
        filterWritingHistory(history, _filter()).map((r) => r.text).toList(),
        <String>['A drill', 'A production', 'old'],
      );
    });

    test('本篇 + 拷打造句：只含本篇 drill', () {
      expect(
        filterWritingHistory(
          history,
          _filter(source: WritingHistorySource.drillSentence),
        ).map((r) => r.text).toList(),
        <String>['A drill'],
      );
    });

    test('全库 + 拷打造句：跨篇，仍按时间倒序', () {
      expect(
        filterWritingHistory(
          history,
          _filter(
            source: WritingHistorySource.drillSentence,
            scope: WritingHistoryScope.all,
          ),
        ).map((r) => r.text).toList(),
        <String>['B drill', 'A drill'],
      );
    });

    test('金句课记录永远不进入仿写历史筛选', () {
      final got = filterWritingHistory(
        history,
        _filter(scope: WritingHistoryScope.all),
      );
      expect(got.any((r) => r.text == 'golden'), isFalse);
    });

    test('不改原列表', () {
      final before = history.map((r) => r.text).toList();
      filterWritingHistory(history, _filter(scope: WritingHistoryScope.all));
      expect(history.map((r) => r.text).toList(), before);
    });
  });

  group('writingHistoryCounts：当前范围的来源计数', () {
    final history = <WritingRecord>[
      _record(source: WritingSource.writing),
      _record(source: WritingSource.production),
      _record(source: WritingSource.drillSentence),
      _record(articleId: 'B', source: WritingSource.drillSentence),
      _record(source: WritingSource.goldenExam),
    ];

    test('本篇：金句课不计数，来源加起来等于 all', () {
      final counts = writingHistoryCounts(
        history,
        WritingHistoryScope.article,
        'A',
      );
      expect(counts[WritingHistorySource.all], 3);
      expect(counts[WritingHistorySource.writing], 1);
      expect(counts[WritingHistorySource.production], 1);
      expect(counts[WritingHistorySource.drillSentence], 1);
    });

    test('全库：跨篇计数', () {
      final counts = writingHistoryCounts(
        history,
        WritingHistoryScope.all,
        'A',
      );
      expect(counts[WritingHistorySource.all], 4);
      expect(counts[WritingHistorySource.drillSentence], 2);
    });
  });

  group('removeWritingHistory：只清当前筛选，金句课保留', () {
    final history = <WritingRecord>[
      _record(text: 'A writing', source: WritingSource.writing),
      _record(text: 'A drill', source: WritingSource.drillSentence),
      _record(text: 'A golden', source: WritingSource.goldenSentence),
      _record(
        articleId: 'B',
        text: 'B drill',
        source: WritingSource.drillSentence,
      ),
    ];

    test('清本篇拷打造句：不动其它来源、别的篇和金句课', () {
      expect(
        removeWritingHistory(
          history,
          _filter(source: WritingHistorySource.drillSentence),
        ).map((r) => r.text).toList(),
        <String>['A writing', 'A golden', 'B drill'],
      );
    });

    test('清全库拷打造句：两篇 drill 都删，金句课仍在', () {
      expect(
        removeWritingHistory(
          history,
          _filter(
            source: WritingHistorySource.drillSentence,
            scope: WritingHistoryScope.all,
          ),
        ).map((r) => r.text).toList(),
        <String>['A writing', 'A golden'],
      );
    });

    test('清全库全部来源：只保留金句课', () {
      expect(
        removeWritingHistory(
          history,
          _filter(scope: WritingHistoryScope.all),
        ).map((r) => r.text).toList(),
        <String>['A golden'],
      );
    });
  });

  group('来源标签', () {
    test('四种来源都有中文名', () {
      for (final s in WritingHistorySource.values) {
        expect(writingHistorySourceLabel[s], isNotEmpty);
      }
      expect(
        writingHistorySourceLabel[WritingHistorySource.production],
        '奶牛工棚',
      );
    });
  });
}
