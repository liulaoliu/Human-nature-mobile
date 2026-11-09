/// 备份导入账本：同一份文件「合并导入」第二次直接跳过。
///
/// 为什么需要：`mergeStudyDays` / `mergeActivity` 是**按天累加**语义（两台机器的
/// 学习时长确实该相加），没有来源 id 就没法做成数学意义上的幂等。但用户最常见的
/// 误操作是「同一个文件点两次合并」，这可以用文件指纹挡住，且不影响不同文件相加。
///
/// 对应 Web 版 `src/core/importLedger.ts`（37 行）。
library;

/// 账本最多记这么多份文件（超出丢最老的）。
const int importLedgerLimit = 20;

/// FNV-1a 32 位；只用于「是不是同一份文件」，不做安全哈希。
///
/// 与 Web 版逐位一致：初始值 `2166136261`、每步 `h = imul(h ^ unit, 16777619)`、
/// 最后 `>>> 0` 转无符号再取 36 进制。Dart 的 int 是 64 位，乘法后必须显式
/// `& 0xFFFFFFFF` 才能模拟 JS 的 32 位截断，否则指纹对不上、同一份文件判不出来。
String backupFingerprint(String text) {
  var h = 2166136261;
  for (var i = 0; i < text.length; i++) {
    h = ((h ^ text.codeUnitAt(i)) * 16777619) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

/// 把指纹记进账本（新的在前，最多 [importLedgerLimit] 个）。
List<String> rememberImport(List<String> ledger, String fingerprint) {
  if (fingerprint.isEmpty) return ledger;
  return <String>[
    fingerprint,
    ...ledger.where((String x) => x != fingerprint),
  ].take(importLedgerLimit).toList();
}

/// 这份文件是不是已经合并导入过。
bool hasImported(List<String> ledger, String fingerprint) =>
    fingerprint.isNotEmpty && ledger.contains(fingerprint);

/// 从偏好存储读账本；坏数据当空账本（不抛）。
List<String> parseImportLedger(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .whereType<String>()
      .where((String x) => x.isNotEmpty)
      .take(importLedgerLimit)
      .toList(growable: false);
}
