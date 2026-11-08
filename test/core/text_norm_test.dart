import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/text_norm.dart';

/// 近似 NFKC：只做全角 ASCII 与连字两项，边界要钉死。
void main() {
  test('全角 ASCII 转半角', () {
    expect(nfkc('ＡＢＣ１２３'), 'ABC123');
    expect(nfkc('！＂＃'), '!"#');
    expect(nfkc('ａｂｃ'), 'abc');
  });

  test('全角空格转普通空格', () {
    expect(nfkc('a\u3000b'), 'a b');
  });

  test('连字拆成字母', () {
    expect(nfkc('ﬁnd'), 'find');
    expect(nfkc('ﬂow'), 'flow');
    expect(nfkc('aﬀair'), 'affair');
    expect(nfkc('oﬃce'), 'office');
    expect(nfkc('raﬄe'), 'raffle');
  });

  test('非全角字符原样保留（含中文、emoji）', () {
    expect(nfkc('中文 abc'), '中文 abc');
    expect(nfkc('🙂'), '🙂');
    expect(nfkc(''), '');
  });
}
