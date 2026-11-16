/// 进入神经 TTS 前把「排版标点」换成能读的字符。
///
/// 2026-11-16 用户报「试听一句正常，实际文章读得不准」：预览句是纯 ASCII，
/// 文章里的所有格 / 缩写用的是弯引号 `’`。`phonemize` 不认它，会把这个词
/// 拆成 `Arabia` + `’` + `ˈɛs`（把 `'s` 念成「S」），所以整篇听起来很怪。
/// Kitten 用同一个音素化器，因此也有同样的问题 —— 不是引擎的锅。
///
/// 这里只改**发音前**的文本；原文、译文、选词区间都不动。
library;

/// 把弯引号、破折号、省略号、零宽字符等归一化。
String normalizeTtsText(String text) {
  var s = text;

  // 不换行空格 / 细空格 → 普通空格。
  s = s.replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ');

  // 弯单引号当撇号用（Arabia’s / don’t）；反引号/acute 也并过来。
  s = s.replaceAll(RegExp(r'[’‘`´]'), "'");

  // 双引号一律去掉：保留会被音素化器当成字面符号读出来。
  s = s.replaceAll(RegExp(r'[“”„«»"]'), ' ');

  // 长破折号是停顿，不是单词；短破折号当连字符（2012–14 → 2012-14）。
  s = s.replaceAll(RegExp(r'[—―]'), ', ');
  s = s.replaceAll('–', '-');

  // 省略号、中文标题括号、零宽/方向控制字符。
  s = s.replaceAll('…', '...');
  s = s.replaceAll(RegExp(r'[【】〔〕]'), ' ');
  s = s.replaceAll(RegExp(r'[\u200B-\u200F\u2060\uFEFF]'), '');

  // 数字 + 缩写：音素化器会把 G20 读成「G economies」、把 20's 读成
  // 「twenty-iss」、把 IMF 读成「imf」。先展开成它认识的词。
  s = s.replaceAllMapped(
    RegExp(r'\bG\s*(\d+)\b', caseSensitive: false),
    (m) => 'G ${m.group(1)}',
  );
  s = s.replaceAllMapped(
    RegExp(r"\b20['’]s\b", caseSensitive: false),
    (_) => "twenty's",
  );
  s = s.replaceAllMapped(
    RegExp(r'\b20s\b', caseSensitive: false),
    (_) => 'twenties',
  );
  const acronyms = <String, String>{
    'IMF': 'I M F',
    'OECD': 'O E C D',
    'CFTC': 'C F T C',
    'WTI': 'W T I',
    'GDP': 'G D P',
    'OPEC': 'O P E C',
    'US': 'U S',
    'UK': 'U K',
    'EU': 'E U',
    'UN': 'U N',
  };
  s = s.replaceAllMapped(
    RegExp(r'\b[A-Z]{2,5}\b'),
    (m) => acronyms[m.group(0)] ?? m.group(0)!,
  );
  s = s.replaceAll('U.S.', 'U S');
  s = s.replaceAll('U.K.', 'U K');
  s = s.replaceAll('e.g.', 'for example');
  s = s.replaceAll('i.e.', 'that is');
  s = s.replaceAll('vs.', 'versus');
  s = s.replaceAll('No.', 'number');
  s = s.replaceAll('%', ' percent ');
  s = s.replaceAll('&', ' and ');
  s = s.replaceAllMapped(
    RegExp(r'\$\s*([\d.,]+)\s*(billion|million|trillion|bn|m)?',
        caseSensitive: false),
    (m) {
      final unit = _unitWord(m.group(2));
      return '${m.group(1)}${unit.isEmpty ? '' : ' $unit'} dollars';
    },
  );
  s = s.replaceAllMapped(
    RegExp(r'£\s*([\d.,]+)\s*(billion|million|trillion|bn|m)?',
        caseSensitive: false),
    (m) {
      final unit = _unitWord(m.group(2));
      return '${m.group(1)}${unit.isEmpty ? '' : ' $unit'} pounds';
    },
  );
  s = s.replaceAllMapped(
    RegExp(r'€\s*([\d.,]+)\s*(billion|million|trillion|bn|m)?',
        caseSensitive: false),
    (m) {
      final unit = _unitWord(m.group(2));
      return '${m.group(1)}${unit.isEmpty ? '' : ' $unit'} euros';
    },
  );

  // 空白收敛；标点前不留空格。
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAllMapped(
    RegExp(r'\s+([,.;:!?])'),
    (match) => match.group(1)!,
  );
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

String _unitWord(String? unit) {
  switch (unit?.toLowerCase()) {
    case 'bn':
      return 'billion';
    case 'm':
      return 'million';
    case null:
    case '':
      return '';
    default:
      return unit ?? '';
  }
}
