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

import '../core/study_prefs.dart';

/// 背单词设置的存储键。
const String studyPrefsKey = 'study:prefs';

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
