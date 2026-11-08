/// 仿写批改的**错因标签体系**（纯数据 + 纯函数）。
///
/// 为什么要闭集：全库趋势要回答「我老在句首大写上错」，就不能让 AI 每次
/// 自由写 `Capitalization` / `capital` / `首字母` 三种标签。`rule` 是跨句、
/// 跨篇归一的键；`key` 才是这一条错因（一张复习卡）的具体身份。
///
/// 对应 Web 版 `src/core/writingErrorRules.ts`（309 行）。不 import 任何运行时模块。
library;

/// 错因大类（界面按它分组、上色）。
enum WritingIssueType {
  spelling,
  capitalization,
  punctuation,
  article,
  number,
  collocation,
  chunk,
  grammar,
  naturalness,
  meaning,
  other,
}

const Map<WritingIssueType, String> _typeLabel = <WritingIssueType, String>{
  WritingIssueType.spelling: '拼写',
  WritingIssueType.capitalization: '大小写',
  WritingIssueType.punctuation: '标点 / 空格',
  WritingIssueType.article: '冠词',
  WritingIssueType.number: '单复数',
  WritingIssueType.collocation: '搭配',
  WritingIssueType.chunk: '词块',
  WritingIssueType.grammar: '语法 / 结构',
  WritingIssueType.naturalness: '中式 / 自然度',
  WritingIssueType.meaning: '语义 / 逻辑',
  WritingIssueType.other: '其他',
};

/// 大类的中文名。
String writingTypeLabel(WritingIssueType type) => _typeLabel[type] ?? '其他';

/// 错因闭集（顺序即提示词里的展示顺序）。
enum WritingRule {
  sentenceInitialCapital('sentence-initial-capital', WritingIssueType.capitalization, '句首首字母未大写'),
  brandNameCapitalization('brand-name-capitalization', WritingIssueType.capitalization, '品牌 / 专有名词大小写'),
  capitalizationOther('capitalization-other', WritingIssueType.capitalization, '其他大小写问题'),
  wordSpelling('word-spelling', WritingIssueType.spelling, '单词拼写'),
  commaFollowedBySpace('comma-followed-by-space', WritingIssueType.punctuation, '逗号后缺空格'),
  spaceBeforePunctuation('space-before-punctuation', WritingIssueType.punctuation, '标点前多空格'),
  commaSplice('comma-splice', WritingIssueType.punctuation, '逗号粘连（两个独立分句）'),
  numberUnitSpacing('number-unit-spacing', WritingIssueType.punctuation, '数字与单位之间缺空格'),
  apostropheDecade('apostrophe-decade', WritingIssueType.punctuation, '年代 / 所有格撇号写法'),
  punctuationOther('punctuation-other', WritingIssueType.punctuation, '其他标点问题'),
  articleMissing('article-missing', WritingIssueType.article, '缺冠词'),
  articleWrong('article-wrong', WritingIssueType.article, '冠词用错'),
  pluralForm('plural-form', WritingIssueType.number, '单复数形式'),
  countability('countability', WritingIssueType.number, '可数 / 不可数'),
  prepositionCollocation('preposition-collocation', WritingIssueType.collocation, '介词搭配'),
  verbPattern('verb-pattern', WritingIssueType.collocation, '动词句型（to do / doing）'),
  verbObjectCollocation('verb-object-collocation', WritingIssueType.collocation, '动宾搭配'),
  collocationOther('collocation-other', WritingIssueType.collocation, '其他固定搭配'),
  chunkMissing('chunk-missing', WritingIssueType.chunk, '规定词块没用上'),
  chunkForm('chunk-form', WritingIssueType.chunk, '词块形式不完整'),
  chunkSense('chunk-sense', WritingIssueType.chunk, '词块义项 / 及物性用错'),
  incompleteClause('incomplete-clause', WritingIssueType.grammar, '句子不完整 / 从句结构'),
  missingFormObject('missing-form-object', WritingIssueType.grammar, '缺形式宾语 / 必要成分'),
  tenseChoice('tense-choice', WritingIssueType.grammar, '时态选择'),
  subjectVerbAgreement('subject-verb-agreement', WritingIssueType.grammar, '主谓一致'),
  wordOrder('word-order', WritingIssueType.grammar, '语序'),
  grammarOther('grammar-other', WritingIssueType.grammar, '其他语法问题'),
  literalTranslation('literal-translation', WritingIssueType.naturalness, '中式直译'),
  unnaturalSubject('unnatural-subject', WritingIssueType.naturalness, '主语 / 搭配不自然'),
  unclearReference('unclear-reference', WritingIssueType.naturalness, '指代不清'),
  styleImprovement('style-improvement', WritingIssueType.naturalness, '更地道的表达（提升项）'),
  naturalnessOther('naturalness-other', WritingIssueType.naturalness, '其他自然度问题'),
  promptMismatch('prompt-mismatch', WritingIssueType.meaning, '偏离中文提示 / 场景'),
  logicContradiction('logic-contradiction', WritingIssueType.meaning, '语义矛盾 / 逻辑不通'),
  meaningOther('meaning-other', WritingIssueType.meaning, '其他语义问题'),
  other('other', WritingIssueType.other, '其他');

  const WritingRule(this.id, this.type, this.label);

  /// 存库 / 提示词里用的稳定 id（与 Web 版一致）。
  final String id;

  /// 大类只从 rule 推导，AI 输出的 type 不单独采信。
  final WritingIssueType type;

  /// 中文名。
  final String label;

  /// 按 id 反查；认不出返回 null。
  static WritingRule? byId(Object? raw) {
    if (raw is! String) return null;
    for (final rule in WritingRule.values) {
      if (rule.id == raw) return rule;
    }
    return null;
  }
}

/// 需要「规则级」复习卡（答案不依赖具体句子）的机械规则。
const Set<WritingRule> _mechanicalRules = <WritingRule>{
  WritingRule.sentenceInitialCapital,
  WritingRule.brandNameCapitalization,
  WritingRule.capitalizationOther,
  WritingRule.commaFollowedBySpace,
  WritingRule.spaceBeforePunctuation,
  WritingRule.commaSplice,
  WritingRule.numberUnitSpacing,
  WritingRule.apostropheDecade,
  WritingRule.punctuationOther,
  WritingRule.articleMissing,
  WritingRule.articleWrong,
  WritingRule.pluralForm,
  WritingRule.countability,
  WritingRule.prepositionCollocation,
  WritingRule.verbPattern,
  WritingRule.incompleteClause,
  WritingRule.missingFormObject,
  WritingRule.tenseChoice,
  WritingRule.subjectVerbAgreement,
  WritingRule.wordOrder,
  WritingRule.grammarOther,
};

/// 是不是闭集里的 rule id。
bool isWritingRule(Object? value) => WritingRule.byId(value) != null;

/// rule → 大类。
WritingIssueType writingTypeOf(WritingRule rule) => rule.type;

/// 稳定 slug：只允许小写字母 / 数字 / 连字符，供 `key` 使用。
String writingKeySlug(String text) {
  var s = text
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > 36) s = s.substring(0, 36);
  s = s.replaceAll(RegExp(r'-+$'), '');
  return s.isEmpty ? 'x' : s;
}

/// key 的合法形状：`chunk-an-end-to` / `spelling-bureaucracy`。
bool isWritingIssueKey(Object? value) =>
    value is String && RegExp(r'^[a-z][a-z0-9-]{2,40}$').hasMatch(value);

/// 给一条错因生成 `key`：
/// - 机械规则（大写 / 标点 / 冠词 / 语法）用规则级 key，避免同一规则堆几十张卡；
/// - 词汇 / 词块 / 搭配 / 语义用「类型 + 改正片段」，保证每个词块有自己的卡。
String writingKeyFor(
  WritingRule rule,
  String original,
  String suggestion,
) {
  if (_mechanicalRules.contains(rule)) return rule.id;
  final body = writingKeySlug(suggestion.isNotEmpty ? suggestion : original);
  return '${writingTypeOf(rule).name}-$body';
}

/// 旧版批改（或 AI 漏字段）里的那三个字段。
class LegacyIssueLike {
  const LegacyIssueLike({this.original = '', this.suggestion = '', this.reason = ''});

  final String original;
  final String suggestion;
  final String reason;
}

/// 一条错因归好类之后的样子。
class ClassifiedIssue {
  const ClassifiedIssue({
    required this.type,
    required this.rule,
    required this.key,
    required this.severity,
  });

  final WritingIssueType type;
  final WritingRule rule;
  final String key;

  /// `must-fix`（硬错）或 `improvement`（提升项）。
  final String severity;

  bool get isImprovement => severity == 'improvement';

  @override
  String toString() => 'ClassifiedIssue(${rule.id}, $key, $severity)';
}

final RegExp _hardWords = RegExp(
  '错误|不成立|拼写|缺少|缺冠词|未使用|没有用上|未出现|语法|不成句|矛盾|必须|应改为|不能接|不及物|单复数',
);

final RegExp _softWords = RegExp(
  '更地道|更自然|更具体|更准确|更顺|更清晰|更贴合|更正式|可考虑|建议用|建议改为|略显|偏正式|偏中式|润色|提升|不够自然|可改为|可换成|可以更',
);

bool _looksLikeImprovement(String reason) {
  if (reason.isEmpty) return false;
  if (_hardWords.hasMatch(reason)) return false;
  return _softWords.hasMatch(reason);
}

WritingRule _ruleFromText(String original, String suggestion, String reason) {
  final s = '$original $suggestion $reason'.toLowerCase();
  if (RegExp('拼写|错拼|少了一个字母|漏写|多写|不是英语单词|不成立.*单词').hasMatch(s)) {
    return WritingRule.wordSpelling;
  }
  if (RegExp('首字母|大写|大小写').hasMatch(s)) {
    return RegExp('品牌|iphone|ipad|apple|专有名词').hasMatch(s)
        ? WritingRule.brandNameCapitalization
        : WritingRule.sentenceInitialCapital;
  }
  if (RegExp('逗号.*空格|空格.*逗号|逗号后|逗号前|逗号粘连|独立分句之间').hasMatch(s)) {
    if (RegExp('独立分句|粘连').hasMatch(s)) return WritingRule.commaSplice;
    if (RegExp('前.*空格|空格.*前').hasMatch(s)) return WritingRule.spaceBeforePunctuation;
    return WritingRule.commaFollowedBySpace;
  }
  if (RegExp("撇号|年代|90's|1990s").hasMatch(s)) return WritingRule.apostropheDecade;
  if (RegExp('数字.*单位|单位.*(空格|缺)|数字.*空格|单位前|单位之间').hasMatch(s)) {
    return WritingRule.numberUnitSpacing;
  }
  if (RegExp('标点|引号').hasMatch(s)) return WritingRule.punctuationOther;
  if (RegExp('冠词|定冠词|不定冠词').hasMatch(s)) {
    return RegExp('缺|需要|漏').hasMatch(s) ? WritingRule.articleMissing : WritingRule.articleWrong;
  }
  if (RegExp('单复数|复数形式').hasMatch(s)) return WritingRule.pluralForm;
  if (RegExp('不可数|可数').hasMatch(s)) return WritingRule.countability;
  if (RegExp('词块|必须使用|未使用|没有用上|未出现|规定词块').hasMatch(s)) {
    if (RegExp('未使用|没有用上|未出现|没用上').hasMatch(s)) return WritingRule.chunkMissing;
    return RegExp('义项|及物|不及物|语义').hasMatch(s)
        ? WritingRule.chunkSense
        : WritingRule.chunkForm;
  }
  if (RegExp('中式|直译').hasMatch(s)) return WritingRule.literalTranslation;
  if (RegExp('介词').hasMatch(s)) return WritingRule.prepositionCollocation;
  if (RegExp('不定式|to do|doing|动词句型|不能接').hasMatch(s)) return WritingRule.verbPattern;
  if (RegExp('搭配').hasMatch(s)) return WritingRule.verbObjectCollocation;
  if (RegExp('不成句|缺主句|句子不完整|从句结构').hasMatch(s)) {
    return WritingRule.incompleteClause;
  }
  if (RegExp('形式宾语|缺.*it|必要成分').hasMatch(s)) return WritingRule.missingFormObject;
  if (RegExp('时态').hasMatch(s)) return WritingRule.tenseChoice;
  if (RegExp('主谓一致').hasMatch(s)) return WritingRule.subjectVerbAgreement;
  if (RegExp('语序').hasMatch(s)) return WritingRule.wordOrder;
  if (RegExp('语法|句子结构').hasMatch(s)) return WritingRule.grammarOther;
  if (RegExp('主语').hasMatch(s)) return WritingRule.unnaturalSubject;
  if (RegExp('指代').hasMatch(s)) return WritingRule.unclearReference;
  if (RegExp('偏离|中文提示|场景|语境').hasMatch(s)) return WritingRule.promptMismatch;
  if (RegExp('逻辑|矛盾').hasMatch(s)) return WritingRule.logicContradiction;
  if (RegExp('不自然|生硬|荒诞|空泛|重复').hasMatch(s)) return WritingRule.naturalnessOther;
  if (RegExp('语义|意思').hasMatch(s)) return WritingRule.meaningOther;
  return WritingRule.other;
}

/// 旧批改 / AI 漏字段时的启发式兜底；新数据应直接带 rule + key。
ClassifiedIssue classifyLegacyIssue(LegacyIssueLike issue) {
  final original = issue.original.trim();
  final suggestion = issue.suggestion.trim();
  final reason = issue.reason.trim();
  final rule = _ruleFromText(original, suggestion, reason);
  final severity = rule == WritingRule.styleImprovement ||
          (!_mechanicalRules.contains(rule) && _looksLikeImprovement(reason))
      ? 'improvement'
      : 'must-fix';
  return ClassifiedIssue(
    type: writingTypeOf(rule),
    rule: rule,
    key: writingKeyFor(rule, original, suggestion),
    severity: severity,
  );
}

/// 给提示词用的紧凑清单（`- rule: 中文说明`）。
String writingRuleCatalog() =>
    WritingRule.values.map((rule) => '- ${rule.id}: ${rule.label}').join('\n');
