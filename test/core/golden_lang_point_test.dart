import 'package:dlaoshi_app/core/golden_lang_point.dart';
import 'package:dlaoshi_app/core/writing.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

Sentence _s({List<String>? phrases, List<String>? idioms}) => Sentence(
      id: 's1',
      paraId: 'p01',
      text: 'The iPhone will come with a better camera.',
      languages: <SentenceLanguage>[
        SentenceLanguage(
          phrases: phrases,
          idioms: idioms,
          usage: const <String>['so-called 常带保留态度（中文说明，不该进选块）'],
        ),
      ],
    );

WritingRecord _record({
  String articleId = 'a1',
  String? sentenceId = 's1',
  String? focus,
}) =>
    WritingRecord(
      at: '2026-10-27T00:00:00.000Z',
      articleId: articleId,
      sentenceId: sentenceId,
      text: 'x',
      feedback: const WritingFeedback(),
      source: WritingSource.drillSentence,
      task: ImitationTask(task: 't', model: 'm', focus: focus),
    );

void main() {
  group('langPointChoices：本句可单练的词块', () {
    test('拆「英文 — 中文」，短语 + 习语都收，中文用法不进列表', () {
      final choices = langPointChoices(_s(
        phrases: <String>['come with — 配备，附带', 'much of an improvement — 很大的改进'],
        idioms: <String>['not much of a — 算不上好的'],
      ));
      expect(
        choices.map((c) => c.en),
        <String>['come with', 'much of an improvement', 'not much of a'],
      );
      expect(
        choices.map((c) => c.zh),
        <String?>['配备，附带', '很大的改进', '算不上好的'],
      );
      expect(choices.every((c) => !c.done), isTrue);
    });

    test('没有释义的也能用；同句重复只留一条（大小写 / 空白不敏感）', () {
      final choices = langPointChoices(_s(
        phrases: <String>['come  with', 'Come With', 'serve small niches — 服务小众市场'],
      ));
      expect(
        choices.map((c) => c.en),
        <String>['come  with', 'serve small niches'],
      );
      expect(choices.first.zh, isNull);
    });

    test('没有语言点 / 空句子 → 空列表', () {
      expect(langPointChoices(_s()), isEmpty);
      expect(langPointChoices(null), isEmpty);
    });

    test('已练过的打 done', () {
      final done = <String>{langPointKey('come with')};
      final choices = langPointChoices(
        _s(phrases: <String>['come with — 配备', 'serve small niches']),
        doneFocus: done,
      );
      expect(choices.map((c) => c.done), <bool>[true, false]);
    });

    test('加入本课的 extraPoints 追加在后，同英文不重复；id 稳定', () {
      final choices = langPointChoices(
        _s(phrases: <String>['come with — 配备']),
        doneFocus: const <String>{},
        extraPoints: <({String en, String? zh})>[
          (en: 'come with', zh: '重复'),
          (en: 'come to an end', zh: '结束'),
        ],
      );
      expect(
        choices.map((c) => c.en),
        <String>['come with', 'come to an end'],
      );
      expect(choices.first.zh, '配备');
      expect(langPointChoiceId('s1', 'come to an end'), 'lp:s1:come-to-an-end');
      expect(langPointChoiceId('s1', '  '), 'lp:s1:x');
    });
  });

  group('doneLangPoints / langPointKey', () {
    test('只认同篇同句的 focus（别的篇 / 别的句不算）', () {
      final set = doneLangPoints(
        <WritingRecord>[
          _record(focus: 'come with'),
          _record(sentenceId: 's2', focus: 'come with'),
          _record(articleId: 'a2', focus: 'serve'),
          _record(focus: null),
        ],
        'a1',
        's1',
      );
      expect(set, <String>{'come with'});
    });

    test('langPointKey 压空白、转小写', () {
      expect(langPointKey('  Come   With '), 'come with');
    });
  });
}
