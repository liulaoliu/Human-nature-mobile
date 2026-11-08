/// 精读 AI 流程的公共底座：任务类型、各表结构的行类型，以及提示词与解析共用的字符串工具。
///
/// 为什么单独一层：`build*`（拼提示词）与 `parse*`（解析粘回结果）是两件事，
/// 但都要用 `HEADER`、引号包裹、列表拆分；混在一个文件里会互相牵制，
/// 又不该用「解析依赖提示词」这种假依赖把它们串起来。
/// 这里只放两边都要用、且不依赖业务逻辑的东西。
///
/// 行类型刻意不重复定义：`PosRow` 在 `vocab/analysis.dart`、`LemmaPair` 在
/// `ecdict.dart`、`ConfusableResult` 在 `vocab/analysis.dart` —— 那些是**写回词库**
/// 时用的类型，解析层直接产出同一份，省掉一层来回转换。
library;

/// AI 任务类型。
enum AnalysisTask {
  translate,
  lookup,
  grammar,
  collocations,
  extractVocab,
  summarize,
  autoVocab,
}

/// 拼提示词的入参。
class BuildPromptInput {
  const BuildPromptInput({
    required this.task,
    required this.text,
    this.words = const [],
  });

  final AnalysisTask task;

  /// 选中的原文（句子 / 段落），作为上下文或翻译对象。
  final String text;

  /// lookup 任务要查的词；空就用 [text] 自己。
  final List<String> words;
}

/// 提示词里包裹原文 / 单词列表的三引号围栏（与正文隔开，避免 AI 把正文当指令）。
const String fence = '"""';

/// 用围栏包住一段原文，前后各留一个换行。
String quoted(String text) => '$fence\n${text.trim()}\n$fence';

/// 所有提示词共用的系统口吻。
const String header = '你是英语精读助手。只输出结果，不要解释。';

/// 查词表格的字段顺序，解析时按这个顺序取。
const List<String> lookupFields = <String>[
  'word',
  'phonetic',
  'partOfSpeech',
  'meaning',
  'usage',
  'example',
];

/// 把一行里用各种分隔符隔开的条目拆出来（去项目符号 / 编号，丢空项）。
List<String> splitList(String raw) => raw
    .split(RegExp(r'[\n;；、]+'))
    .map((s) => s.replaceFirst(RegExp(r'^[-*•\d.、\s]+'), '').trim())
    .where((s) => s.isNotEmpty)
    .toList(growable: false);

/// 清洗 AI 给的例句：去编号 / 项目符号、去包裹引号、压缩空白。
///
/// 句子被 AI 加序号或引号很常见，不清会污染卡片、也影响挖空。
String cleanExampleText(String raw) => raw
    .replaceFirst(RegExp(r'^\s*(?:[-*•·]|\d+[.)、])\s*'), '')
    .replaceAll(RegExp('^["\'\u201c\u201d\u2018\u2019]+|["\'\u201c\u201d\u2018\u2019]+\$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// 词组 / 习语表的一行。
class PhraseRow {
  const PhraseRow({
    required this.word,
    required this.phrases,
    required this.idioms,
  });

  final String word;
  final List<String> phrases;
  final List<String> idioms;
}

/// 用法示例表的一行。
class ExampleRow {
  const ExampleRow({required this.word, required this.examples});

  final String word;
  final List<({String text, String? translation})> examples;
}

/// 「id | 译文」逐句翻译表的一行。
class TranslationRow {
  const TranslationRow({required this.sentenceId, required this.translation});

  final String sentenceId;
  final String translation;
}

/// 语法标记表的行类型（与 `vocab/merge.dart` 的 `applyGrammarMarks` 同形）。
typedef GrammarMarkRow = ({String word, List<String> marks});
