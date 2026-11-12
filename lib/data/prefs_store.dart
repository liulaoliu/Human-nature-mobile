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

import '../core/ai_config.dart';
import '../core/drill_sentence_draft.dart';
import '../core/golden_session.dart';
import '../core/import_ledger.dart';
import '../core/production_draft.dart';
import '../core/production_settings.dart';
import '../core/shadowing_prefs.dart';
import '../core/speed_read.dart' show speedCursorKey;
import '../core/speed_read_prefs.dart';
import '../core/study_prefs.dart';
import '../core/theme_prefs.dart';
import '../core/tts_engine.dart';
import '../core/vocab_browse_prefs.dart';
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

/// 导入账本的存储键（记最近 20 份合并过的备份指纹，同一份不重复合并）。
const String importedBackupsKey = 'backup:imports';

/// AI 跑批设置的存储键。**只存本机 SharedPreferences**，不进备份 / 不进 git。
const String aiConfigKey = 'ai:config';

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

  /// 读导入账本（最近合并过的备份指纹，新的在前）。
  ///
  /// 没存过 / 存坏了都回空表 —— 账本只是「别重复合并同一份」的保险，
  /// 丢了最多让用户重导一次，不该因此挡住备份功能本身。
  List<String> loadImportedBackups() {
    final raw = _read(importedBackupsKey);
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      return parseImportLedger(jsonDecode(raw));
    } on FormatException {
      return const <String>[];
    }
  }

  /// 写导入账本（写入前过 `parseImportLedger`：坏值过滤 + 截断到 20 条）。
  ///
  /// 去重不在这里做：账本顺序是「最近在前」，调用方用 `rememberImport(ledger, fp)`
  /// 算出新账本再存，这样指纹总在最前，截断时挤掉的才是最老的那份。
  Future<void> saveImportedBackups(List<String> ledger) =>
      _write(importedBackupsKey, jsonEncode(parseImportLedger(ledger)));

  /// 读 AI 跑批设置；没存过 / 存坏了都回默认（key 空 = 未配置）。
  ///
  /// 和别的键一样走守卫：用户手填过又清空、旧版本残留坏 JSON 都不能让跑批
  /// 一启动就抛异常。
  AiConfig loadAiConfig() {
    final raw = _read(aiConfigKey);
    if (raw == null || raw.isEmpty) return defaultAiConfig;
    try {
      return normalizeAiConfig(jsonDecode(raw));
    } on FormatException {
      return defaultAiConfig;
    }
  }

  /// 写 AI 跑批设置（key 只落在本机 SharedPreferences）。
  Future<void> saveAiConfig(AiConfig config) =>
      _write(aiConfigKey, jsonEncode(aiConfigToJson(config)));

  /// 读跟读偏好（显示模式 / 麦克风 / 静音时长 / 回放放大）。
  ///
  /// 与 Web 版 `shadowingPrefs.ts` 逐键一致：**读不到一律回默认**，
  /// 脏值（比如静音时长 300ms、放大 0）也当没设过 —— 那些值会让功能看起来坏了。
  ShadowingPrefs loadShadowingPrefs() => readShadowingPrefs(<String, String?>{
        shadowingViewModeKey: _read(shadowingViewModeKey),
        shadowingMicRawKey: _read(shadowingMicRawKey),
        shadowingMicDeviceKey: _read(shadowingMicDeviceKey),
        shadowingHangoverKey: _read(shadowingHangoverKey),
        shadowingTakeBoostKey: _read(shadowingTakeBoostKey),
        shadowingRateKey: _read(shadowingRateKey),
      });

  /// 写跟读偏好（键名与 Web 版一致，值全存字符串）。
  Future<void> saveShadowingPrefs(ShadowingPrefs prefs) async {
    final json = shadowingPrefsToJson(prefs);
    for (final entry in json.entries) {
      await _write(entry.key, entry.value);
    }
  }

  /// 读速读偏好（语速 / 是否自动拷打 / 某篇的游标）。
  ///
  /// 读不到一律回默认 —— 这几个值丢了大不了重调一次。
  int loadSpeedWpm() => parseSpeedWpm(_read(speedWpmKey));

  /// 写速读语速。
  Future<void> saveSpeedWpm(int wpm) => _write(speedWpmKey, '$wpm');

  /// 读「超时自动拷打」开关。
  bool loadSpeedAutoDrill() => parseSpeedAutoDrill(_read(speedAutoDrillKey));

  /// 写「超时自动拷打」开关。
  Future<void> saveSpeedAutoDrill(bool on) => _write(speedAutoDrillKey, on ? 'true' : 'false');

  /// 读某篇文章的速读游标（第几句，0 起）。
  int loadSpeedCursor(String articleKey) =>
      parseSpeedCursor(_read(speedCursorKey(articleKey)));

  /// 写某篇文章的速读游标。
  Future<void> saveSpeedCursor(String articleKey, int index) =>
      _write(speedCursorKey(articleKey), '$index');

  /// 读「用哪个朗读引擎」；null = 系统默认。
  ///
  /// 存的是引擎的包名（`com.google.android.tts` 这类）。存坏了 / 空串都当没选过。
  String? loadTtsEngine() => readTtsEngine(_read(ttsEngineKey));

  /// 写「用哪个朗读引擎」；传 null / 空串 = 回系统默认（直接删键）。
  Future<void> saveTtsEngine(String? name) async {
    final value = readTtsEngine(name);
    if (value == null) {
      final memory = _memory;
      if (memory != null) {
        memory.remove(ttsEngineKey);
        return;
      }
      await _prefs?.remove(ttsEngineKey);
      return;
    }
    await _write(ttsEngineKey, value);
  }

  /// 读明暗模式；没存过 / 存坏了都回「跟随系统」。
  AppThemeMode loadThemeMode() => parseThemeMode(_read(themeModeKey));

  /// 写明暗模式（存枚举名，不存序号）。
  Future<void> saveThemeMode(AppThemeMode mode) =>
      _write(themeModeKey, themeModeStorage(mode));

  /// 读词库筛选面板的条件；没存过 / 存坏了都回 null（= 用面板默认值）。
  ///
  /// 回 null 而不是回一份默认对象：默认值由 `core/vocab_browse_prefs.dart` 的
  /// 构造函数负责，这里再造一份就会有两处默认值。
  VocabBrowsePrefs? loadVocabBrowsePrefs() {
    final raw = _read(vocabBrowsePrefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return parseVocabBrowsePrefs(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  /// 写词库筛选面板的条件。
  Future<void> saveVocabBrowsePrefs(VocabBrowsePrefs prefs) =>
      _write(vocabBrowsePrefsKey, jsonEncode(vocabBrowsePrefsToJson(prefs)));

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
