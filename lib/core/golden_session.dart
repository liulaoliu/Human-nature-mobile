/// 金句课的会话位置（停在哪个视图 / 第几句）。
///
/// 对应 Web `src/reader/hooks/goldenSession.ts`（61 行）。
///
/// 为什么单独一个 core 文件：位置是**外部输入**（SharedPreferences 里的旧 JSON），
/// 读回来必须过守卫 —— 坏数据一律当没存过，不能把界面卡在空视图上。
library;

/// 金句课的九个视图。
const List<String> goldenViews = <String>[
  'home',
  'plan',
  'drill',
  'recall',
  'summary',
  'bank',
  'exam',
  'history',
  'errors',
];

/// 单句练习的阶段（钻取 / 填空 / 拼句 / 小结 / 仿写）。
const List<String> goldenPhases = <String>[
  'preview',
  'fill',
  'assemble',
  'summary',
  'imitation',
];

/// 视图名是否合法。
bool isGoldenView(Object? value) => value is String && goldenViews.contains(value);

/// 会话位置。
class GoldenSession {
  const GoldenSession({
    this.view = 'home',
    this.index = 0,
    this.recallIndex = 0,
  });

  /// 当前视图（`home` / `plan` / `drill` / `recall` / `summary` / `bank` /
  /// `exam` / `history` / `errors`）。
  final String view;

  /// 当前练到第几句（0 起）。
  final int index;

  /// 逆向默写练到第几句（0 起）。
  final int recallIndex;

  GoldenSession copyWith({String? view, int? index, int? recallIndex}) =>
      GoldenSession(
        view: view ?? this.view,
        index: index ?? this.index,
        recallIndex: recallIndex ?? this.recallIndex,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'view': view,
        'index': index,
        'recallIndex': recallIndex,
      };

  @override
  bool operator ==(Object other) =>
      other is GoldenSession &&
      other.view == view &&
      other.index == index &&
      other.recallIndex == recallIndex;

  @override
  int get hashCode => Object.hash(view, index, recallIndex);

  @override
  String toString() => 'GoldenSession($view, index: $index, recall: $recallIndex)';
}

/// 空位置。
const GoldenSession emptyGoldenSession = GoldenSession();

int _nonNegativeInt(Object? raw) {
  final n = raw is num ? raw : num.tryParse('$raw');
  if (n == null || !n.isFinite || n < 0) return 0;
  return n.floor();
}

/// 守卫：坏数据一律当没存过（返 null），不把界面卡在空视图。
GoldenSession? parseGoldenSession(Object? raw) {
  if (raw is! Map) return null;
  final view = raw['view'];
  if (!isGoldenView(view)) return null;
  return GoldenSession(
    view: view! as String,
    index: _nonNegativeInt(raw['index']),
    recallIndex: _nonNegativeInt(raw['recallIndex']),
  );
}

/// 按文章分的存储键（没文章时用空串，和 Web 一致）。
String goldenSessionKey(String? articleKey) =>
    'reader:goldenSession:${articleKey ?? ''}';
