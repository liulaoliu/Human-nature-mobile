/// 学习记录（durable learning data）。
///
/// 这里只放**用户学习记录**：练习成绩、错题、读完/精读进度、写作、复述、活动统计、
/// 背词/选词记录。它们不是「偏好」：换设备、清缓存后应该还能恢复。
///
/// 偏好 / 会话状态（主题、字号、面板开关、上次文章、草稿、会话快照）**不要**放进来；
/// 那些留在本地偏好存储里。
///
/// 存储实现见 `lib/data/`（sqflite 优先）。
library;

import '../models/listening.dart' show listeningQuestionFromJson;
import '../models/vocab.dart' show ReviewState;
import 'activity/activity.dart';
import 'answer_events.dart';
import 'goals.dart';
import 'kind_stats.dart';
import 'mistakes.dart';
import 'practice.dart';
import 'vocab_stats.dart';

/// 复述打卡：用自己的话复述的留档（按篇）。
class RetellRecord {
  const RetellRecord({
    required this.at,
    required this.articleId,
    required this.text,
    required this.words,
  });

  final String at;
  final String articleId;
  final String text;
  final int words;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at,
        'articleId': articleId,
        'text': text,
        'words': words,
      };
}

/// 每天背过的词 id，按天累积。
class StudiedDay {
  const StudiedDay({required this.day, required this.ids});

  final String day;
  final List<String> ids;

  Map<String, Object?> toJson() => <String, Object?>{'day': day, 'ids': ids};
}

/// 学习记录里可以单独增量同步的部分。
///
/// 顺序即 [learningKeys] 的顺序，也就是 UI / 日志里的展示顺序。
enum LearningSection {
  practice,
  mistakes,
  readDone,
  writingHistory,
  backTranslations,
  retells,
  activity,
  studyDays,
  sessions,
  studiedDays,
  skimmed,
  kindStats,
  answerEvents,
  goldenDrills,
  writingErrorProgress,
  productionProgress;

  /// 本地存储键（与 Web 版 localStorage 键一致，迁移时不用再翻译一层）。
  String get storageKey => learningKeys[this]!;
}

/// 存储键 ↔ section 的**唯一清单**。
///
/// 读写学习记录时一律从这里取键（`LearningSection.practice.storageKey`），
/// 不要再手写 `'reader:practice'`：手写漏掉一处，反查就返回 null，
/// 这块记录会默默留在本地、永远不同步到数据库。
///
/// 注意两个历史键名不是驼峰：`studyDays` 存 `reader:studyStats`、
/// `sessions` 存 `reader:vocabStats`。
const Map<LearningSection, String> learningKeys = <LearningSection, String>{
  LearningSection.practice: 'reader:practice',
  LearningSection.mistakes: 'reader:mistakes',
  LearningSection.readDone: 'reader:readDone',
  LearningSection.writingHistory: 'reader:writingHistory',
  LearningSection.backTranslations: 'reader:backTranslations',
  LearningSection.retells: 'reader:retells',
  LearningSection.activity: 'reader:activity',
  LearningSection.studyDays: 'reader:studyStats',
  LearningSection.sessions: 'reader:vocabStats',
  LearningSection.studiedDays: 'reader:studiedToday',
  LearningSection.skimmed: 'reader:intensiveSkimmed',
  LearningSection.kindStats: 'reader:kindStats',
  LearningSection.answerEvents: 'reader:answerEvents',
  LearningSection.goldenDrills: 'reader:goldenDrills',
  LearningSection.writingErrorProgress: 'reader:writingErrorProgress',
  LearningSection.productionProgress: 'reader:productionProgress',
};

/// 中文名（导出 / 备份时的说明文字用）。
const Map<LearningSection, String> learningLabel = <LearningSection, String>{
  LearningSection.practice: '练习记录',
  LearningSection.mistakes: '错题',
  LearningSection.readDone: '读完记录',
  LearningSection.writingHistory: '仿写记录',
  LearningSection.backTranslations: '回译记录',
  LearningSection.retells: '复述记录',
  LearningSection.activity: '活动统计',
  LearningSection.studyDays: '背词日统计',
  LearningSection.sessions: '选词会话',
  LearningSection.studiedDays: '每天背过的词',
  LearningSection.skimmed: '略读标记',
  LearningSection.kindStats: '题型统计',
  LearningSection.answerEvents: '答题事件',
  LearningSection.goldenDrills: '金句锤炼记录',
  LearningSection.writingErrorProgress: '错因复习状态',
  LearningSection.productionProgress: '奶牛工棚目标块进度',
};

/// 一份完整的学习记录。
///
/// 字段名尽量沿用存储键的语义，迁移时不用再做一层翻译。
///
/// 写作 / 回译 / 金句 / 错因 / 工棚这五段暂存**原始 JSON 列表**：它们的记录类型
/// 要到 P5（产出训练 + 小课堂）才移植，那时再把这里换成强类型并在对应模块里
/// 补守卫。放在这里的是「段容器 + 键表 + 守卫口径」，接口先稳住。
class LearningData {
  LearningData({
    List<PracticeRecord>? practice,
    List<MistakeEntry>? mistakes,
    List<ReadDone>? readDone,
    List<Map<String, Object?>>? writingHistory,
    List<Map<String, Object?>>? backTranslations,
    List<RetellRecord>? retells,
    List<DayActivity>? activity,
    List<StudyDay>? studyDays,
    List<PickSession>? sessions,
    List<StudiedDay>? studiedDays,
    List<String>? skimmed,
    KindStats? kindStats,
    List<AnswerEvent>? answerEvents,
    List<Map<String, Object?>>? goldenDrills,
    List<Map<String, Object?>>? writingErrorProgress,
    List<Map<String, Object?>>? productionProgress,
  })  : practice = practice ?? <PracticeRecord>[],
        mistakes = mistakes ?? <MistakeEntry>[],
        readDone = readDone ?? <ReadDone>[],
        writingHistory = writingHistory ?? <Map<String, Object?>>[],
        backTranslations = backTranslations ?? <Map<String, Object?>>[],
        retells = retells ?? <RetellRecord>[],
        activity = activity ?? <DayActivity>[],
        studyDays = studyDays ?? <StudyDay>[],
        sessions = sessions ?? <PickSession>[],
        studiedDays = studiedDays ?? <StudiedDay>[],
        skimmed = skimmed ?? <String>[],
        kindStats = kindStats ?? <String, Map<String, KindStat>>{},
        answerEvents = answerEvents ?? <AnswerEvent>[],
        goldenDrills = goldenDrills ?? <Map<String, Object?>>[],
        writingErrorProgress = writingErrorProgress ?? <Map<String, Object?>>[],
        productionProgress = productionProgress ?? <Map<String, Object?>>[];

  List<PracticeRecord> practice;
  List<MistakeEntry> mistakes;
  List<ReadDone> readDone;
  List<Map<String, Object?>> writingHistory;
  List<Map<String, Object?>> backTranslations;
  List<RetellRecord> retells;
  List<DayActivity> activity;
  List<StudyDay> studyDays;
  List<PickSession> sessions;
  List<StudiedDay> studiedDays;
  List<String> skimmed;
  KindStats kindStats;
  List<AnswerEvent> answerEvents;
  List<Map<String, Object?>> goldenDrills;
  List<Map<String, Object?>> writingErrorProgress;
  List<Map<String, Object?>> productionProgress;
}

/// 空记录。每次都返回新列表 / 新对象，避免调用方改到共享常量。
LearningData emptyLearning() => LearningData();

List<T> _asArray<T>(Object? v) => v is List ? v.whereType<T>().toList() : <T>[];

/// 宽容取列表：列表里只留对象（Map）。
List<Map<String, Object?>> _asObjectList(Object? v) {
  if (v is! List) return <Map<String, Object?>>[];
  return v.whereType<Map>().map(_asObject).toList();
}

Map<String, Object?> _asObject(Map raw) => <String, Object?>{
      for (final e in raw.entries) '${e.key}': e.value,
    };

bool _hasString(Map<String, Object?> m, String key) => m[key] is String;

bool _nonEmptyString(Map<String, Object?> m, String key) {
  final v = m[key];
  return v is String && v.trim().isNotEmpty;
}

/// 取有限数（和 Web 版 `Number.isFinite(Number(v))` 同口径：纯数字字符串也算）。
num? _numVal(Object? v) => switch (v) {
      int i => i,
      double d when d.isFinite => d,
      String s => num.tryParse(s.trim()),
      _ => null,
    };

bool _hasFinite(Map<String, Object?> m, String key) => _numVal(m[key]) != null;

int _intOf(Map<String, Object?> m, String key) => _numVal(m[key])!.toInt();

/// 宽容解析：坏字段丢掉，别让一条脏数据拖垮整份学习记录。
LearningData normalizeLearning(Object? raw) {
  final out = emptyLearning();
  if (raw is! Map) return out;

  out.practice = _asObjectList(raw['practice'])
      .where((r) => _hasString(r, 'at') && _hasString(r, 'kind') && _hasFinite(r, 'total') && _hasFinite(r, 'correct'))
      .map(_practiceFrom)
      .toList();

  out.mistakes = _asObjectList(raw['mistakes'])
      .where((r) =>
          _hasString(r, 'id') &&
          _hasString(r, 'kind') &&
          _hasString(r, 'at') &&
          _hasString(r, 'label') &&
          _hasFinite(r, 'count'))
      .map(_mistakeFrom)
      .toList();

  out.readDone = _asObjectList(raw['readDone'])
      .where((r) => _hasString(r, 'articleId') && _hasString(r, 'day') && _hasString(r, 'at'))
      .map(_readDoneFrom)
      .toList();

  // 写作 / 回译 / 金句 / 错因 / 工棚：P5 才移植强类型，这里只保证「列表 + 对象」。
  //
  // 仿写的 `source` 先做白名单清洗（与 `src/core/writing.ts` 的 WRITING_SOURCES 同口径）：
  // 坏值当成「普通仿写」删掉键，而不是原样留着让界面认错来源。
  out.writingHistory = _asObjectList(raw['writingHistory'])
      .where((r) => _hasString(r, 'at') && _hasString(r, 'text'))
      .map(_cleanWritingSource)
      .toList();
  out.backTranslations = _asObjectList(raw['backTranslations'])
      .where((r) => _nonEmptyString(r, 'id') && _nonEmptyString(r, 'sourceZh'))
      .toList();

  out.retells = _asObjectList(raw['retells'])
      .where((r) =>
          _hasString(r, 'at') && _hasString(r, 'articleId') && _hasString(r, 'text') && _hasFinite(r, 'words'))
      .map((r) => RetellRecord(
            at: r['at']! as String,
            articleId: r['articleId']! as String,
            text: r['text']! as String,
            words: _intOf(r, 'words'),
          ))
      .toList();

  out.activity = normalizeActivity(raw['activity']);

  out.studyDays = _asObjectList(raw['studyDays'])
      .where((r) => _hasString(r, 'day') && _hasFinite(r, 'seconds') && _hasFinite(r, 'cards'))
      .map((r) => StudyDay(
            day: r['day']! as String,
            seconds: _intOf(r, 'seconds'),
            cards: _intOf(r, 'cards'),
          ))
      .toList();

  out.sessions = _asObjectList(raw['sessions'])
      .where((r) => _hasString(r, 'at') && _hasFinite(r, 'seconds') && _hasFinite(r, 'picked'))
      .map((r) => PickSession(
            at: r['at']! as String,
            seconds: _intOf(r, 'seconds'),
            picked: _intOf(r, 'picked'),
          ))
      .toList();

  out.studiedDays = _asObjectList(raw['studiedDays'])
      .where((r) => _hasString(r, 'day'))
      .map((r) => StudiedDay(
            day: r['day']! as String,
            ids: _asArray<String>(r['ids']),
          ))
      .toList();

  out.skimmed = _asArray<String>(raw['skimmed']).where((id) => id.isNotEmpty).toList();

  out.kindStats = normalizeKindStats(raw['kindStats']);

  out.answerEvents = normalizeAnswerEvents(raw['answerEvents']);

  out.goldenDrills = _asObjectList(raw['goldenDrills']);
  out.writingErrorProgress = _asObjectList(raw['writingErrorProgress']);
  out.productionProgress = _asObjectList(raw['productionProgress']);
  return out;
}

PracticeRecord _practiceFrom(Map<String, Object?> r) {
  final seconds = r['seconds'];
  return PracticeRecord(
    at: r['at']! as String,
    kind: parsePracticeKind(r['kind']) ?? PracticeKind.quiz,
    total: _intOf(r, 'total'),
    correct: _intOf(r, 'correct'),
    seconds: _numVal(seconds)?.toInt(),
    articleId: r['articleId'] is String ? r['articleId']! as String : null,
  );
}

MistakeEntry _mistakeFrom(Map<String, Object?> r) {
  String? str(String key) {
    final v = r[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  return MistakeEntry(
    id: r['id']! as String,
    kind: parseMistakeKind(r['kind']) ?? MistakeKind.vocab,
    at: r['at']! as String,
    count: _intOf(r, 'count'),
    label: r['label']! as String,
    itemId: str('itemId'),
    question: listeningQuestionFromJson(r['question']),
    articleId: str('articleId'),
    text: str('text'),
  );
}

ReadDone _readDoneFrom(Map<String, Object?> r) => ReadDone(
      day: r['day']! as String,
      articleId: r['articleId']! as String,
      title: r['title'] is String ? r['title']! as String : '',
      at: r['at']! as String,
    );

/// 仿写来源白名单（必须与 `src/core/writing.ts` 的 `WRITING_SOURCES` 一致）。
const Set<String> writingSources = {
  'writing',
  'goldenSentence',
  'goldenExam',
  'goldenError',
  'production',
  'drillSentence',
};

/// 清洗仿写记录来源：白名单外的值一律删掉（当普通仿写），`sentenceId` 非字符串也删。
Map<String, Object?> _cleanWritingSource(Map<String, Object?> r) {
  final out = <String, Object?>{...r};
  final source = out['source'];
  if (source is! String || !writingSources.contains(source)) out.remove('source');
  if (out['sentenceId'] is! String) out.remove('sentenceId');
  return out;
}

/// 按 section 取一段原始的解析结果（读本地存储单键时用）。
///
/// 复用整份 [normalizeLearning] 的守卫，只返回这一段，保证和数据库水合同口径。
Object normalizeLearningSection(LearningSection key, Object? raw) {
  final parsed = normalizeLearning(<String, Object?>{key.name: raw});
  return switch (key) {
    LearningSection.practice => parsed.practice,
    LearningSection.mistakes => parsed.mistakes,
    LearningSection.readDone => parsed.readDone,
    LearningSection.writingHistory => parsed.writingHistory,
    LearningSection.backTranslations => parsed.backTranslations,
    LearningSection.retells => parsed.retells,
    LearningSection.activity => parsed.activity,
    LearningSection.studyDays => parsed.studyDays,
    LearningSection.sessions => parsed.sessions,
    LearningSection.studiedDays => parsed.studiedDays,
    LearningSection.skimmed => parsed.skimmed,
    LearningSection.kindStats => parsed.kindStats,
    LearningSection.answerEvents => parsed.answerEvents,
    LearningSection.goldenDrills => parsed.goldenDrills,
    LearningSection.writingErrorProgress => parsed.writingErrorProgress,
    LearningSection.productionProgress => parsed.productionProgress,
  };
}

/// 是否至少有一条学习记录（偏好不算）。
bool hasLearningData(LearningData data) =>
    data.practice.isNotEmpty ||
    data.mistakes.isNotEmpty ||
    data.readDone.isNotEmpty ||
    data.writingHistory.isNotEmpty ||
    data.backTranslations.isNotEmpty ||
    data.retells.isNotEmpty ||
    data.activity.isNotEmpty ||
    data.studyDays.isNotEmpty ||
    data.sessions.isNotEmpty ||
    data.studiedDays.any((d) => d.ids.isNotEmpty) ||
    data.skimmed.isNotEmpty ||
    data.kindStats.isNotEmpty ||
    data.answerEvents.isNotEmpty ||
    data.goldenDrills.isNotEmpty ||
    data.writingErrorProgress.isNotEmpty ||
    data.productionProgress.isNotEmpty;

/// 各 section 的条数（调试 / 备份摘要用）。
Map<LearningSection, int> learningCounts(LearningData data) => <LearningSection, int>{
      LearningSection.practice: data.practice.length,
      LearningSection.mistakes: data.mistakes.length,
      LearningSection.readDone: data.readDone.length,
      LearningSection.writingHistory: data.writingHistory.length,
      LearningSection.backTranslations: data.backTranslations.length,
      LearningSection.retells: data.retells.length,
      LearningSection.activity: data.activity.length,
      LearningSection.studyDays: data.studyDays.length,
      LearningSection.sessions: data.sessions.length,
      LearningSection.studiedDays: data.studiedDays.length,
      LearningSection.skimmed: data.skimmed.length,
      LearningSection.kindStats: data.kindStats.length,
      LearningSection.answerEvents: data.answerEvents.length,
      LearningSection.goldenDrills: data.goldenDrills.length,
      LearningSection.writingErrorProgress: data.writingErrorProgress.length,
      LearningSection.productionProgress: data.productionProgress.length,
    };

/// 备好默认复习状态（测试 / 迁移用），避免各处重复写 `ReviewState(...)`。
ReviewState defaultReviewState() => const ReviewState();
