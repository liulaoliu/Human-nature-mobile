/// SQLite 存储共用的小工具（对应 Web 版 `server/sqliteUtil.ts`）。
///
/// 只做「形状不可信 → 可落库的值」这一层转换：不依赖具体表，
/// 词库 / 文章 / 学习记录都能用。
library;

/// UTC ISO 时间串，与 Web 版 `new Date().toISOString()` 同格式。
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// 写 TEXT 列的统一出口：null/undefined 存 NULL，其余 `String()` 化。
///
/// 参数是 `Object?`：调用方喂的是 JSON 字段或 SQLite row 值（外部输入），
/// 只认「null → NULL，string 原样，别的 ToString」这一条规则。
String? asText(Object? v) {
  if (v == null) return null;
  return v is String ? v : v.toString();
}

/// 读数字：转不成有限值就走兜底（`null` / 非数字串 / 怪值都算）。
num asNum(Object? v, [num fallback = 0]) {
  if (v is num) return v.isFinite ? v : fallback;
  if (v is String) {
    final n = num.tryParse(v);
    if (n != null && n.isFinite) return n;
  }
  return fallback;
}

/// JSON 数组字段守卫：是数组就原样返回，否则空数组（不把坏数据变成 null）。
List<T> asList<T>(Object? v) => v is List ? v.whereType<T>().toList() : const [];

/// JSON 对象守卫：是 Map 就返回（键统一成 String），否则 null。
///
/// 数组也当不了 record —— 与 Web 版 `isRecord` 的 `!Array.isArray` 一致。
Map<String, Object?>? asRecord(Object? v) {
  if (v is! Map) return null;
  final out = <String, Object?>{};
  for (final e in v.entries) {
    out[asText(e.key) ?? ''] = e.value;
  }
  return out;
}

/// 是不是一个 JSON 对象。
bool isRecord(Object? v) => v is Map;
