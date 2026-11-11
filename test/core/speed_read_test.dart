import 'package:dlaoshi_app/core/speed_read.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

Sentence sent(String text, {List<String> vocab = const [], SentenceLanguage? language, List<SentenceLanguage>? languages}) =>
    Sentence(
      id: 's1',
      paraId: 'p01',
      text: text,
      vocab: vocab,
      language: language,
      languages: languages,
    );

/// 固定返回 0 的「随机」：`shuffleQuiz` 会把原序打散成确定顺序，便于断言。
double zero() => 0;

void main() {
  group('wordCount / targetMs', () {
    test('词数按空白切，空串算 0', () {
      expect(wordCount('one two three'), 3);
      expect(wordCount('   '), 0);
      expect(wordCount(''), 0);
    });

    test('目标时长 = 词数 / WPM + 思考余量', () {
      // 5 词 / 60wpm = 5 秒，加 1.5 秒余量
      expect(targetMs('a b c d e', wpm: 60), 6500);
    });

    test('WPM 低于 50 按 50 算，且给上下限', () {
      expect(targetMs('a b c d e', wpm: 10), targetMs('a b c d e', wpm: 50));
      expect(targetMs('x'), minTargetMs);
      final long = List<String>.filled(400, 'word').join(' ');
      expect(targetMs(long), maxTargetMs);
    });

    test('默认 WPM 是 120', () {
      expect(targetMs('a b c d e'), targetMs('a b c d e', wpm: defaultWpm));
    });
  });

  group('pickDrill：优先语言点搭配', () {
    test('旧的单条 language 里的搭配优先，且给四选一', () {
      final s = sent(
        'Investments in renewables are ramping up.',
        language: const SentenceLanguage(phrases: ['ramp up']),
      );
      final d = pickDrill(s, rnd: zero)!;
      expect(d.via, SpeedReadVia.phrase);
      expect(d.prompt, contains('____'));
      expect(d.options, hasLength(4));
      expect(d.options, contains(d.answer));
      expect(checkDrill(d, d.answer), isTrue);
    });

    test('languages[] 里的搭配同样优先（手动改过的走这条）', () {
      final s = sent(
        'Investments in renewables are ramping up.',
        languages: const [SentenceLanguage(phrases: ['ramp up'], source: LanguageSource.ai)],
      );
      final d = pickDrill(s, rnd: zero)!;
      expect(d.via, SpeedReadVia.phrase);
      expect(d.answer.toLowerCase(), 'ramping');
    });

    test('没有语言点时挖生词', () {
      final s = sent('The generator transforms rotation into power.', vocab: ['rotation']);
      final d = pickDrill(s, rnd: zero)!;
      expect(d.via, SpeedReadVia.vocab);
    });

    test('既没语言点也没生词时挖最长实词', () {
      final s = sent('The generator transforms rotation into power.');
      final d = pickDrill(s, rnd: zero)!;
      expect(d.via, SpeedReadVia.word);
      expect(d.answer.length, greaterThanOrEqualTo(4));
    });

    test('空句子出不了题', () {
      expect(pickDrill(sent('   ')), isNull);
      expect(pickTargetBlank(sent('   ')), isNull);
    });

    test('停用词不会被当成挖空目标', () {
      // 整句都是停用词，也没有 ≥4 字母的实词 → 出不了题
      final d = pickDrill(sent('the and that with this from'));
      expect(d, isNull);
    });
  });

  group('pickTargetBlank', () {
    test('挖空后句子保留上下文，只把目标词换成 ____', () {
      final b = pickTargetBlank(sent('The generator transforms rotation into power.', vocab: ['rotation']))!;
      expect(b.via, SpeedReadVia.vocab);
      expect(b.blanked, contains('____'));
      expect(b.blanked, isNot(contains('rotation')));
      expect(b.surface.toLowerCase(), 'rotation');
    });

    test('词组里挑最长的那个实词挖空（与 Web 一致，不是整段挖）', () {
      final b = pickTargetBlank(
        sent('Investments in renewables are ramping up.', language: const SentenceLanguage(phrases: ['ramping up'])),
      )!;
      expect(b.via, SpeedReadVia.phrase);
      expect(b.surface.toLowerCase(), 'ramping');
    });
  });

  group('checkDrill', () {
    final d = SpeedReadDrill(
      prompt: 'a ____ b',
      answer: 'well-targeted',
      accept: const ['well-targeted'],
      via: SpeedReadVia.word,
      options: const ['well-targeted', 'x', 'y', 'z'],
    );

    test('判分忽略大小写 / 连字符', () {
      expect(checkDrill(d, 'Well Targeted'), isTrue);
      expect(checkDrill(d, 'WELLTARGETED'), isTrue);
      expect(checkDrill(d, 'wrong'), isFalse);
    });

    test('空输入一律判错', () {
      expect(checkDrill(d, '   '), isFalse);
    });
  });

  group('summarize', () {
    test('汇总平均速度与超时 / 拷打数', () {
      final s = summarize(const [
        SpeedRow(words: 10, ms: 3000),
        SpeedRow(words: 10, ms: 6000, slow: true, drillOk: true),
      ]);
      expect(s.count, 2);
      expect(s.slow, 1);
      expect(s.drillTotal, 1);
      expect(s.drillCorrect, 1);
      expect(s.avgWpm, ((20 / 9000) * 60000).round());
    });

    test('一句都没有时不会除零', () {
      final s = summarize(const []);
      expect(s.count, 0);
      expect(s.avgWpm, 0);
      expect(s.slow, 0);
      expect(s.drillTotal, 0);
      expect(s.drillCorrect, 0);
    });

    test('拷打答错不算对', () {
      final s = summarize(const [SpeedRow(words: 5, ms: 2000, drillOk: false)]);
      expect(s.drillTotal, 1);
      expect(s.drillCorrect, 0);
    });
  });

  group('speedCursorKey', () {
    test('键名带上 articleKey，不同正文不串篇', () {
      expect(speedCursorKey('doc:1@abc'), 'reader:speedCursor:doc:1@abc');
      expect(speedCursorKey('a@1'), isNot(speedCursorKey('a@2')));
    });

    test('同一篇重开键一样，能续上', () {
      const k = 'doc:1@abc';
      expect(speedCursorKey(k), speedCursorKey(k));
    });
  });

  group('contentWords', () {
    test('去掉短词、停用词与非字母', () {
      final words = contentWords('The generators are transforming (rotation), into power.');
      expect(words, contains('generators'));
      expect(words, contains('transforming'));
      expect(words, contains('rotation'));
      expect(words, isNot(contains('The')));
      expect(words, isNot(contains('into')));
      expect(words, isNot(contains('are')));
    });
  });
}
