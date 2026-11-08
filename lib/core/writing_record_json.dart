/// 把存库 / 备份里的一条仿写记录还原成强类型 [WritingRecord]。
///
/// 为什么单独一个文件：记录里的 `task` 可能是普通仿写任务，也可能是产出训练
/// 的任务（多出 mode / topic / targets 那几列），所以这里必须同时认识两边 ——
/// 而 `production_task.dart` 又反过来依赖 `writing.dart`，塞进任何一侧都会成环。
library;

import 'production_task.dart' show ProductionTask, productionTaskFromJson;
import 'writing.dart' show ImitationTask;
import 'writing_json.dart';
import 'writing_record.dart';

/// 一条记录的 JSON → 强类型；认不出（缺 `at` / `articleId`）返回 null。
///
/// 与 [normalizeWritingRecord] 分工：那个管「字段白名单 + 补 recordKey」，
/// 这个管「JSON 形状 → 对象」。顺序是先本函数、再 normalize。
WritingRecord? writingRecordFromJson(Object? raw) {
  if (raw is! Map) return null;
  final at = raw['at'];
  final articleId = raw['articleId'];
  if (at is! String || at.isEmpty) return null;
  if (articleId is! String) return null;

  final ImitationTask? task = productionTaskFromJson(raw['task']) ??
      imitationTaskFromJson(raw['task']);
  final title = raw['articleTitle'];
  final model = raw['model'];
  final examId = raw['examId'];
  final sentenceId = raw['sentenceId'];
  final recordKey = raw['recordKey'];

  return normalizeWritingRecord(WritingRecord(
    at: at,
    articleId: articleId,
    articleTitle: title is String && title.isNotEmpty ? title : null,
    model: model is String ? model : '',
    text: raw['text'] is String ? raw['text'] as String : '',
    feedback: writingFeedbackFromJson(raw['feedback']),
    task: task,
    source: WritingSource.byId(raw['source']),
    examId: examId is String && examId.isNotEmpty ? examId : null,
    sentenceId: sentenceId is String && sentenceId.isNotEmpty ? sentenceId : null,
    recordKey: recordKey is String && recordKey.isNotEmpty ? recordKey : null,
  ));
}

/// 一批记录：坏的直接跳过（一条脏数据不该让整页历史读不出来）。
List<WritingRecord> writingRecordsFromJson(Object? raw) {
  if (raw is! List) return const <WritingRecord>[];
  final out = <WritingRecord>[];
  for (final r in raw) {
    final rec = writingRecordFromJson(r);
    if (rec != null) out.add(rec);
  }
  return out;
}

/// 一批记录 → JSON 列表（`LearningSection.writingHistory` 要的形状）。
List<Map<String, Object?>> writingRecordsToJson(List<WritingRecord> records) =>
    <Map<String, Object?>>[for (final r in records) r.toJson()];

/// 记录里的产出训练任务（没有就是 null）。
ProductionTask? productionTaskOfRecord(WritingRecord rec) {
  final task = rec.task;
  return task is ProductionTask ? task : null;
}
