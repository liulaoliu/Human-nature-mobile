/// 追加一条仿写 / 造句 / 产出训练记录，并按需给今天的「写」活动 +1。
///
/// 为什么单独一个服务：这段逻辑以前在三个 ViewModel 里各写了一遍
/// （`writing_view_model.dart` / `production_view_model.dart` /
/// `drill_sentence_view_model.dart`），差异只有「要不要记活动」一个条件，
/// 抄三遍迟早漏一处 —— 复习 `docs/TODO.md` 第三件时特意合一。
///
/// 一条硬语义：`writing_records` 表是**先清后插**，所以追加一条也必须
/// 把 `LearningSection.writingHistory` 整段重写，不能只 INSERT 一行。
/// 已存在的同题 / 同稿 / 同文字记录（`hasSameWritingAttempt`）不重复入库，
/// 也不重复记今日活动 —— 只有真追加（`appended`）才记账。
library;

import '../core/activity/activity.dart';
import '../core/learning.dart' show LearningSection;
import '../core/writing_record.dart';
import '../core/writing_record_json.dart' show writingRecordsToJson;
import '../data/repositories/learning_repository.dart';

/// 一次追加的结果。`history` 是落库成功后应该替换进 ViewModel 的完整历史。
class WritingAppendResult {
  const WritingAppendResult({
    required this.ok,
    required this.history,
    required this.appended,
    this.error,
  });

  final bool ok;

  /// 成功时是追加后的历史；失败时原样返回 [current]，调用方不用回滚。
  final List<WritingRecord> history;

  /// 这次是否真的多了一条（重复粘回为 false）。
  final bool appended;

  /// 失败原因（中文，可直接进 `_error`）；成功为 null。
  final String? error;
}

/// 追加 [record] 并落盘。
///
/// [countActivity] 由调用方决定「这条记录该不该算一次写作」：
///   - 普通仿写 / 拷打造句 = `true`；
///   - 产出训练 = `productionTaskOf(record)?.skipped != true`（跳过稿不记账）。
/// 服务内部再与 `appended` 取与，保证重复粘回不重复记账。
Future<WritingAppendResult> appendWritingRecord({
  required LearningRepository repo,
  required List<WritingRecord> current,
  required WritingRecord record,
  required bool countActivity,
}) async {
  final next = hasSameWritingAttempt(current, record)
      ? current
      : addWritingRecord(current, record);
  final appended = next.length != current.length;
  final counted = countActivity && appended;
  try {
    final data = await repo.load();
    data.writingHistory = writingRecordsToJson(next);
    if (counted) {
      data.activity =
          addActivity(data.activity, dayKeyLocal(), ActivityCat.write);
    }
    await repo.write(data, <LearningSection>[
      LearningSection.writingHistory,
      if (counted) LearningSection.activity,
    ]);
    return WritingAppendResult(ok: true, history: next, appended: appended);
  } catch (e) {
    return WritingAppendResult(
      ok: false,
      history: current,
      appended: false,
      error: '记录存不进去：$e',
    );
  }
}
