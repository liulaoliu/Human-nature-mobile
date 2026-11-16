import 'package:phonemize/phonemize.dart' as p;
import 'package:espeak/espeak.dart' as e;

abstract class Phonemizer {
  factory Phonemizer() = InternalPhonemizer;
  const Phonemizer._();
  String convert(String text, {String? language});
  String sanitize(String ipa) => ipa.trim();
  void dispose() {}
}

/// 原样返回：调用方已经把音素算好了。
///
/// 为什么需要这个（2026-11-16，本项目加的）：Kokoro 要的是 misaki 字母表，
/// 而 misaki 的 Dart 移植（`malsami`）词典是**异步**加载的，塞不进
/// [convert] 的同步签名。于是 App 侧先 `await` 算好音素串，再把引擎的
/// 音素器换成这个，`isPhonemized: true` 时原样透传到 Kotlin。
class PassthroughPhonemizer extends Phonemizer {
  const PassthroughPhonemizer() : super._();
  @override
  String convert(String text, {String? language}) => text;
}

class InternalPhonemizer extends Phonemizer {
  InternalPhonemizer() : super._();
  bool _initialized = false;

  void _ensureInitialized() {
    if (!_initialized) {
      p.initDefaultProcessors();
      _initialized = true;
    }
  }

  @override
  String convert(String text, {String? language}) {
    _ensureInitialized();
    return p.phonemize(
      text,
      language: language ?? 'en-us',
      stripStress: false,
      format: 'ipa',
    );
  }
}

class EspeakPhonemizer extends Phonemizer {
  final e.Espeak _espeak;
  final String _defaultLanguage;

  EspeakPhonemizer._(this._espeak, this._defaultLanguage) : super._();

  /// Initialize espeak-ng with data from [dataPath].
  /// [dataPath] is the directory containing `espeak-ng-data/`.
  factory EspeakPhonemizer({
    required String dataPath,
    String language = 'en-us',
  }) {
    final instance = e.Espeak.init(dataPath, voice: language);
    return EspeakPhonemizer._(instance, language);
  }

  @override
  String convert(String text, {String? language}) {
    if (language != null && language != _defaultLanguage) {
      _espeak.setVoice(language);
    }
    return _espeak.phonemize(text);
  }

  @override
  void dispose() {
    _espeak.dispose();
  }
}
