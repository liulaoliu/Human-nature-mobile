/// 学习统计：记录每天「听说读写词」各做了多少，并提供周/月汇总与热力图数据。
///
/// 纯函数，零 IO —— 对应旧项目 `src/core/activity.ts`（逐函数移植，语义一致）。
/// 存储交给 `lib/data/repositories/`，这里只算。
/// 热力图布局借鉴 GitHub 贡献图：列 = 周、行 = 星期（周日起），未来留空。
library;

/// 活动分类。
enum ActivityCat { read, vocab, listen, write, speak }

/// 固定顺序（求和、渲染都按这个顺序，别用 enum.values 之外的顺序）。
const List<ActivityCat> activityCats = <ActivityCat>[
  ActivityCat.read,
  ActivityCat.vocab,
  ActivityCat.listen,
  ActivityCat.write,
  ActivityCat.speak,
];

/// 分类的中文名（标签、图例用）。
const Map<ActivityCat, String> activityLabel = <ActivityCat, String>{
  ActivityCat.read: '读',
  ActivityCat.vocab: '词',
  ActivityCat.listen: '听',
  ActivityCat.write: '写',
  ActivityCat.speak: '说',
};

/// 一天的活动量。`counts` 里没有的分类视为 0。
class DayActivity {
  const DayActivity({required this.day, this.counts = const {}});

  /// 本地日期 YYYY-MM-DD（逻辑日，见 [dayKeyLocal]）。
  final String day;

  /// 分类 → 次数；缺省 = 0。
  final Map<ActivityCat, int> counts;

  int countOf(ActivityCat cat) => counts[cat] ?? 0;

  DayActivity copyWith({String? day, Map<ActivityCat, int>? counts}) =>
      DayActivity(day: day ?? this.day, counts: counts ?? this.counts);

  @override
  String toString() => 'DayActivity($day, $counts)';

  @override
  bool operator ==(Object other) =>
      other is DayActivity && other.day == day && _sameCounts(other.counts, counts);

  @override
  int get hashCode => Object.hash(day, Object.hashAll(activityCats.map(countOf)));

  static bool _sameCounts(Map<ActivityCat, int> a, Map<ActivityCat, int> b) {
    for (final cat in activityCats) {
      if ((a[cat] ?? 0) != (b[cat] ?? 0)) return false;
    }
    return true;
  }
}

/// 「新的一天」从凌晨几点开始（0–23）。
///
/// 设 4 = 00:00–03:59 仍算前一天（熬夜不跨天）。
const int dayRolloverHour = 4;

String _pad2(int n) => n.toString().padLeft(2, '0');

/// 纯日历日期键 YYYY-MM-DD（就是那一天本身，不做结算偏移）——热力图格子、打印日期用。
String calendarDayKey(DateTime d) => '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';

/// 逻辑「今天」的日期键 YYYY-MM-DD（**本地时区**）。
///
/// 结算点在**凌晨 4 点**：00:00–03:59 的学习/背词算**前一天**，
/// 免得学到半夜跨过 0 点就被切成两天（目标、连续天数、日志都用它）。
String dayKeyLocal([DateTime? now]) {
  final d = now ?? DateTime.now();
  return calendarDayKey(d.subtract(const Duration(hours: dayRolloverHour)));
}

/// 下一个「学习日」开始时刻（本地 04:00）；页面跨结算点时用它安排归零。
DateTime nextStudyDayStart([DateTime? now]) {
  final d = now ?? DateTime.now();
  final shifted = d.subtract(const Duration(hours: dayRolloverHour));
  return DateTime(shifted.year, shifted.month, shifted.day + 1, dayRolloverHour);
}

/// 把存档 / 备份里读到的活动数组洗成可用形状。
///
/// 元素级脏数据（非 Map、`day` 不是字符串、`counts` 不是 Map）整条丢掉，
/// 而不是让它把 [addActivity] / 汇总函数炸掉。
List<DayActivity> normalizeActivity(Object? raw) {
  if (raw is! List) return const [];
  final out = <DayActivity>[];
  for (final row in raw) {
    if (row is! Map) continue;
    final day = row['day'];
    if (day is! String || day.trim().isEmpty) continue;
    final rawCounts = row['counts'];
    if (rawCounts is! Map) continue;
    final counts = <ActivityCat, int>{};
    for (final cat in activityCats) {
      final n = _toPositiveInt(rawCounts[cat.name]);
      if (n != null) counts[cat] = n;
    }
    out.add(DayActivity(day: day, counts: counts));
  }
  out.sort((a, b) => a.day.compareTo(b.day));
  return out;
}

int? _toPositiveInt(Object? v) {
  final n = switch (v) {
    int i => i,
    double d when d.isFinite => d.toInt(),
    String s => int.tryParse(s.trim()),
    _ => null,
  };
  if (n == null || n <= 0) return null;
  return n;
}

/// 把某天某类活动加 n（同一天合并；超过上限截断）。纯函数。
List<DayActivity> addActivity(
  List<DayActivity> list,
  String day,
  ActivityCat cat, {
  int n = 1,
  int cap = 400,
}) {
  if (day.isEmpty || n <= 0) return list;
  final i = list.indexWhere((x) => x.day == day);
  final next = <DayActivity>[...list];
  if (i < 0) {
    next.add(DayActivity(day: day, counts: {cat: n}));
  } else {
    final cur = list[i];
    next[i] = cur.copyWith(counts: {...cur.counts, cat: cur.countOf(cat) + n});
  }
  next.sort((a, b) => a.day.compareTo(b.day));
  final keep = cap < 0 ? 0 : cap;
  if (next.length <= keep) return next;
  return next.sublist(next.length - keep);
}

/// 一天的总量。
int dayTotal(DayActivity a) {
  var s = 0;
  for (final c in activityCats) {
    s += a.countOf(c);
  }
  return s;
}

Map<ActivityCat, int> _emptyCats() => {
      for (final c in activityCats) c: 0,
    };

/// 统计 [from, to]（含）区间内各分类合计。from/to 为 YYYY-MM-DD。
Map<ActivityCat, int> sumCats(List<DayActivity> list, String from, String to) {
  final out = _emptyCats();
  for (final a in list) {
    if (a.day.compareTo(from) < 0 || a.day.compareTo(to) > 0) continue;
    for (final c in activityCats) {
      out[c] = out[c]! + a.countOf(c);
    }
  }
  return out;
}

/// 连续有活动的天数（从今天或昨天往前数）。
int activityStreak(List<DayActivity> list, [DateTime? now]) {
  final has = <String>{
    for (final a in list)
      if (dayTotal(a) > 0) a.day,
  };
  // 先取「逻辑今天」的日历日（含 04:00 结算），再按日历往前一天天数
  final parts = dayKeyLocal(now).split('-').map(int.parse).toList();
  final cursor = DateTime(parts[0], parts[1], parts[2]);
  var c = cursor;
  if (!has.contains(calendarDayKey(c))) {
    c = c.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (has.contains(calendarDayKey(c))) {
    streak += 1;
    c = c.subtract(const Duration(days: 1));
  }
  return streak;
}

/// 记录数 → 色阶（0 空，1–4 由浅到深）。
int levelFor(int count) {
  if (count <= 0) return 0;
  if (count <= 2) return 1;
  if (count <= 5) return 2;
  if (count <= 9) return 3;
  return 4;
}

/// 热力图的一格。
class HeatCell {
  const HeatCell({
    required this.key,
    required this.count,
    required this.level,
    required this.future,
  });

  /// YYYY-MM-DD
  final String key;
  final int count;
  final int level;

  /// 未来日期（不画内容）
  final bool future;

  @override
  bool operator ==(Object other) =>
      other is HeatCell &&
      other.key == key &&
      other.count == count &&
      other.level == level &&
      other.future == future;

  @override
  int get hashCode => Object.hash(key, count, level, future);
}

/// 月份标注：第 col 列开始是几月。
class HeatMonthLabel {
  const HeatMonthLabel({required this.col, required this.label});

  final int col;
  final String label;
}

/// 热力图。
class Heatmap {
  const Heatmap({
    required this.columns,
    required this.cells,
    required this.monthLabels,
    required this.max,
  });

  final int columns;

  /// cells[col][row]，row 0 = 周日 … 6 = 周六
  final List<List<HeatCell>> cells;
  final List<HeatMonthLabel> monthLabels;

  /// 最大值，用于图例说明
  final int max;
}

/// 构造固定 columns 周的热力图。起点为首周的周日，终点为今天；未来日期留空。
///
/// counts：日期键 → 当日总量。注意格子用**纯日历日**，而 counts 的键是
/// 「逻辑日」（[dayKeyLocal]），凌晨 1 点的活动会落到前一天的格子里。
Heatmap buildHeatmap(
  Map<String, int> counts, {
  int columns = 13,
  DateTime? now,
  int Function(int count) levelFn = levelFor,
}) {
  final t = now ?? DateTime.now();
  final today0 = DateTime(t.year, t.month, t.day);
  // getDay() 的 Dart 语义：DateTime.weekday 是 1=周一…7=周日
  final weekdayIndex = today0.weekday % 7; // 0=周日
  final thisSunday = today0.subtract(Duration(days: weekdayIndex));
  final start = thisSunday.subtract(Duration(days: (columns - 1) * 7));

  final cells = <List<HeatCell>>[];
  final firstColOfMonth = <int, int>{};
  var max = 0;
  for (var c = 0; c < columns; c++) {
    final col = <HeatCell>[];
    for (var r = 0; r < 7; r++) {
      final d = start.add(Duration(days: c * 7 + r));
      final key = calendarDayKey(d);
      final future = d.isAfter(today0);
      final count = future ? 0 : (counts[key] ?? 0);
      if (!future && !firstColOfMonth.containsKey(d.month)) {
        firstColOfMonth[d.month] = c;
      }
      if (count > max) max = count;
      col.add(HeatCell(
        key: key,
        count: count,
        level: future ? 0 : levelFn(count),
        future: future,
      ));
    }
    cells.add(col);
  }

  final monthLabels = firstColOfMonth.entries
      .map((e) => HeatMonthLabel(col: e.value, label: '${e.key}'))
      .toList();

  return Heatmap(
    columns: columns,
    cells: cells,
    monthLabels: monthLabels,
    max: max,
  );
}
