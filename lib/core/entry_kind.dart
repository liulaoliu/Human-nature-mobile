/// 词条「类型」这一层的小工具。
///
/// 为什么单独一个文件：`kind` 是**跨领域**的概念——词库（单词）、语言点（词组/习语/用法）、
/// 打印导出、AI 任务、背单词范围都要问「这条是哪一类」。放在 vocab 里会让所有想用它的
/// 模块都被迫依赖整个词库逻辑。这里零依赖，谁都能引。
///
/// 对应旧项目 `src/core/entryKind.ts`，语义逐条对齐。
library;

/// 词条类型。
enum VocabKind { word, phrase, idiom, usage }

/// 类型的中文名（列表标签、打印、Anki 标签用）。
const Map<VocabKind, String> kindLabel = <VocabKind, String>{
  VocabKind.word: '单词',
  VocabKind.phrase: '词组',
  VocabKind.idiom: '习语',
  VocabKind.usage: '用法',
};

/// 固定顺序（筛选项、打印分组按这个来）。
const List<VocabKind> kindOrder = <VocabKind>[
  VocabKind.word,
  VocabKind.phrase,
  VocabKind.idiom,
  VocabKind.usage,
];

/// 含中日韩文字（用法笔记基本都是中文说明）。
final RegExp _cjk = RegExp(r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]');

/// 单个英文单词（可带连字符 / 撇号，不含空格与中文）。
final RegExp _singleWord = RegExp(r"^[A-Za-z][A-Za-z'’\-]*$");

/// 词条正文本身就是一个英文单词（可带连字符 / 撇号，不含空格与中文）。
///
/// 为什么单独拎出来：AI 有时把单词写进「词组 / 用法」栏，历史上也留下过
/// 「单词词条被标成 usage」的脏数据。词形是单个英文单词时，类型只能是单词。
bool isSingleEnglishWord(String? text) {
  final w = (text ?? '').trim();
  if (w.isEmpty || _cjk.hasMatch(w)) return false;
  return _singleWord.hasMatch(w);
}

/// 词条类型（老数据没有 `kind` → 普通单词）。
///
/// 同时兜住「类型与词形矛盾」的存量数据：`word` 是单个英文单词却标成
/// `phrase / idiom / usage` 时按单词算。否则这些词会从「本篇生词」里消失、
/// 一键处理反复把它们塞回待选。
VocabKind kindOf({VocabKind? kind, String? word}) {
  final k = kind ?? VocabKind.word;
  if (k == VocabKind.word) return VocabKind.word;
  return isSingleEnglishWord(word) ? VocabKind.word : k;
}

/// 是不是「单词」——词组 / 习语 / 用法笔记都不是（AI 的词级任务不该去分析它们）。
///
/// 传 `word` 是为了让词形兜底生效（单个英文单词被标成 usage 时仍算单词）。
bool isWordEntry({VocabKind? kind, String? word}) =>
    kindOf(kind: kind, word: word) == VocabKind.word;

/// 是不是「语言点收藏」（词组 / 习语 / 用法笔记）。
bool isLangPoint({VocabKind? kind, String? word}) =>
    kindOf(kind: kind, word: word) != VocabKind.word;

/// 能不能拿来背 / 考。两条硬门槛：
///
/// - 用法笔记（中文说明）只用来收藏与打印，不进卡片；
/// - 没有释义的卡是「废卡」——没中文意思，选义题出不了、卡片上只能显示「无释义」，
///   不该混进背词 / 考试池，先去补释义。
bool isStudyable({VocabKind? kind, String? word, String? meaning}) {
  if (kindOf(kind: kind, word: word) == VocabKind.usage) return false;
  return (meaning ?? '').isNotEmpty;
}

/// 背词牌组：普通单词 / 搭配（词组·习语）。
enum StudyDeck { word, collocation }

/// 这条属于哪个背词牌组。
///
/// - [StudyDeck.word]：只背普通单词（词组/习语抽到「背搭配」里）
/// - [StudyDeck.collocation]：只背词组 / 习语（用法笔记两边都不进）
bool inStudyDeck({
  VocabKind? kind,
  String? word,
  String? meaning,
  required StudyDeck deck,
}) {
  if (!isStudyable(kind: kind, word: word, meaning: meaning)) return false;
  final k = kindOf(kind: kind, word: word);
  return deck == StudyDeck.collocation
      ? k == VocabKind.phrase || k == VocabKind.idiom
      : k == VocabKind.word;
}
