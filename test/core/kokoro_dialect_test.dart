import 'package:dlaoshi_app/core/kokoro_dialect.dart';
import 'package:flutter_test/flutter_test.dart';

/// 每一组左边是 `package:phonemize`（espeak 教科书 IPA）对我们自己语料的真实
/// 输出，右边是 misaki 0.9.4 对同一个词的真实输出。
///
/// 来源：CrispASR #316 的 `test-kokoro-g2p-316.cpp` 里的 `kGolden` 表，那里
/// 声明「every expectation is misaki's actual output」。这 16 组覆盖了我们
/// 管线能产出的全部 43 个符号，是本项目「方言转换对不对」的验收基准。
const List<(String, String)> _golden = <(String, String)>[
  ('ɔːltˈɜːnəɾɪv', 'ɔltˈɜɹnəTɪv'), // alternative
  ('ˈæmbjələtˌɔːɹi', 'ˈæmbjələtˌɔɹi'), // ambulatory
  ('bˈækɡɹˌaʊndz', 'bˈækɡɹˌWndz'), // backgrounds
  ('sˌɜːɾəfəkˈeɪʃənz', 'sˌɜɹTəfəkˈAʃənz'), // certifications
  ('kənstˈɪtʃʊənsi', 'kənstˈɪʧʊənsi'), // constituency
  ('kənvˈɜːʒənz', 'kənvˈɜɹʒənz'), // conversions
  ('fˈɑːɹðɪŋɡˌeɪl', 'fˈɑɹðɪŋɡˌAl'), // farthingale
  ('hˈɛmɚɹˌɔɪdz', 'hˈɛməɹˌYdz'), // hemorrhoids
  ('ˌɪmpɚfˈɛkʃənz', 'ˌɪmpəɹfˈɛkʃənz'), // imperfections
  ('dʒˌʌkstəpəzˈɪʃən', 'ʤˌʌkstəpəzˈɪʃən'), // juxtaposition
  ('nˈɛtwˌɜːks', 'nˈɛtwˌɜɹks'), // networks
  ('pˈɛtɹoʊdˌɑːlɚz', 'pˈɛtɹOdˌɑləɹz'), // petrodollars
  ('sˌækɹəmˈɛntoʊz', 'sˌækɹəmˈɛntOz'), // sacramento's
  ('stɹˌæŋɡjəlˈeɪʃənz', 'stɹˌæŋɡjəlˈAʃənz'), // strangulations
  ('sˌuːpɚhˈɛɾɚɹədˌaɪn', 'sˌupəɹhˈɛTəɹədˌIn'), // superheterodyne
  ('sˈɪmpəθˌaɪzɪŋ', 'sˈɪmpəθˌIzɪŋ'), // sympathizing
];

void main() {
  group('espeak IPA → misaki 字母表', () {
    test('16 组真实样本逐字节对齐 misaki', () {
      for (final (input, want) in _golden) {
        expect(toMisakiAlphabet(input), want, reason: '输入 $input');
      }
    });

    test('转换后不留任何 espeak 专属写法', () {
      // 这些写法全都在 Kokoro 的 vocab 里，漏一个都不会报错，只会让音频跑偏，
      // 所以必须逐条断言。
      for (final (input, _) in _golden) {
        final conv = toMisakiAlphabet(input);
        expect(espeakResidue(conv), isEmpty, reason: '输入 $input → $conv');
      }
    });

    test('双元音与塞擦音合成单个符号', () {
      expect(toMisakiAlphabet('tʃ'), 'ʧ');
      expect(toMisakiAlphabet('dʒ'), 'ʤ');
      expect(toMisakiAlphabet('eɪ'), 'A');
      expect(toMisakiAlphabet('aɪ'), 'I');
      expect(toMisakiAlphabet('oʊ'), 'O');
      expect(toMisakiAlphabet('əʊ'), 'O', reason: 'en-gb 写法的同一个音');
      expect(toMisakiAlphabet('aʊ'), 'W');
      expect(toMisakiAlphabet('ɔɪ'), 'Y');
      expect(toMisakiAlphabet('ɾ'), 'T');
    });

    test('长音符被丢掉，NURSE 保留 r', () {
      expect(toMisakiAlphabet('tˈuː'), 'tˈu');
      expect(toMisakiAlphabet('spˈiːtʃ'), 'spˈiʧ');
      expect(toMisakiAlphabet('wˈɜːld'), 'wˈɜɹld');
      expect(toMisakiAlphabet('ɜː'), 'ɜɹ');
    });

    test('ɚ 后面已有 ɹ 时不重复', () {
      // espeak 把 "parameters" 写成 pɚɹ…，天真的 ɚ→əɹ 会得到 əɹɹ。
      expect(toMisakiAlphabet('ɚ'), 'əɹ');
      expect(toMisakiAlphabet('pɚɹˈæməɾɚz'), 'pəɹˈæməTəɹz');
    });

    test('替换结果不回扫', () {
      // tʃ → ʧ 之后不能再被扫一遍去命中别的规则。
      expect(toMisakiAlphabet('ʧ'), 'ʧ');
      expect(toMisakiAlphabet('T'), 'T');
      expect(toMisakiAlphabet(''), '');
      expect(toMisakiAlphabet('hello'), 'hello');
      // espeak 有时把近音直接写成 ASCII r。
      expect(toMisakiAlphabet('rɛd'), 'ɹɛd');
      expect(toMisakiAlphabet('ɹɛd'), 'ɹɛd');
    });

    test('幂等：转换过的不再变化', () {
      for (final (input, want) in _golden) {
        expect(toMisakiAlphabet(want), want, reason: '二次转换 $input');
      }
    });

    test('试听那句话转换后是 misaki 字母表', () {
      // 用户 2026-11-16 反馈「reading makes perfect 被读成 reading makes fit」。
      // 改之前 meɪks 是 e+ɪ 两个 token、pɝfɪkt 里的 ɝ 被丢掉；现在应该是
      // mAks + pɜɹfɪkt，与 misaki 同一套字母表。
      const espeak = 'ˈɹɛdɪŋ ˈmeɪks ˈpɝfɪkt.';
      expect(toMisakiAlphabet(espeak), 'ˈɹɛdɪŋ ˈmAks ˈpɜɹfɪkt.');
      expect(espeakResidue(toMisakiAlphabet(espeak)), isEmpty);
    });
  });
}
