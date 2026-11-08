/// 背单词的设置控制器：范围 / 牌组 / 每组词数 / 每日新词额度。
///
/// 为什么从 `StudyViewModel` 里分出来：设置是「记住用户偏好」，会话是「背这一轮」，
/// 两件事的写入方、失败后果、测试方式都不一样 —— 设置写不进去顶多回到默认，
/// 会话写不进去要保住词库。分开之后各自只改自己那一份状态。
///
/// 跨结算点归零由 `StudyPrefs.rollOver` 负责（按 `dayKeyLocal` 判），
/// 所以这里每次读之前都先 `rollOver`，页面一直开着跨过 04:00 也不会算错。
library;

import 'package:flutter/foundation.dart';

import '../core/activity/activity.dart' show dayKeyLocal;
import '../core/entry_kind.dart';
import '../core/study_pool.dart';
import '../core/study_prefs.dart';
import '../data/prefs_store.dart';

class StudySettings extends ChangeNotifier {
  StudySettings({required this.store});

  /// 设置项落盘口（默认实现走 shared_preferences，测试注入内存版）。
  final PrefsStore store;

  StudyPrefs _prefs = defaultStudyPrefs;
  String? _error;

  /// 当前设置（已按今天归零过）。
  StudyPrefs get prefs => _prefs;

  /// 写设置失败的原因；成功一次就清空。
  String? get error => _error;

  /// 读回设置（进页面调一次）。
  void load() {
    _prefs = store.loadStudyPrefs().rollOver(dayKeyLocal());
    notifyListeners();
  }

  /// 换范围（只影响候选池，正在进行的这一轮不受影响）。
  Future<void> setScope(StudyScope value) async {
    if (_prefs.scope == value) return;
    await _save(_prefs.copyWith(scope: value));
  }

  /// 换牌组（单词 / 搭配）。
  Future<void> setDeck(StudyDeck value) async {
    if (_prefs.deck == value) return;
    await _save(_prefs.copyWith(deck: value));
  }

  /// 设置「每组 N 词」，0 = 跟随范围。
  Future<void> setGroupSize(int value) async {
    final next = value < 0 ? 0 : value;
    if (_prefs.groupSize == next) return;
    await _save(_prefs.copyWith(groupSize: next));
  }

  /// 设置「每天最多引入多少新词」，0 = 不限。
  Future<void> setNewLimit(int value) async {
    final next = value < 0 ? 0 : value;
    if (_prefs.newLimit == next) return;
    await _save(_prefs.copyWith(newLimit: next));
  }

  /// 记一次「今天引入了一个新词」并落盘。
  ///
  /// 跨结算点会先归零再加一，所以昨天用掉的额度不会算到今天头上。
  Future<void> bumpNewToday() => _save(_prefs.bumpNewToday(dayKeyLocal()));

  /// 改设置并落盘；写失败只记 [error]，不打断当前这一轮。
  Future<void> _save(StudyPrefs next) async {
    _prefs = next;
    _error = null;
    notifyListeners();
    try {
      await store.saveStudyPrefs(next);
    } catch (e) {
      _error = '设置写不进去：$e';
      notifyListeners();
    }
  }
}
