/// 速读的本机偏好：语速、是否自动拷打、以及每篇文章的游标。
///
/// 键名与 Web 版一致（`reader:speedWpm` / `reader:speedAutoDrill` /
/// `reader:speedCursor:<articleKey>`），这样两端的习惯不打架。
///
/// 一律「读不到 / 存坏了回默认」：这些值丢了大不了重调一次，
/// 不该因为一个脏字符串把整页卡住。
library;

import 'speed_read.dart' show clampWpm, defaultWpm;

/// 语速的存储键。
const String speedWpmKey = 'reader:speedWpm';

/// 是否自动拷打的存储键。
const String speedAutoDrillKey = 'reader:speedAutoDrill';

/// 解析语速：坏值 / 缺失回默认，超范围夹回去。
int parseSpeedWpm(String? raw) {
  if (raw == null || raw.trim().isEmpty) return defaultWpm;
  final n = int.tryParse(raw.trim());
  if (n == null) return defaultWpm;
  return clampWpm(n);
}

/// 解析「自动拷打」开关：只有明确写了 `false` / `0` 才算关，其余都开。
bool parseSpeedAutoDrill(String? raw) {
  if (raw == null) return true;
  final t = raw.trim().toLowerCase();
  if (t == 'false' || t == '0') return false;
  return true;
}

/// 解析某篇文章的游标（第几句，0 起）。坏值回 0。
int parseSpeedCursor(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 0;
  final n = int.tryParse(raw.trim());
  if (n == null || n < 0) return 0;
  return n;
}

/// 把游标夹进这篇的句数范围：读到最后一句时停在最后一句。
int clampCursor(int cursor, int sentenceCount) {
  if (sentenceCount <= 0) return 0;
  if (cursor < 0) return 0;
  if (cursor >= sentenceCount) return sentenceCount - 1;
  return cursor;
}
