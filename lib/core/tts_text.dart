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

  // 年代：`1950s` 会被整段吞掉（Kokoro 只听见一个 s）。根因是 phonemize 自带
  // 的年份规则用 `\b(1[89]\d{2}|20\d{2})\b`，而 `1950` 后面粘着字母 `s`，
  // 词边界不成立，那条规则就没命中，数字随后被丢弃。
  // 补一个撇号（`1950's`）让年份规则看得见数字，它自己就读成
  // 「nineteen fifties」了 —— 所以这里不自己实现数字拼写。
  // 注意顺序：必须在上面 20s → twenties 之后，那条更具体。
  s = s.replaceAllMapped(
    RegExp(r'\b(\d{2,4})s\b'),
    (m) => "${m.group(1)}'s",
  );

  // 千分位逗号：`30,000` 会被读成「thirty, zero」而不是「thirty thousand」。
  s = s.replaceAllMapped(
    RegExp(r'(\d),(\d{3})(?!\d)'),
    (m) => '${m.group(1)}${m.group(2)}',
  );

  // 单位缩写：音素化器只认单词，`2m` 会读成「two em」。这些词它拼不出来，
  // 只能由我们补。只收这套语料里真会出现的（按长度降序，先长后短）。
  s = s.replaceAllMapped(
    RegExp(r'\b(\d+(?:\.\d+)?)\s*(bn|tn|mn|bn|mw|gw|kw|km|kg|cm|mm|mph|ha|bbl|mi|ft|m)\b',
        caseSensitive: false),
    (m) {
      final unit = _measureWord(m.group(2)!);
      return unit == null ? m.group(0)! : '${m.group(1)} $unit';
    },
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

  // 字母和数字粘在一起时（`3D`、`5G`、`B2B`、`A4`、`4x4`），音素化器会把
  // 整个词丢给 G2P，数字部分直接消失（`3D` → d、`5G` → ɡ、`B2B` → bb）。
  // 在交界处拆开，各段就都能正常读。
  // 放在货币/缩写替换之后：那些规则产出的 `14.7 billion` 里没有粘连。
  // 序数后缀要放过：`1st` 拆成 `1 st` 会读成「one street」、`3rd` 读成
  // 「three road」。语料里序数有 1200 多处，拆了就全废，所以这里负向断言跳过。
  s = s.replaceAllMapped(
    RegExp(r'(\d)(?!(?:st|nd|rd|th)\b)([A-Za-z])'),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  s = s.replaceAllMapped(
    RegExp(r'([A-Za-z])(\d)'),
    (m) => '${m.group(1)} ${m.group(2)}',
  );

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

/// 计量单位缩写 → 音素化器读得出来的词。
///
/// 音素化器只查词典，`2m` 会读成「two em」、`254gw` 读成「two hundred fifty-four
/// gee double-you」。这些拼写它推不出来，只能由我们补。
/// 只收这套语料里真的会出现的单位；拿不准的返回 null，保持原样（宁可不改）。
String? _measureWord(String raw) {
  switch (raw.toLowerCase()) {
    case 'bn':
      return 'billion';
    case 'tn':
      return 'trillion';
    case 'mn':
      return 'million';
    case 'm':
      return 'million';
    case 'mw':
      return 'megawatts';
    case 'gw':
      return 'gigawatts';
    case 'kw':
      return 'kilowatts';
    case 'km':
      return 'kilometres';
    case 'kg':
      return 'kilograms';
    case 'cm':
      return 'centimetres';
    case 'mm':
      return 'millimetres';
    case 'mph':
      return 'miles per hour';
    case 'ha':
      return 'hectares';
    case 'bbl':
      return 'barrels';
    case 'mi':
      return 'miles';
    case 'ft':
      return 'feet';
    default:
      return null;
  }
}
