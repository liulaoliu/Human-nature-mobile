/// 词库筛选面板的**偏好落盘口径**（纯函数 + 值对象）。
///
/// 为什么单独一个 core 模块：筛选条件要跨会话记住（面板默认关着，用户点开
/// 看到的就是上次那套），而「存成什么形状、读回来坏了怎么办」属于判定，
/// 挂在界面里就只能起 Flutter 才能测。
///
/// 口径：
///   - 只存**用户选过的**那几项：来源 / 类型 / 状态 / 排序 / 含已掌握 /
///     选篇看的那一篇 / 日期；
///   - 读不到、读到坏 JSON、枚举名对不上 → 一律回默认（丢了最多重选一次）；
///   - `sort` 存字符串而不是枚举：排序口径定义在 ViewModel 层
///     （`BrowseSort`），core 不能反向依赖上层。
///
/// **「本篇」指向哪一篇不在这里存** —— 那是全局 `reader:currentArticle`
/// （`core/current_article.dart`）的事。词库只存「选篇」那个临时视角。
library;

import 'vocab_browse.dart';

/// 词库筛选偏好的存储键。
const String vocabBrowsePrefsKey = 'vocab:browse';

/// 面板上的四组条件 + 排序。
///
/// 默认值就是面板第一次打开时该有的样子：**本篇 / 单词 / 复习**。
/// 词库页面的默认视图是「这一篇今天要复习的词」，不是整库大表。
class VocabBrowsePrefs {
  const VocabBrowsePrefs({
    this.scope = BrowseScope.article,
    this.kind = BrowseKind.word,
    this.status = BrowseStatus.due,
    this.sort = 'recent',
    this.includeMastered = false,
    this.pickedArticleId,
    this.days = const <String>{},
  });

  /// 来源（本篇 / 选篇 / 全部）。
  final BrowseScope scope;

  /// 类型（单词 / 语言点 / 全部）。
  final BrowseKind kind;

  /// 学习状态（复习 / 未学习 / 忘记 / 已掌握 / 全部）。
  final BrowseStatus status;

  /// 排序口径名（`recent` / `alphabet` / `due`）。
  final String sort;

  /// 是否把已掌握也算进来。
  final bool includeMastered;

  /// 「选篇」临时看的那一篇；null = 没选。**不改全局当前文章。**
  final String? pickedArticleId;

  /// 勾了哪些入库日（空 = 全部日期）。
  final Set<String> days;

  VocabBrowsePrefs copyWith({
    BrowseScope? scope,
    BrowseKind? kind,
    BrowseStatus? status,
    String? sort,
    bool? includeMastered,
    String? Function()? pickedArticleId,
    Set<String>? days,
  }) =>
      VocabBrowsePrefs(
        scope: scope ?? this.scope,
        kind: kind ?? this.kind,
        status: status ?? this.status,
        sort: sort ?? this.sort,
        includeMastered: includeMastered ?? this.includeMastered,
        pickedArticleId:
            pickedArticleId != null ? pickedArticleId() : this.pickedArticleId,
        days: days ?? this.days,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'scope': scope.name,
        'kind': kind.name,
        'status': status.name,
        'sort': sort,
        'includeMastered': includeMastered,
        if (pickedArticleId != null) 'pickedArticleId': pickedArticleId,
        'days': days.toList(growable: false),
      };
}

T _enumOf<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

/// 读回偏好。不是 Map 就返回 null（= 从没存过）；Map 里坏掉的单项各自回默认，
/// **不整份丢弃** —— 用户只是想记住筛选，没必要因为一个字段报废全丢。
VocabBrowsePrefs? parseVocabBrowsePrefs(Object? raw) {
  if (raw is! Map) return null;
  final picked = raw['pickedArticleId'];
  final days = raw['days'];
  const fallback = VocabBrowsePrefs();
  return VocabBrowsePrefs(
    scope: _enumOf(BrowseScope.values, raw['scope'], fallback.scope),
    kind: _enumOf(BrowseKind.values, raw['kind'], fallback.kind),
    status: _enumOf(BrowseStatus.values, raw['status'], fallback.status),
    sort: raw['sort'] is String && (raw['sort'] as String).trim().isNotEmpty
        ? (raw['sort'] as String).trim()
        : 'recent',
    includeMastered: raw['includeMastered'] == true,
    pickedArticleId: picked is String && picked.trim().isNotEmpty
        ? picked.trim()
        : null,
    days: _strings(days),
  );
}

/// 序列化成可 `jsonEncode` 的 Map。
Map<String, Object?> vocabBrowsePrefsToJson(VocabBrowsePrefs prefs) =>
    prefs.toJson();

Set<String> _strings(Object? raw) {
  if (raw is! List) return const <String>{};
  final out = <String>{};
  for (final v in raw) {
    if (v is String && v.trim().isNotEmpty) out.add(v.trim());
  }
  return out;
}
