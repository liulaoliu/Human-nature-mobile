/// 跟读 / 手动切块存在本机的两小份数据（校准 + 改过的正文）。
///
/// 对应 Web 版 `src/core/shadowingState.ts`（69 行）。它们不是学习记录（丢了不影响
/// 统计），但也是用户手工调过的资产：旧版本、手工改坏、别的程序写脏都可能留下
/// 非对象 JSON。读的时候必须先过这里，不能 `jsonDecode(...) as Map` 直接进业务。
///
/// 纯函数，不碰存储（读写由 `data/prefs_store.dart` 负责）。
library;

import 'ports.dart';

// 调用方拿 [Calibration] 时几乎总要构造 [ManualAnchor]，这里一并导出，
// 免得每个界面文件都多写一行 import。
export 'ports.dart' show ManualAnchor;

bool _isRecord(Object? v) => v is Map && v is! List;

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

int? _int(Object? v) => v is num && v.isFinite ? v.toInt() : null;

/// 与 Web 版 `numbers()` 一致：非数组 → null；数组里非数字的项**逐个丢掉**。
List<int>? _numbers(Object? v) {
  if (v is! List) return null;
  return <int>[for (final item in v) ?_int(item)];
}

ManualAnchor? _anchor(Object? v) {
  if (!_isRecord(v)) return null;
  final raw = v as Map;
  final atSec = _num(raw['atSec']);
  final startWord = _int(raw['startWord']);
  final endWord = _int(raw['endWord']);
  if (atSec == null || startWord == null || endWord == null) return null;
  final text = raw['text'];
  return ManualAnchor(
    atSec: atSec,
    startWord: startWord,
    endWord: endWord,
    text: text is String ? text : null,
  );
}

/// 一份校准：词序号偏移 + 起始块，可选手动锚点 / 拆分 / 合并。
class Calibration {
  const Calibration({
    required this.offsetWords,
    required this.textStartChunk,
    this.anchors = const <ManualAnchor>[],
    this.splits = const <int>[],
    this.merges = const <int>[],
  });

  final int offsetWords;
  final int textStartChunk;

  /// 手动对齐过的锚点（按时间记，换切块粒度也能找回）。
  final List<ManualAnchor> anchors;

  /// 手工拆开过的块号。
  final List<int> splits;

  /// 手工合并过的块号。
  final List<int> merges;

  @override
  String toString() =>
      'Calibration($offsetWords, $textStartChunk, anchors=${anchors.length})';
}

Calibration? _calibration(Object? v) {
  if (!_isRecord(v)) return null;
  final raw = v as Map;
  final offsetWords = _int(raw['offsetWords']);
  final textStartChunk = _int(raw['textStartChunk']);
  if (offsetWords == null || textStartChunk == null) return null;
  var anchors = const <ManualAnchor>[];
  final rawAnchors = raw['anchors'];
  if (rawAnchors is List) {
    anchors = <ManualAnchor>[for (final item in rawAnchors) ?_anchor(item)];
  }
  return Calibration(
    offsetWords: offsetWords,
    textStartChunk: textStartChunk,
    anchors: anchors,
    splits: _numbers(raw['splits']) ?? const <int>[],
    merges: _numbers(raw['merges']) ?? const <int>[],
  );
}

/// 解析校准表：非对象 → 空表；坏条目**整条丢掉**，不因一条脏数据整份失败。
///
/// 键是音频文件名（或文章 id + 档位），值必须至少有 `offsetWords` / `textStartChunk`
/// 两个数字，缺一个就当这条不存在。
Map<String, Calibration> parseCalibrationMap(Object? raw) {
  if (!_isRecord(raw)) return <String, Calibration>{};
  final out = <String, Calibration>{};
  for (final entry in (raw as Map).entries) {
    final one = _calibration(entry.value);
    if (one != null) out['${entry.key}'] = one;
  }
  return out;
}

/// 解析「改过的讲稿」表：非对象 → 空表；只收字符串值。
Map<String, String> parseScriptEditMap(Object? raw) {
  if (!_isRecord(raw)) return <String, String>{};
  final out = <String, String>{};
  for (final entry in (raw as Map).entries) {
    final v = entry.value;
    if (v is String) out['${entry.key}'] = v;
  }
  return out;
}

/// 校准表写回 JSON（键值都是可序列化的基本类型）。
Map<String, Object?> calibrationToJson(Calibration c) => <String, Object?>{
      'offsetWords': c.offsetWords,
      'textStartChunk': c.textStartChunk,
      if (c.anchors.isNotEmpty)
        'anchors': <Map<String, Object?>>[
          for (final a in c.anchors)
            <String, Object?>{
              'atSec': a.atSec,
              'startWord': a.startWord,
              'endWord': a.endWord,
              if (a.text != null) 'text': a.text,
            },
        ],
      if (c.splits.isNotEmpty) 'splits': c.splits,
      if (c.merges.isNotEmpty) 'merges': c.merges,
    };

/// 校准表整体写回。
Map<String, Object?> calibrationMapToJson(Map<String, Calibration> map) =>
    <String, Object?>{
      for (final entry in map.entries) entry.key: calibrationToJson(entry.value),
    };
