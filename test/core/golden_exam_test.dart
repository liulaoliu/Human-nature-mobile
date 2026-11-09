import 'dart:convert';

import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_exam.dart';
import 'package:dlaoshi_app/core/writing.dart';
import 'package:flutter_test/flutter_test.dart';

const _text =
    'In response to the pandemic, remote collaboration has become the new norm.';
const _zh = '为了应对疫情，远程协作已经成为新常态。';

final GoldenTextMeta _meta =
    const GoldenTextMeta(id: 's1', text: _text, translation: _zh);

GoldenLesson _lesson() => GoldenLesson(
      source: GoldenSource.local,
      sentences: <GoldenSentence>[
        const GoldenSentence(
          id: 's1',
          zh: _zh,
          pattern: 'In response to + n., … has become …',
          targets: <GoldenTarget>[
            GoldenTarget(
                en: 'in response to',
                zh: '为了应对',
                kind: GoldenTargetKind.collocation),
            GoldenTarget(
                en: 'has become',
                zh: '已经成为',
                kind: GoldenTargetKind.tense),
          ],
        ),
      ],
      selected: <String>['s1'],
      options: const GoldenLessonOptions(examAfter: 5),
    );

void main() {
  group('goldenExam', () {
    test('本地出题：中文题干 + 原句范句 + 已学词块 + rubric 合计 100', () {
      final lesson = _lesson();
      final item = makeLocalGoldenExamItem(lesson.sentences.first, _meta);
      expect(item.sentenceId, 's1');
      expect(item.model, _text);
      expect(item.task, contains('仿写'));
      expect(item.task, contains(_zh));
      expect(item.mustUse, <String>['in response to', 'has become']);
      expect(item.source, GoldenItemSource.local);
      expect(
        item.rubric.fold<int>(0, (n, r) => n + r.weight),
        100,
      );
    });

    test('单句仿写不依赖整课完成：当前句有内容就能出题', () {
      final lesson = _lesson();
      final item = buildLocalGoldenExamItem(lesson, <GoldenTextMeta>[_meta], 's1');
      expect(item?.sentenceId, 's1');
      expect(item?.model, _text);
      expect(item?.task, contains('仿写'));
      expect(
        buildLocalGoldenExamItem(lesson, <GoldenTextMeta>[_meta], 'missing'),
        isNull,
      );
    });

    test('AI 题：只保留原句里真实出现的 mustUse；坏句子 id 丢弃', () {
      final raw = jsonEncode(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'sentenceId': 's1',
            'task': '用这个结构写一句关于环保的新句子。',
            'structure': 'In response to + n., … has become …',
            'mustUse': <String>['has become', 'invented phrase'],
            'rubric': <Object?>[
              <String, Object?>{'dimension': '结构运用', 'weight': 60},
            ],
          },
          <String, Object?>{'sentenceId': 'missing', 'task': '坏题'},
        ],
      });
      final items = parseGoldenExam(raw, <GoldenTextMeta>[_meta]);
      expect(items, hasLength(1));
      expect(items[0].source, GoldenItemSource.ai);
      expect(items[0].mustUse, <String>['has become']);
      expect(items[0].model, _text);
    });

    test('出题/批改提示词复用现有仿写任务结构', () {
      final prompt = buildGoldenExamPrompt(
        title: 'A',
        sentences: <GoldenExamPromptSentence>[
          const GoldenExamPromptSentence(
            id: 's1',
            text: _text,
            translation: _zh,
            pattern: '...',
            targets: <String>['in response to'],
          ),
        ],
      );
      expect(prompt, contains('"items"'));
      expect(prompt, contains('s1'));
      expect(prompt, contains('不要改写范句'));

      final item = makeLocalGoldenExamItem(_lesson().sentences.first, _meta);
      final task = examToImitation(item);
      expect(task.model, _text);
      expect(task.mustUse, item.mustUse);
      expect(
        buildGoldenExamFeedbackPrompt(
          item,
          'In response to the flood, rescue teams have become faster.',
        ),
        contains('学生作答'),
      );
    });

    test('门槛可调 5/10；旧题在正文变化后自动淘汰', () {
      expect(goldenExamAfter(_lesson()), 5);
      final lesson10 = _lesson().copyWith(
        options: const GoldenLessonOptions(examAfter: 10),
      );
      expect(goldenExamAfter(lesson10), 10);
      final items = <GoldenExamItem>[
        makeLocalGoldenExamItem(lesson10.sentences.first, _meta),
      ];
      expect(
        pruneGoldenExam(
          items,
          <GoldenTextMeta>[
            const GoldenTextMeta(id: 's1', text: 'Changed.'),
          ],
        ),
        isNull,
      );
      expect(pruneGoldenExam(items, <GoldenTextMeta>[_meta]), hasLength(1));
      expect(
        normalizeGoldenExam(
          <String, Object?>{'items': <Object?>[]},
          <GoldenTextMeta>[_meta],
        ),
        isEmpty,
      );
    });

    test('isGoldenExamRecord 只认 goldenExam', () {
      expect(isGoldenExamRecord(WritingSource.goldenExam), isTrue);
      expect(isGoldenExamRecord(WritingSource.writing), isFalse);
      expect(isGoldenExamRecord(null), isFalse);
    });
  });

  group('buildLangPointGoldenItem：单点造句题', () {
    const meta = GoldenTextMeta(
      id: 's1',
      text: 'The iPhone will come with a better camera.',
    );

    test('只要求用上一个词块，题干带上中文，rubric 合计 100', () {
      final item = buildLangPointGoldenItem(
        meta,
        en: 'come with',
        zh: '配备，附带',
      );
      expect(item.sentenceId, 's1');
      expect(item.mustUse, <String>['come with']);
      expect(item.focus, 'come with');
      expect(item.task, contains('come with'));
      expect(item.task, contains('配备，附带'));
      expect(item.task, contains('不要照抄原句'));
      expect(item.rubric.fold<int>(0, (n, r) => n + r.weight), 100);
    });

    test('同一句不同词块生成不同 id；转成仿写任务时带上 focus', () {
      final a = buildLangPointGoldenItem(meta, en: 'come with');
      final b = buildLangPointGoldenItem(meta, en: 'a better camera');
      expect(a.id, isNot(b.id));
      final task = examToImitation(a);
      expect(task.mustUse, <String>['come with']);
      expect(task.focus, 'come with');
      expect(task.task, isNot(contains('配备')));
    });
  });
}
