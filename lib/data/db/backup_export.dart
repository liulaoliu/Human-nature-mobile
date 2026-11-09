/// 备份的**导出**侧：把整库打成一份能换电脑用的 JSON。
///
/// 对应 Web 版 `src/reader/hooks/exportFiles.ts` 的 `exportAll`（其余导出型功能
/// 用户已明确不要，见 `docs/PLAN.md` 的 P6「打印 / 导出」条目）。
///
/// 与导入侧（`backup_parse.dart`）是一对：这里写什么键，那边就读什么键，
/// 键名必须与 Web 版一致 —— 用户在浏览器导出的备份，App 得能直接吃，反之亦然。
///
/// 落 `data/db/` 而不是 `core/`：它要复用数据层对「学习记录 → JSON」的唯一口径
/// （`learningSectionJson`）。自己再写一份键名映射，迟早跟导入侧对不上 ——
/// 那种错法最阴：导入「成功」但数据是空的。
library;

import 'dart:convert';

import '../../core/article_json.dart';
import '../../core/learning.dart';
import '../../core/vocab/vocab_json.dart';
import '../../models/document.dart';
import '../../models/vocab.dart';
import 'learning_json.dart';

/// 备份顶层格式号（与 Web 版 `BACKUP_VERSION` 同步）。
const int backupVersion = 1;

/// 整库备份的文件名（与 Web 版一致，便于用户一眼认出）。
String backupFileName(String day) => 'economist-backup-$day.json';

/// 学习记录在备份顶层的键名。
///
/// **不是** `LearningSection.name` 直接照搬：Web 版有两个历史键名
/// （`studyDays` 存 `studyStats`、`sessions` 存 `stats`），备份沿用历史键名，
/// 导入侧 `parseBackupPayload` 正是按这套历史名读的。
const Map<LearningSection, String> backupLearningKeys = <LearningSection, String>{
  LearningSection.practice: 'practice',
  LearningSection.mistakes: 'mistakes',
  LearningSection.readDone: 'readDone',
  LearningSection.writingHistory: 'writingHistory',
  LearningSection.backTranslations: 'backTranslations',
  LearningSection.retells: 'retells',
  LearningSection.activity: 'activity',
  LearningSection.studyDays: 'studyStats',
  LearningSection.sessions: 'stats',
  LearningSection.studiedDays: 'studiedDays',
  LearningSection.skimmed: 'skimmed',
  LearningSection.kindStats: 'kindStats',
  LearningSection.answerEvents: 'answerEvents',
  LearningSection.goldenDrills: 'goldenDrills',
  LearningSection.writingErrorProgress: 'writingErrorProgress',
  LearningSection.productionProgress: 'productionProgress',
};

/// 把整库打成备份对象（配合 `jsonEncode` / `jsonEncodePretty`）。
///
/// 传 `library: null` / `articles: []` 也能用：只导学习统计时不必造空库。
Map<String, Object?> backupPayload({
  VocabLibrary? library,
  List<SavedArticle> articles = const <SavedArticle>[],
  required LearningData learning,
  int? readGoal,
  String? goalMemo,
  Object? productionDraft,
  required String exportedAt,
}) {
  // 空串的备忘录当没有：Web 版是 `goalMemo && ...`，空串不写进备份。
  final memo = (goalMemo == null || goalMemo.isEmpty) ? null : goalMemo;
  return <String, Object?>{
    'version': backupVersion,
    'exportedAt': exportedAt,
    if (library != null) 'library': vocabLibraryToJson(library),
    'articles': <Object?>[for (final a in articles) articleToJson(a)],
    for (final section in LearningSection.values)
      backupLearningKeys[section]!: learningSectionJson(learning, section),
    'readGoal': ?readGoal,
    'goalMemo': ?memo,
    'productionDraft': ?productionDraft,
  };
}

/// 两空格缩进的 JSON 文本（备份是给人看 / 存档的，diff 友好）。
String encodeBackupJson(Map<String, Object?> payload) =>
    const JsonEncoder.withIndent('  ').convert(payload);
