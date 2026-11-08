import '../text_norm.dart';

/// 词形与释义：归一化、lemma 还原、词性/释义清洗。
///
/// 纯函数，其他 vocab 子模块都从这里取「词形怎么算」的唯一口径。
/// 逐函数移植自 Web 版 `src/core/vocab/word.ts`（166 行）。

/// 不规则形 → 原形。规则表覆盖不到的常见词放这里。
const _irregular = <String, String>{
  'am': 'be', 'is': 'be', 'are': 'be', 'was': 'be', 'were': 'be', 'been': 'be',
  'being': 'be',
  'has': 'have', 'had': 'have', 'having': 'have',
  'does': 'do', 'did': 'do', 'done': 'do', 'doing': 'do',
  'goes': 'go', 'went': 'go', 'gone': 'go',
  'ran': 'run', 'runs': 'run',
  'children': 'child', 'men': 'man', 'women': 'woman', 'people': 'person',
  'mice': 'mouse', 'feet': 'foot', 'teeth': 'tooth', 'geese': 'goose',
  'better': 'good', 'best': 'good', 'worse': 'bad', 'worst': 'bad',
  'made': 'make', 'took': 'take', 'gave': 'give', 'came': 'come',
  'became': 'become',
  'saw': 'see', 'knew': 'know', 'said': 'say', 'found': 'find', 'told': 'tell',
  'thought': 'think', 'got': 'get', 'wrote': 'write', 'drove': 'drive',
  'using': 'use', 'uses': 'use', 'used': 'use',
};

final _curlyQuotes = RegExp('[\u2018\u2019\u02bc\u2032]');
final _dashes = RegExp('[\u2010-\u2015\u2212]');
final _nonWordChars = RegExp("[^A-Za-z'\\- ]+");
final _spaces = RegExp(r'\s+');

/// 把词形归一化成小写、统一撇号/连字符，去掉标点。
String normalizeWord(String raw) {
  return nfkc(raw)
      .replaceAll(_curlyQuotes, "'")
      .replaceAll(_dashes, '-')
      .replaceAll(_nonWordChars, ' ')
      .replaceAll(_spaces, ' ')
      .trim()
      .toLowerCase();
}

final _possessive = RegExp(r"'s$");
final _esEnding = RegExp(r'(s|x|z|ch|sh)es$');
final _iesEnding = RegExp(r'ies$');
final _plainS = RegExp(r'[^s]s$');
final _keepS = RegExp(r'(us|ss|is|os)$');
final _ingEnding = RegExp(r'ing$');
final _edEnding = RegExp(r'ed$');
final _doubledTail = RegExp(r'([bcdgklmnprtvz])\1$');
final _cvcTail = RegExp(r'[^aeiou][aeiou][^aeiouwxy]$');

/// 取 lemma（去重用的归一化形式）。
///
/// 这是启发式还原，不是完整词形还原：不规则形查表，其余走少量后缀规则
/// （复数、-ing、-ed）。覆盖不到的会偏，但同形/同词的常见变体能合并，
/// 后续可整体换成更完整的词形还原库。
String lemmaOf(String raw) {
  var s = normalizeWord(raw);
  if (s.isEmpty) return '';
  // 短语（含空格）不做词形还原，原样作为去重键
  if (s.contains(' ')) return s;
  final irregular = _irregular[s];
  if (irregular != null) return irregular;

  s = s.replaceFirst(_possessive, '');
  if (s.length <= 2) return s;

  if (_esEnding.hasMatch(s)) {
    s = s.substring(0, s.length - 2);
  } else if (_iesEnding.hasMatch(s) && s.length > 4) {
    s = '${s.substring(0, s.length - 3)}y';
  } else if (_plainS.hasMatch(s) && !_keepS.hasMatch(s)) {
    s = s.substring(0, s.length - 1);
  }

  if (_ingEnding.hasMatch(s) && s.length > 4) {
    s = _uninflect(s.substring(0, s.length - 3));
  } else if (_edEnding.hasMatch(s) && s.length > 3) {
    s = _uninflect(s.substring(0, s.length - 2));
  }
  return s;
}

/// 双写尾辅音去一个（running → runn → run）；辅-元-辅结尾补 e（watched → watch → watche）。
String _uninflect(String base) {
  if (_doubledTail.hasMatch(base)) return base.substring(0, base.length - 1);
  if (_cvcTail.hasMatch(base)) return '${base}e';
  return base;
}

/// 屈折后缀：加上它只是同一个词的变形，不是另一个词。
const _inflection = <String>{'s', 'es', 'd', 'ed', 'ing', 'n', 'en'};

/// AI 说「A 的原形是 B」时，能不能真把词条从 A 改名成 B。
///
/// 2026-10-22 的血案：`-ing/-ed 辨析` 拿 AI 给的原形直接改词条的 word，
/// 而 AI 会把**加前缀派生出来的另一个词**当成词形变化：
/// `unchallenged → challenge`、`unarticulated → articulate`、`inarticulate → articulate`。
/// 改名只动 word/lemma/id，**释义、用法、例句都不动**，于是
/// 「challenge」这张卡上挂着 unchallenged 的词典释义（n./adj. 张冠李戴）。
///
/// 所以这里只认**屈折**，不认派生：
///   - 不规则表（went→go、better→good）；
///   - 在词干后面接屈折后缀（runs→run、watched→watch、swelling→swell）；
///   - 双写尾辅音（running→run）、去 e 加 -ing/-ed（expunging→expunge）；
///   - y→ies（companies→company）、-ses→-sis（analyses→analysis）。
/// 加/去任何**派生**词缀一律拒绝：un-/in-/im-/ir-/il-/dis-/non-/anti-/mis-（前缀），
/// -ly/-ness/-less/-ful/-ment/-tion/-able/-ity/-ism/-ist/-er/-or/-al/-ic/-ous（后缀）。
/// 拒绝的代价只是「词形没被规整」，误改的代价是整张卡的释义张冠李戴——宁严不宽。
bool canRewriteTo(String from, String to) {
  final f = normalizeWord(from);
  final t = normalizeWord(to);
  if (f.isEmpty || t.isEmpty) return false;
  if (f == t) return true;
  if (_irregular[f] == t) return true;
  // 只处理单词：短语（含空格）不做改名判断，交给原来的「同形才改」
  if (f.contains(' ') || t.contains(' ')) return false;

  // 词干 + 屈折后缀（含词尾变化）
  if (f.startsWith(t)) {
    final rest = f.substring(t.length);
    if (_inflection.contains(rest)) return true;
    // 双写尾辅音：run → running / plan → planned（词干末尾那个字母再写一遍）
    final tail = t.substring(t.length - 1);
    if (rest == '${tail}ing' || rest == '${tail}ed') return true;
  }
  // 去 e 再加 -ing/-ed：expunge → expunging / expunged
  if (t.endsWith('e') &&
      (f == '${t.substring(0, t.length - 1)}ing' ||
          f == '${t.substring(0, t.length - 1)}ed')) {
    return true;
  }
  // 辅音 + y → ies：company → companies
  if (t.endsWith('y') && f == '${t.substring(0, t.length - 1)}ies') return true;
  // -sis → -ses：analysis → analyses
  if (t.endsWith('sis') && f == '${t.substring(0, t.length - 2)}es') return true;
  return false;
}

/// 词性全称 → 缩写（离线词典/AI 有时给 "noun" 全称）。
const _posAbbr = <String, String>{
  'noun': 'n.',
  'verb': 'v.',
  'adjective': 'adj.',
  'adverb': 'adv.',
  'preposition': 'prep.',
  'conjunction': 'conj.',
  'pronoun': 'pron.',
  'numeral': 'num.',
  'article': 'art.',
  'interjection': 'interj.',
};

final _trailingDots = RegExp(r'\.+$');

/// 规范化词性显示：「noun」→「n.」。
String normalizePos(String? pos) {
  final p = (pos ?? '').trim();
  if (p.isEmpty) return '';
  final key = p.toLowerCase().replaceAll(_trailingDots, '').trim();
  return _posAbbr[key] ?? p;
}

final _backslashes = RegExp(r'\\+');
final _leadingSeparators = RegExp(r'^[\s;,.，、]+');
final _trailingSeparators = RegExp(r'[\s;,，、]+$');

/// 清洗释义/英英：数据里常见行尾转义残留的「\」（ECDICT/AI 都有），
/// 还有多余空白与首尾分隔符。中文英文都过一遍。
String cleanGloss(String? s) {
  return (s ?? '')
      .replaceAll(_backslashes, ' ')
      .replaceAll(_spaces, ' ')
      .replaceAll(_leadingSeparators, '')
      .replaceAll(_trailingSeparators, '')
      .trim();
}

/// 若释义开头与词性重复（词性 n. 且释义以「n. 」或「noun 」开头），去掉重复那段。
String stripLeadingPos(String? pos, String gloss) {
  final abbr = normalizePos(pos);
  if (abbr.isEmpty) return gloss;
  final tokens = <String>[
    if (abbr.isNotEmpty) abbr,
    if ((pos ?? '').trim().isNotEmpty) (pos ?? '').trim(),
  ];
  var out = gloss;
  for (final t in tokens) {
    final esc = RegExp.escape(t);
    out = out.replaceFirst(RegExp('^\\s*$esc\\.?\\s*', caseSensitive: false), '');
  }
  return out.trim();
}

/// 词条的展示用中释义（清洗 + 去重复词性）。
String displayMeaning({String? partOfSpeech, String? meaning}) {
  return stripLeadingPos(partOfSpeech, cleanGloss(meaning));
}
