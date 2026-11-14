/// 「⚡ 一键处理」的五步清单与可用性判定。
///
/// 动作本身在 `services/dict_tools_service.dart`；这里只定义「有哪些步、
/// 每步依赖什么」，界面按清单画按钮、按 [dictStepEnabled] 决定禁用。
/// 顺序与 Web 版 `useDictTools.ts` 一致：
/// 挑词 → 补齐 → 补例句 → 校正原形 → 补混淆项。
library;

/// 一步「一键处理」。
class DictToolStep {
  const DictToolStep({
    required this.id,
    required this.label,
    required this.hint,
    required this.needsDictionary,
    required this.needsExamples,
    this.needsArticle = false,
  });

  /// 稳定 id（服务按它分发，别改成中文标签）。
  final String id;

  /// 按钮文案。
  final String label;

  /// 一句说明：这步做什么。
  final String hint;

  /// 要不要离线词典（ECDICT）。
  final bool needsDictionary;

  /// 要不要离线例句库（Tatoeba）。
  final bool needsExamples;

  /// 要不要「当前这一篇」（挑词按正文挑，没文章就没得挑）。
  final bool needsArticle;
}

/// 五步。顺序就是执行顺序，别乱。
///
/// 例句排在校正之前：校正后词形变了，例句表按旧词形对不上。
const List<DictToolStep> dictToolSteps = <DictToolStep>[
  DictToolStep(
    id: 'pick',
    label: '本篇挑词',
    hint: '按当前词汇标准，用离线词典从正文挑超纲词并收进本篇（不用 AI）',
    needsDictionary: true,
    needsExamples: false,
    needsArticle: true,
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
    hint: '给还没有例句的词从 Tatoeba 补真实例句（完全离线）',
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

/// 某一步现在能不能跑。
bool dictStepEnabled(
  DictToolStep step, {
  required bool dictionaryReady,
  required bool examplesReady,
  bool hasArticle = true,
}) {
  if (step.needsDictionary && !dictionaryReady) return false;
  if (step.needsExamples && !examplesReady) return false;
  if (step.needsArticle && !hasArticle) return false;
  return true;
}

/// 缺什么 —— 直接给用户看的那句话。
///
/// 都齐了返回空串（界面据此不显示提示行）。
String dictToolsBlocker({
  required bool dictionaryReady,
  required bool examplesReady,
}) {
  if (!dictionaryReady && !examplesReady) {
    return '离线词典和例句库都还没加载好 —— 稍等片刻再点。';
  }
  if (!dictionaryReady) {
    return '离线词典（ECDICT）还没加载好 —— 稍等片刻再点。';
  }
  if (!examplesReady) {
    return '离线例句库（Tatoeba）没加载 —— 补例句那步先跳过。';
  }
  return '';
}
