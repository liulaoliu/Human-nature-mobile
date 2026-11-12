/// 挑朗读引擎：把「这台机器装了哪些合成器 / 上次选的是哪个」收成一个小对象。
///
/// 为什么单独拿出来：跟读 ViewModel 已经有四十几件事要做（挑文章、读、录、判、
/// 记偏好……），再把「枚举引擎 / 校验存下来的名字 / 换引擎要重设 TTS」塞进去，
/// 方法数就撞门禁了。这里只依赖 `SpeechEnginePort` + `PrefsStore`，可以单独测。
library;

import 'package:flutter/foundation.dart';

import '../core/ports.dart' show SpeechEnginePort;
import '../core/tts_engine.dart';
import '../data/prefs_store.dart';

/// 引擎选择器。
class SpeechEnginePicker extends ChangeNotifier {
  SpeechEnginePicker({required this._port, required this._store});

  /// 没有这个能力时为空（假实现 / 网页 / 老系统）。
  final SpeechEnginePort? _port;
  final PrefsStore _store;

  List<SpeechEngine> _engines = const <SpeechEngine>[];
  String? _selected;

  /// 本机装了的引擎；能力缺失或读不到就是空表。
  List<SpeechEngine> get engines => _engines;

  /// 现在选中的引擎包名；null = 系统默认。
  String? get selected => _selected;

  /// 这台设备的朗读器支不支持挑引擎。
  bool get available => _port != null;

  /// 取一次列表，并把存下来的那个装回去。
  ///
  /// 存的包名可能已经被卸载（`resolveTtsEngine` 会判），这时退回系统默认，
  /// 免得拿着一个装不上的名字反复抛。
  Future<void> load() async {
    final port = _port;
    if (port == null) return;
    _engines = await port.engines();
    _selected = resolveTtsEngine(_store.loadTtsEngine(), _engines);
    if (_selected != null) await port.setEngine(_selected);
    notifyListeners();
  }

  /// 换引擎（null = 系统默认），存本机。
  Future<void> select(String? name) async {
    final port = _port;
    if (port == null) return;
    _selected = readTtsEngine(name);
    await port.setEngine(_selected);
    await _store.saveTtsEngine(_selected);
    notifyListeners();
  }
}
