/// 跟读模块的本机偏好（显示模式 / 麦克风 / 说完静音多久 / 回放放大）。
///
/// 对应 Web 版 `src/state/shadowingPrefs.ts`（95 行）。那边从展示层抽出来是为了让
/// 架构门禁 R3（视图不许直接碰存储）通过；这里同样只放纯逻辑与键名，
/// 真正的读写由 `data/prefs_store.dart` 做（它已经负责 `shared_preferences` 的兜底）。
///
/// **所有读都兜底**：隐私模式 / 存储满了 / 存的是脏数据，一律回默认值，不影响用。
library;

/// 原文显示模式：整篇 / 聚焦（当前块大字，邻近压暗）/ 单块。
enum ShadowingViewMode {
  full('full'),
  focus('focus'),
  block('block');

  const ShadowingViewMode(this.id);

  final String id;

  static ShadowingViewMode? byId(Object? raw) {
    if (raw is! String) return null;
    for (final m in ShadowingViewMode.values) {
      if (m.id == raw) return m;
    }
    return null;
  }
}

/// 循环顺序：按 V 依次切 全文 → 聚焦 → 单块。
const List<ShadowingViewMode> shadowingViewModes = <ShadowingViewMode>[
  ShadowingViewMode.full,
  ShadowingViewMode.focus,
  ShadowingViewMode.block,
];

/// 本机偏好键（与 Web 版逐字一致，方便备份搬来搬去）。
const String shadowingViewModeKey = 'shadowing.ui.viewMode';
const String shadowingMicRawKey = 'shadowing.ui.micRaw';
const String shadowingMicDeviceKey = 'shadowing.ui.micDevice';
const String shadowingHangoverKey = 'shadowing.ui.hangoverMs';
const String shadowingTakeBoostKey = 'shadowing.ui.takeBoost';
const String shadowingRateKey = 'shadowing.ui.speechRate';

/// 默认值集中在这里，读不到 / 存坏了都回它。
class ShadowingPrefs {
  const ShadowingPrefs({
    this.viewMode = ShadowingViewMode.full,
    this.micRaw = true,
    this.micDevice = '',
    this.hangoverMs = 2500,
    this.takeBoost = 2,
    this.speechRate = 0.45,
  });

  final ShadowingViewMode viewMode;

  /// 默认「原声优先」—— 发闷多半就是系统降噪干的。
  final bool micRaw;

  /// 麦克风设备 id；空串表示系统默认。
  final String micDevice;

  /// 「说完静音多久算结束」，默认 2.5 秒（读得慢 / 有停顿的人够用）。
  final int hangoverMs;

  /// 录音回放额外放大倍数，默认 2（= 放大 100%）。
  final double takeBoost;

  /// 标准音的语速（系统 TTS 的 0–1 档）。跟读用 0.45 左右，比日常语速慢一截。
  ///
  /// 这一项 Web 版没有（那边用浏览器 speechSynthesis，语速靠引擎默认），
  /// 但 App 里系统 TTS 默认速度对跟读偏快，所以做成可调的。
  final double speechRate;

  ShadowingPrefs copyWith({
    ShadowingViewMode? viewMode,
    bool? micRaw,
    String? micDevice,
    int? hangoverMs,
    double? takeBoost,
    double? speechRate,
  }) =>
      ShadowingPrefs(
        viewMode: viewMode ?? this.viewMode,
        micRaw: micRaw ?? this.micRaw,
        micDevice: micDevice ?? this.micDevice,
        hangoverMs: hangoverMs ?? this.hangoverMs,
        takeBoost: takeBoost ?? this.takeBoost,
        speechRate: speechRate ?? this.speechRate,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        shadowingViewModeKey: viewMode.id,
        shadowingMicRawKey: micRaw ? '1' : '0',
        shadowingMicDeviceKey: micDevice,
        shadowingHangoverKey: '$hangoverMs',
        shadowingTakeBoostKey: '$takeBoost',
        shadowingRateKey: '$speechRate',
      };
}

/// 默认值（读不到 / 存坏了都回它）。
const ShadowingPrefs defaultShadowingPrefs = ShadowingPrefs();

/// 写回存储时的形状：**键 → 字符串**（`shared_preferences` 只存字符串，
/// 与 Web 版 `localStorage` 一样）。
///
/// 单独一个函数而不是直接用 `toJson()`：那个返回 `Map<String, Object?>`，
/// 调用方还得逐个 `toString()`，写错一处就存进 `'true'` 之类的脏值。
Map<String, String> shadowingPrefsToJson(ShadowingPrefs prefs) =>
    <String, String>{
      shadowingViewModeKey: prefs.viewMode.id,
      shadowingMicRawKey: prefs.micRaw ? '1' : '0',
      shadowingMicDeviceKey: prefs.micDevice,
      shadowingHangoverKey: '${prefs.hangoverMs}',
      shadowingTakeBoostKey: '${prefs.takeBoost}',
      shadowingRateKey: '${prefs.speechRate}',
    };

/// 读显示模式：只认 `focus` / `block`，其余（含脏值）回默认。
ShadowingViewMode readShadowingViewMode(String? raw) =>
    ShadowingViewMode.byId(raw) ?? defaultShadowingPrefs.viewMode;

/// 原声开关存成 `'1'` / `'0'`；没存过回默认（true）。
bool readShadowingMicRaw(String? raw) =>
    raw == null ? defaultShadowingPrefs.micRaw : raw != '0';

/// 麦克风设备 id：没存过回空串（系统默认）。
String readShadowingMicDevice(String? raw) => raw ?? defaultShadowingPrefs.micDevice;

/// 静音多久算读完：小于 0.8 秒的值当脏数据（会把人说话中的停顿当结束）。
int readShadowingHangover(String? raw) {
  final v = num.tryParse(raw ?? '');
  if (v == null || !v.isFinite || v < 800) return defaultShadowingPrefs.hangoverMs;
  return v.toInt();
}

/// 回放放大倍数：小于 0.5 当脏数据（0 等于静音了自己都听不见）。
double readShadowingTakeBoost(String? raw) {
  final v = num.tryParse(raw ?? '');
  if (v == null || !v.isFinite || v < 0.5) return defaultShadowingPrefs.takeBoost;
  return v.toDouble();
}

/// 标准音语速：系统 TTS 的 0–1 档，超出区间当脏数据（0 等于不响，1 快得没法跟）。
double readShadowingRate(String? raw) {
  final v = num.tryParse(raw ?? '');
  if (v == null || !v.isFinite || v < 0.1 || v > 1.0) {
    return defaultShadowingPrefs.speechRate;
  }
  return v.toDouble();
}

/// 从「键 → 原始字符串」的一整份 map 还原偏好（一次读全，省得五次 IO）。
///
/// 与 Web 版不同：那边每次读单键（`localStorage.getItem`），这里按 `PrefsStore`
/// 的形状一次给全，语义完全一致。
ShadowingPrefs readShadowingPrefs(Map<String, String?> raw) => ShadowingPrefs(
      viewMode: readShadowingViewMode(raw[shadowingViewModeKey]),
      micRaw: readShadowingMicRaw(raw[shadowingMicRawKey]),
      micDevice: readShadowingMicDevice(raw[shadowingMicDeviceKey]),
      hangoverMs: readShadowingHangover(raw[shadowingHangoverKey]),
      takeBoost: readShadowingTakeBoost(raw[shadowingTakeBoostKey]),
      speechRate: readShadowingRate(raw[shadowingRateKey]),
    );
