/// 一轮背完之后的「接下来」：只算该给用户什么建议，不碰界面。
///
/// 口径（用户 m25031 确认）：
///   - 本篇还有生词 → 继续学（**不自动跳**，跳走会把结算数字盖掉）；
///   - 本篇学完了、但有到期的 → 给「去复习」；
///   - 都没有 → 老实说没有，指一条能收词的路。
///
/// 放 core 是因为它只有判断没有状态，界面里写一遍、测试里再验一遍会分叉。
library;

import 'study_pool.dart';

/// 结算页该建议的下一步。
class RoundNextStep {
  const RoundNextStep({
    required this.hint,
    this.entry,
    this.count = 0,
  });

  /// 给用户看的一句话（为什么是这个建议）。
  final String hint;

  /// 建议进哪个入口；null = 没有可进的了。
  final StudyEntry? entry;

  /// 那个入口里还有多少。
  final int count;

  /// 按钮文案；[entry] 为 null 时是空串（调用方不该画按钮）。
  String get label => switch (entry) {
        StudyEntry.learn => '继续学这 $count 个',
        StudyEntry.review => '去复习这 $count 个',
        StudyEntry.recall => '去回顾这 $count 个',
        null => '',
      };
}

/// 算下一步建议。
///
/// [articleId] 为 null 表示还没打开过文章（这时「本篇」无从谈起）。
RoundNextStep roundNextStep({
  required int learn,
  required int review,
  required String? articleId,
}) {
  if (learn > 0) {
    return RoundNextStep(
      hint: '还有 $learn 个生词没背过，接着学一轮最顺。',
      entry: StudyEntry.learn,
      count: learn,
    );
  }
  if (review > 0) {
    return RoundNextStep(
      hint: '这一篇的生词学完了；今天有 $review 个到期，趁热复习一遍记得最牢。',
      entry: StudyEntry.review,
      count: review,
    );
  }
  return RoundNextStep(
    hint: articleId == null
        ? '全库没有待学的新词，也没有到期的。去「精读」收几个词再来。'
        : '这一篇学完了，也没有到期的。换一篇，或者去「精读」再收几个词。',
  );
}
