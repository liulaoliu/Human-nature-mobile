/// 「⚡ 一键处理」的五步清单 —— **只定义步骤，不实现动作**。
///
/// 用户 m24894 明确说过：手机端数据本来就从 Web 拿，挑词 / 补齐 / 例句 /
/// 校正 / 混淆这几个动作可以先不做，但**框架要在**，以后想补时知道往哪补。
///
/// 所以这里只有「有哪些步、每步要什么条件、要调哪个现成函数」，
/// 界面按这份清单画一排**禁用**的按钮，并在说明里写清缺什么。
/// 真接的时候：给 [DictToolStep.id] 挂上对应 `core/` 函数即可，清单本身不用改。
library;

/// 一步「一键处理」。
class DictToolStep {
  const DictToolStep({
    required this.id,
    required this.label,
    required this.hint,
    required this.needsDictionary,
    required this.needsExamples,
  });

  /// 稳定 id（以后接动作时按它分发，别改成中文标签）。
  final String id;

  /// 按钮文案。
  final String label;

  /// 一句说明：这步做什么、靠哪个函数。
  final String hint;

  /// 要不要离线词典（ECDICT）。
  final bool needsDictionary;

  /// 要不要离线例句库（Tatoeba）。
  final bool needsExamples;
}

/// 五步。顺序就是 Web 版「一键处理」的执行顺序，别乱。
///
/// 依赖的函数（现在都只在 core 里躺着，没有调用方 —— 这正是「框架」的含义）：
/// - `pick` → `analyzer_prompt.dart:162 buildAutoVocabPrompt` /
///   `ecdict.dart:371 pickAboveLevelWords`（本地挑词那条路）
/// - `enrich` → `analyzer_prompt.dart:51 buildBatchLookupPrompt` +
///   `analyzer_parse.dart:81 parseLookupTable` + `vocab/analysis.dart applyWordAnalysis`
/// - `examples` → `analyzer_prompt.dart:84 buildExamplePrompt`
/// - `lemma` → `analyzer_prompt.dart:210 buildLemmaPrompt` + `vocab/word.dart lemmaOf`
/// - `confuse` → `analyzer_prompt.dart:178 buildConfusablePrompt`
const List<DictToolStep> dictToolSteps = <DictToolStep>[
  DictToolStep(
    id: 'pick',
    label: '本篇挑词',
    hint: '按当前词汇标准，用离线词典从正文挑超纲词（不用 AI）',
    needsDictionary: true,
    needsExamples: false,
  ),
  DictToolStep(
    id: 'enrich',
    label: '补齐生词本',
    hint: '给生词补齐音标 / 词性 / 中英文释义（词典里有的才补）',
    needsDictionary: true,
    needsExamples: false,
  ),
  DictToolStep(
    id: 'examples',
    label: '补离线例句',
    hint: '给还没有例句的词批量补真实例句',
    needsDictionary: false,
    needsExamples: true,
  ),
  DictToolStep(
    id: 'lemma',
    label: '校正原形',
    hint: '把 running / went 这类还原成原形并去重',
    needsDictionary: true,
    needsExamples: false,
  ),
  DictToolStep(
    id: 'confuse',
    label: '补混淆项',
    hint: '给缺干扰项的词生成拼写形近、含义不同的选项',
    needsDictionary: true,
    needsExamples: false,
  ),
];

/// 每一步现在能不能跑。
///
/// **当前恒为 false**：动作没实现，光有数据也不算能跑。
/// 以后接上某一步，就把它从「恒 false」改成真判定 —— 这样界面不用改。
bool dictStepEnabled(
  DictToolStep step, {
  required bool dictionaryReady,
  required bool examplesReady,
}) {
  if (step.needsDictionary && !dictionaryReady) return false;
  if (step.needsExamples && !examplesReady) return false;
  return false; // 动作还没实现。
}

/// 缺什么 —— 直接给用户看的那句话（都齐了就说「还没做」）。
String dictToolsBlocker({
  required bool dictionaryReady,
  required bool examplesReady,
}) {
  if (!dictionaryReady && !examplesReady) {
    return '离线词典和例句库都还没接进来，而且这几步的动作也还没实现 —— 先在电脑端跑，手机上以后再补。';
  }
  if (!dictionaryReady) {
    return '离线词典（ECDICT）没加载，而且这几步的动作还没实现。';
  }
  if (!examplesReady) {
    return '离线例句库（Tatoeba）没加载，而且这几步的动作还没实现。';
  }
  return '数据和函数都齐了，但这几步的动作还没实现 —— 这是留好的框架。';
}
