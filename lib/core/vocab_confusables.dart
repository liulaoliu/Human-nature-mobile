import '../models/vocab.dart';

/// 易混项来源（唯一事实来源）。
///
/// 易混项现在有两个写入方：
///   - ai：AI 混淆项任务
///   - dict：离线词典按拼写近邻生成
///
/// 旧数据没有 `confusablesSource`，按「未记录」处理，不根据内容或时间反推。
/// 与 Web 版 `src/core/vocabConfusables.ts` 一一对应。
const List<VocabConfusableSource> vocabConfusableSources = [
  VocabConfusableSource.ai,
  VocabConfusableSource.dict,
];

/// 外部输入（备份 JSON / 本地存储）里的易混项来源先过这里。
VocabConfusableSource? parseVocabConfusableSource(Object? value) {
  if (value is! String) return null;
  for (final s in vocabConfusableSources) {
    if (s.name == value) return s;
  }
  return null;
}

/// 界面标签；旧数据返回空串（不显示来源）。
String confusableSourceLabel(VocabConfusableSource? source) => switch (source) {
      VocabConfusableSource.ai => 'AI',
      VocabConfusableSource.dict => '词典',
      null => '',
    };
