import 'package:dlaoshi_app/core/ecdict.dart';
import 'package:dlaoshi_app/data/dictionary_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真·资源文件的冒烟测试：确认 `assets/ecdict/*.tsv` 打进包之后
/// `rootBundle` 读得出来、`parseEcdict` 吃得下（约 9MB，跑一次几秒）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetDictionary);

  test('从 assets 读真词典：主表有量、词形还原可用、释义非空', () async {
    final ok = await loadDictionary();
    expect(ok, isTrue, reason: 'assets/ecdict/*.tsv 没打进包或格式不对');

    final dict = dictionary()!;
    // 真实 ECDICT 主表是几万条；给个宽松下限，格式错了会远低于这个数
    expect(dict.entries.length, greaterThan(50000));
    expect(dict.forms.length, greaterThan(10000));

    final resolved = resolveWord(dict, 'abandon');
    expect(resolved, isNotNull);
    expect(resolved!.lemma, 'abandon');
    expect(firstLine(resolved.entry.zh), isNotEmpty);

    // 词形还原：不规则 + 规则各来一个
    expect(dictLemmaOf(dict, 'went'), 'go');
    expect(dictLemmaOf(dict, 'abandoned'), 'abandon');
  });
}
