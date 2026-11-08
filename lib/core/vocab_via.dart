import '../models/vocab.dart';

/// 本篇生词的细分来源（唯一事实来源）。
///
/// `origin` 仍保留粗粒度 auto/manual（老数据、打印口径都在用）；
/// `via` 只负责回答「这个词是怎么进来的」：
///   - ai：AI 自动标词直入
///   - dict：离线词典挑词 / 一键处理
///   - manual：手动点选、速读里手动加词
///   - language：AI 语言点自动收藏
///   - auto：听写等自动补词
///   - batch / legacy：旧数据没记具体来源，只知道自己不是逐个点的
///
/// 对应 Web 版 `src/core/vocabVia.ts`。
const List<VocabVia> vocabVias = <VocabVia>[
  VocabVia.ai,
  VocabVia.dict,
  VocabVia.manual,
  VocabVia.language,
  VocabVia.auto,
  VocabVia.batch,
  VocabVia.legacy,
];

/// 外部输入（本地存储 / 备份 JSON）里的来源字段先过这里。
VocabVia? parseVocabVia(Object? value) {
  if (value is! String) return null;
  for (final v in vocabVias) {
    if (v.name == value) return v;
  }
  return null;
}

/// 是不是合法来源。
bool isVocabVia(Object? value) => parseVocabVia(value) != null;
