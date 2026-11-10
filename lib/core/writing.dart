/// 仿写训练的公共入口（re-export 伞）。
///
/// 原来 774 行全塞在这一个文件里（35 个顶层符号、13 处 import，全库扇入第一），
/// 已按职责拆开：
///   - `writing_types.dart`  数据结构（任务 / 评分 / 错因 / 建议 / 批改结果）
///   - `writing_prompt.dart` 出题与批改提示词的拼装
///   - `writing_parse.dart`  AI 输出 JSON 的严格解析
///   - `writing_record.dart` 记录（历史 / 去重 / 分页）
///   - `writing_json.dart`   读回落盘记录的宽松守卫（与解析层口径刻意不同）
///   - `writing_error_rules.dart` 错因闭集
///
/// 全库 20 处 `import 'writing.dart'` 一行都不用改：这里把上面全部 re-export 出去。
/// 对应 Web 版 `src/core/writing.ts`（689 行）。
library;

export 'writing_error_rules.dart'
    show WritingIssueType, WritingRule, writingRuleCatalog, writingTypeLabel;
export 'writing_json.dart';
export 'writing_record.dart';
export 'writing_types.dart';
export 'writing_prompt.dart';
export 'writing_parse.dart';
