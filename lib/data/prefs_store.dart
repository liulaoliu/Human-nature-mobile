/// 偏好设置的落盘口：`shared_preferences` 的一层薄封装。
///
/// 为什么单独一个类而不是在 ViewModel 里直接调 SharedPreferences：
///   - 界面层不该知道「存在哪」；换存储（比如以后进 sqflite）只改这一个文件；
///   - 测试里可以塞一个内存实现（[PrefsStore.memory]），不用起平台通道。
///
/// 与 `schema.dart:214` 的口径一致：偏好 / 会话状态走 SharedPreferences，
/// 词库与学习记录一律进 sqflite —— 这里只放「丢了最多回默认」的小对象。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/drill_sentence_draft.dart';
import '../core/golden_session.dart';
import '../core/production_draft.dart';
import '../core/production_settings.dart';
import '../core/study_prefs.dart';
import '../core/writing_draft.dart';

/// 背单词设置的存储键。
const String studyPrefsKey = 'study:prefs';

/// 产出训练设置的存储键。
const String productionSettingsKey = 'production:settings';

/// 奶牛工棚会话草稿的存储键（按「文章::吃法」各一组，最多 9 组）。
const String productionDraftsKey = 'production:drafts';

/// 仿写草稿的存储键（范句 / 作答 / 任务 / 必须用上的词，只有一份）。
const String writingDraftKey = 'writing:draft';

/// 拷打造句草稿的存储键（一批题各一份作答 / 批改，只有一轮）。
const String drillSentenceDraftKey = 'writing:drillDraft';

/// 偏好存储（默认走 SharedPreferences；测试可用 [PrefsStore.memory]）。
class PrefsStore {
  PrefsStore(this._prefs);

  /// 平台实现（`SharedPreferences` 已经在本进程里缓存过一份）。
  static Future<PrefsStore> open() async =>
      PrefsStore(await SharedPreferences.getInstance());

  /// 内存实现（测试用）。
  factory PrefsStore.memory([Map<String, String>? seed]) =>
      PrefsStore._memory(seed ?? <String, String>{});

  PrefsStore._memory(Map<String, String> memory)
      : _prefs = null,
        _memory = memory;

  final SharedPreferences? _prefs;
  Map<String, String>? _memory;

  /// 读背单词设置；没存过 / 存坏了都回默认。
  StudyPrefs loadStudyPrefs() {
    final raw = _read(studyPrefsKey);
    if (raw == null || raw.isEmpty) return defaultStudyPrefs;
    try {
      return parseStudyPrefs(jsonDecode(raw));
    } on FormatException {
      return defaultStudyPrefs;
    }
  }

  /// 写背单词设置。
  Future<void> saveStudyPrefs(StudyPrefs prefs) =>
      _write(studyPrefsKey, jsonEncode(studyPrefsToJson(prefs)));

  /// 读产出训练设置；没存过 / 存坏了都回默认。
  ProductionSettings loadProductionSettings() {
    final raw = _read(productionSettingsKey);
    if (raw == null || raw.isEmpty) return defaultProductionSettings;
    try {
      return normalizeProductionSettings(jsonDecode(raw));
    } on FormatException {
      return defaultProductionSettings;
    }
  }

  /// 写产出训练设置。
  Future<void> saveProductionSettings(ProductionSettings settings) => _write(
        productionSettingsKey,
        jsonEncode(productionSettingsToJson(settings)),
      );

  /// 读奶牛工棚草稿；没存过 / 存坏了都回空表（界面上就是「没有暂停的草稿」）。
  Map<String, ProductionDraft> loadProductionDrafts() {
    final raw = _read(productionDraftsKey);
    if (raw == null || raw.isEmpty) return <String, ProductionDraft>{};
    try {
      return normalizeProductionDraftMap(jsonDecode(raw));
    } on FormatException {
      return <String, ProductionDraft>{};
    }
  }

  /// 写奶牛工棚草稿（写入前先过一遍守卫与上限）。
  Future<void> saveProductionDrafts(Map<String, ProductionDraft> drafts) =>
      _write(
        productionDraftsKey,
        jsonEncode(productionDraftMapToJson(drafts)),
      );

  /// 读仿写草稿；没存过 / 存坏了都回空草稿。
  WritingDraft loadWritingDraft() {
    final raw = _read(writingDraftKey);
    if (raw == null || raw.isEmpty) return emptyWritingDraft;
    try {
      return normalizeWritingDraft(jsonDecode(raw));
    } on FormatException {
      return emptyWritingDraft;
    }
  }

  /// 写仿写草稿。
  Future<void> saveWritingDraft(WritingDraft draft) =>
      _write(writingDraftKey, jsonEncode(draft.toJson()));

  /// 读拷打造句草稿；没存过 / 存坏了都回空草稿。
  DrillSentenceDraft loadDrillSentenceDraft() {
    final raw = _read(drillSentenceDraftKey);
    if (raw == null || raw.isEmpty) return emptyDrillSentenceDraft;
    try {
      return normalizeDrillSentenceDraft(jsonDecode(raw));
    } on FormatException {
      return emptyDrillSentenceDraft;
    }
  }

  /// 写拷打造句草稿。
  Future<void> saveDrillSentenceDraft(DrillSentenceDraft draft) =>
      _write(drillSentenceDraftKey, jsonEncode(draft.toJson()));

  /// 读金句课的会话位置（**按文章分键**，键由 `goldenSessionKey` 算）。
  ///
  /// 没存过 / 存坏了都回空位置（`home` + 第 0 句），不把界面卡在空视图上。
  GoldenSession loadGoldenSession(String? articleKey) {
    final raw = _read(goldenSessionKey(articleKey));
    if (raw == null || raw.isEmpty) return emptyGoldenSession;
    try {
      return parseGoldenSession(jsonDecode(raw)) ?? emptyGoldenSession;
    } on FormatException {
      return emptyGoldenSession;
    }
  }

  /// 写金句课的会话位置。
  Future<void> saveGoldenSession(String? articleKey, GoldenSession session) =>
      _write(goldenSessionKey(articleKey), jsonEncode(session.toJson()));

  String? _read(String key) => _prefs?.getString(key) ?? _memory?[key];

  Future<void> _write(String key, String value) async {
    final memory = _memory;
    if (memory != null) {
      memory[key] = value;
      return;
    }
    await _prefs?.setString(key, value);
  }
}
