import 'package:dlaoshi_app/core/ecdict.dart';
import 'package:dlaoshi_app/data/dictionary_loader.dart';
import 'package:flutter_test/flutter_test.dart';

const String _wordsTsv =
    'abandon\tabandon\t[ə\'bændən]\tv. 放弃\t0\t3\t1\t1500\t1200\n'
    'zebra\tzebra\t[\'ziːbrə]\tn. 斑马\t0\t1\t0\t4000\t4200\n';

const String _formsTsv = 'abandoned\tabandon\nzebras\tzebra\n';

void main() {
  tearDown(resetDictionary);

  group('loadDictionary', () {
    test('读三份表并建好词典', () async {
      final ok = await loadDictionary(
        loader: (name) async => switch (name) {
          'words.tsv' => _wordsTsv,
          'forms.tsv' => _formsTsv,
          'near.tsv' => '',
          _ => null,
        },
      );
      expect(ok, isTrue);
      expect(dictionaryReady(), isTrue);
      final dict = dictionary();
      expect(dict, isNotNull);
      expect(dict!.entries.containsKey('abandon'), isTrue);
      expect(dictLemmaOf(dict, 'abandoned'), 'abandon');
    });

    test('主表缺失时返回 false，不抛错', () async {
      final ok = await loadDictionary(loader: (name) async => null);
      expect(ok, isFalse);
      expect(dictionaryReady(), isFalse);
    });

    test('主表为空串也当没有', () async {
      final ok = await loadDictionary(
        loader: (name) async => name == 'words.tsv' ? '' : null,
      );
      expect(ok, isFalse);
      expect(dictionary(), isNull);
    });

    test('变体表/近似词表读不到时仍能用（只是没有词形还原）', () async {
      final ok = await loadDictionary(
        loader: (name) async => name == 'words.tsv' ? _wordsTsv : null,
      );
      expect(ok, isTrue);
      // 没有 forms 表时，变形词还原不出原形（但原形本身还查得到）
      expect(dictLemmaOf(dictionary()!, 'abandoned'), isNull);
      expect(dictLemmaOf(dictionary()!, 'abandon'), 'abandon');
    });

    test('已加载后再次调用直接返回 true，不重复读', () async {
      var calls = 0;
      await loadDictionary(
        loader: (name) async {
          calls++;
          return name == 'words.tsv' ? _wordsTsv : '';
        },
      );
      final before = calls;
      expect(await loadDictionary(loader: (name) async => null), isTrue);
      expect(calls, before);
    });

    test('并发调用共用同一次加载', () async {
      var calls = 0;
      Future<String?> loader(String name) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return name == 'words.tsv' ? _wordsTsv : '';
      }

      final results = await Future.wait([
        loadDictionary(loader: loader),
        loadDictionary(loader: loader),
        loadDictionary(loader: loader),
      ]);
      expect(results, [true, true, true]);
      expect(calls, 3); // 三份表各读一次，不是 9 次
    });

    test('resetDictionary 之后要重新加载', () async {
      await loadDictionary(
        loader: (name) async => name == 'words.tsv' ? _wordsTsv : '',
      );
      expect(dictionaryReady(), isTrue);
      resetDictionary();
      expect(dictionaryReady(), isFalse);
      expect(dictionary(), isNull);
    });

    test('setDictionary 可以注入现成词典', () {
      final dict = parseEcdict(_wordsTsv, _formsTsv);
      setDictionary(dict);
      expect(dictionaryReady(), isTrue);
      expect(identical(dictionary(), dict), isTrue);
      setDictionary(null);
      expect(dictionaryReady(), isFalse);
    });

    test('loader 抛错被吞掉，返回 false', () async {
      final ok = await loadDictionary(
        loader: (name) async => throw StateError('boom'),
      );
      expect(ok, isFalse);
      expect(dictionary(), isNull);
    });
  });
}
