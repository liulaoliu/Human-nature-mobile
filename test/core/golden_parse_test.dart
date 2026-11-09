import 'dart:convert';

import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_exam.dart';
import 'package:dlaoshi_app/core/golden_parse.dart';
import 'package:flutter_test/flutter_test.dart';

const _text =
    'In response to the pandemic, remote collaboration has become the new norm.';
const _zh = '为了应对疫情，远程协作已经成为新常态。';

final List<GoldenTextMeta> _sentences = <GoldenTextMeta>[
  const GoldenTextMeta(id: 's1', text: _text, translation: _zh),
];

Map<String, Object?> _raw() => <String, Object?>{
      'source': 'ai',
      'summary': '核心',
      'outline': <Object?>[
        <String, Object?>{
          'paraId': 'p01',
          'role': 'intro',
          'points': <String>['要点'],
        },
      ],
      'selected': <String>['s1', 's404'],
      'sentences': <Object?>[
        <String, Object?>{
          'id': 's1',
          'pattern': 'In response to + n., … has become …',
          'targets': <Object?>[
            <String, Object?>{
              'en': 'in response to',
              'zh': '为了应对',
              'kind': 'collocation',
            },
            <String, Object?>{
              'en': 'made up',
              'zh': '编造',
              'kind': 'word',
            },
          ],
        },
        <String, Object?>{'id': 's404', 'targets': <Object?>[]},
      ],
    };

void main() {
  group('normalize / prune 金句课', () {
    test('本课设置保留填空单位；旧数据缺省不在解析层硬写', () {
      final target = normalizeGoldenLesson(
        <String, Object?>{..._raw(), 'options': <String, Object?>{'blankUnit': 'target'}},
        _sentences,
      );
      expect(target?.options.blankUnit, GoldenBlankUnit.target);
      final old = normalizeGoldenLesson(_raw(), _sentences);
      expect(old?.options.blankUnit, isNull);
    });

    test('未知句子与编造目标被丢掉，保留有效内容', () {
      final lesson = normalizeGoldenLesson(_raw(), _sentences);
      expect(lesson, isNotNull);
      expect(lesson!.sentences, hasLength(1));
      expect(lesson.sentences[0].targets.map((t) => t.en), <String>['in response to']);
      expect(lesson.sentences[0].zh, _zh);
      expect(lesson.selected, <String>['s1']);
    });

    test('改正文后内容对不上就作废', () {
      final lesson = normalizeGoldenLesson(_raw(), _sentences)!;
      expect(
        pruneGoldenLesson(
          lesson,
          <GoldenTextMeta>[
            const GoldenTextMeta(id: 's1', text: 'Completely different.'),
          ],
        ),
        isNull,
      );
    });

    test('仿写考试题随课程解析；改正文后对不上的题被 prune', () {
      final withExam = normalizeGoldenLesson(
        <String, Object?>{
          ..._raw(),
          'options': <String, Object?>{'examAfter': 10},
          'exam': <Object?>[
            <String, Object?>{
              'sentenceId': 's1',
              'task': '用这个结构写一句新句子。',
              'model': _text,
              'mustUse': <String>['in response to', 'invented phrase'],
              'rubric': <Object?>[
                <String, Object?>{'dimension': '结构运用', 'weight': 100},
              ],
            },
            <String, Object?>{'sentenceId': 's404', 'task': '坏题'},
          ],
        },
        _sentences,
      );
      expect(withExam?.options.examAfter, 10);
      expect(withExam?.exam, hasLength(1));
      expect(withExam!.exam![0].mustUse, <String>['in response to']);
      expect(pruneGoldenLesson(withExam, _sentences)?.exam, hasLength(1));
      expect(
        pruneGoldenLesson(
          withExam,
          <GoldenTextMeta>[
            const GoldenTextMeta(id: 's1', text: 'Completely different.'),
          ],
        ),
        isNull,
      );
    });

    test('extraPoints：只留当前句子，同英文去重，坏 kind 归 chunk', () {
      final lesson = normalizeGoldenLesson(
        <String, Object?>{
          ..._raw(),
          'extraPoints': <Object?>[
            <String, Object?>{
              'sentenceId': 's1',
              'en': 'come to an end',
              'zh': '结束',
              'kind': 'chunk',
              'source': 'ai',
            },
            <String, Object?>{
              'sentenceId': 's1',
              'en': 'come  to an end',
              'kind': 'weird',
            },
            <String, Object?>{
              'sentenceId': 's404',
              'en': 'gone',
              'kind': 'chunk',
            },
          ],
        },
        _sentences,
      );
      expect(lesson?.extraPoints, hasLength(1));
      expect(lesson!.extraPoints![0].sentenceId, 's1');
      expect(lesson.extraPoints![0].kind, GoldenExtraPointKind.chunk);
      expect(lesson.extraPoints![0].source, GoldenExtraPointSource.ai);
    });

    test('导入合并时 extraPoints 取并集，不因重新生成丢掉', () {
      final base = normalizeGoldenLesson(
        <String, Object?>{
          ..._raw(),
          'extraPoints': <Object?>[
            <String, Object?>{
              'sentenceId': 's1',
              'en': 'come to an end',
              'kind': 'chunk',
            },
          ],
        },
        _sentences,
      )!;
      final next = normalizeGoldenLesson(
        <String, Object?>{
          ..._raw(),
          'summary': '新',
          'extraPoints': <Object?>[
            <String, Object?>{
              'sentenceId': 's1',
              'en': 'bring an end to',
              'kind': 'chunk',
            },
          ],
        },
        _sentences,
      )!;
      final merged = mergeGoldenIntoArticle(
        existing: base,
        incoming: next,
        existingUpdatedAt: '2026-10-01T00:00:00.000Z',
        incomingUpdatedAt: '2026-10-02T00:00:00.000Z',
      );
      expect(
        merged?.extraPoints?.map((p) => p.en),
        <String>['come to an end', 'bring an end to'],
      );
      final dangling = next.copyWith(
        extraPoints: () => <GoldenExtraPoint>[
          const GoldenExtraPoint(
            sentenceId: 's404',
            en: 'gone',
            kind: GoldenExtraPointKind.chunk,
            source: GoldenExtraPointSource.user,
          ),
        ],
      );
      final merged2 = mergeGoldenIntoArticle(
        existing: base,
        incoming: dangling,
        existingUpdatedAt: '2026-10-01T00:00:00.000Z',
        incomingUpdatedAt: '2026-10-02T00:00:00.000Z',
      );
      expect(
        merged2?.extraPoints?.map((p) => p.en),
        <String>['come to an end'],
      );
    });

    test('prune 后句子没了，extraPoints 也不留', () {
      final lesson = normalizeGoldenLesson(
        <String, Object?>{
          ..._raw(),
          'extraPoints': <Object?>[
            <String, Object?>{
              'sentenceId': 's1',
              'en': 'come to an end',
              'kind': 'chunk',
            },
          ],
        },
        _sentences,
      )!;
      expect(
        pruneGoldenLesson(
          lesson,
          <GoldenTextMeta>[
            const GoldenTextMeta(id: 's1', text: 'Completely different.'),
          ],
        ),
        isNull,
      );
      expect(pruneGoldenLesson(lesson, _sentences)?.extraPoints, hasLength(1));
      final two = <GoldenTextMeta>[
        ..._sentences,
        const GoldenTextMeta(id: 's2', text: 'Another sentence for testing.'),
      ];
      final onlyZh = normalizeGoldenLesson(
        <String, Object?>{
          ..._raw(),
          'sentences': <Object?>[
            ...(_raw()['sentences'] as List),
            <String, Object?>{'id': 's2', 'zh': '只有译文，没有 targets'},
          ],
          'selected': <String>['s1', 's2'],
          'extraPoints': <Object?>[
            <String, Object?>{
              'sentenceId': 's2',
              'en': 'come to an end',
              'kind': 'chunk',
            },
          ],
        },
        two,
      )!;
      expect(pruneGoldenLesson(onlyZh, two)?.extraPoints, isNull);
    });

    test('drillKey 对文本/目标敏感', () {
      final a = goldenDrillKey('abc', <GoldenTarget>[
        const GoldenTarget(en: 'a', kind: GoldenTargetKind.word),
      ]);
      final b = goldenDrillKey('abc', <GoldenTarget>[
        const GoldenTarget(en: 'a', kind: GoldenTargetKind.word),
      ]);
      final c = goldenDrillKey('abc', <GoldenTarget>[
        const GoldenTarget(en: 'b', kind: GoldenTargetKind.word),
      ]);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('导入旧备份没有 golden 时保留现有金句课', () {
      final lesson = normalizeGoldenLesson(_raw(), _sentences)!;
      final kept = mergeGoldenIntoArticle(
        existing: lesson,
        incoming: null,
        existingUpdatedAt: '2026-10-02T00:00:00.000Z',
        incomingUpdatedAt: '2026-10-01T00:00:00.000Z',
      );
      expect(kept?.summary, lesson.summary);
      final newer = lesson.copyWith(summary: () => '新');
      final merged = mergeGoldenIntoArticle(
        existing: lesson,
        incoming: newer,
        existingUpdatedAt: '2026-10-02T00:00:00.000Z',
        incomingUpdatedAt: '2026-10-03T00:00:00.000Z',
      );
      expect(merged?.summary, '新');
    });
  });

  group('goldenExam 守卫（经 golden_parse 再导出）', () {
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
      final items = parseGoldenExam(raw, _sentences);
      expect(items, hasLength(1));
      expect(items[0].source, GoldenItemSource.ai);
      expect(items[0].mustUse, <String>['has become']);
      expect(items[0].model, _text);
    });

    test('带 ```json fence 的也能解析', () {
      const fenced =
          '```json\n{"items":[{"sentenceId":"s1","task":"写一句新句子。"}]}\n```';
      expect(parseGoldenExam(fenced, _sentences), hasLength(1));
    });

    test('门槛可调 5/10；旧题在正文变化后自动淘汰', () {
      final lesson = normalizeGoldenLesson(
        <String, Object?>{
          ..._raw(),
          'options': <String, Object?>{'examAfter': 10},
        },
        _sentences,
      )!;
      expect(goldenExamAfter(lesson), 10);
      expect(goldenExamAfter(null), 5);
      final items = <GoldenExamItem>[
        makeLocalGoldenExamItem(
          lesson.sentences.first,
          const GoldenTextMeta(id: 's1', text: _text, translation: _zh),
        ),
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
      expect(pruneGoldenExam(items, _sentences), hasLength(1));
      expect(
        normalizeGoldenExam(<String, Object?>{'items': <Object?>[]}, _sentences),
        isEmpty,
      );
    });
  });
}
