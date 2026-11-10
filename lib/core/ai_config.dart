library;

/// AI 跑批的连接设置（不可变、纯 Dart）。
///
/// 为什么要单独一层守卫：这些值来自 `shared_preferences`（用户手填 / 旧版本残留），
/// 和备份 JSON 一样属于「外部输入」。坏值不能让跑批一启动就抛异常或把请求发到
/// 莫名其妙的地址 —— 一律先过 [normalizeAiConfig] 洗一遍。
///
/// **apiKey 只存本机 SharedPreferences**（`PrefsStore.aiConfigKey`），
/// 绝不写进 `local.properties` / 备份 JSON / 任何会被 git 跟踪的文件。
/// 本文件只定义形状，不负责存储、不发请求。
const String defaultAiBaseUrl = 'https://api.deepseek.com';
const String defaultAiModel = 'deepseek-chat';
const double defaultAiTemperature = 0.3;
const double minAiTemperature = 0;
const double maxAiTemperature = 2;

class AiConfig {
  const AiConfig({
    this.baseUrl = defaultAiBaseUrl,
    this.apiKey = '',
    this.model = defaultAiModel,
    this.temperature = defaultAiTemperature,
  });

  /// 服务根地址，不带末尾斜杠（`https://api.deepseek.com`）。
  final String baseUrl;

  /// 密钥；空串表示「还没配」。
  final String apiKey;

  /// 模型 id（`deepseek-chat`）。
  final String model;

  /// 采样温度，跑批要稳定，默认偏低。
  final double temperature;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// 给界面看的脱敏写法：`sk-ab****wxyz`。key 本身永不原样回显。
  String get maskedApiKey {
    final key = apiKey.trim();
    if (key.isEmpty) return '（未填写）';
    if (key.length <= 8) return '${key.substring(0, 1)}****';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  AiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
  }) =>
      AiConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
      );

  @override
  bool operator ==(Object other) =>
      other is AiConfig &&
      other.baseUrl == baseUrl &&
      other.apiKey == apiKey &&
      other.model == model &&
      other.temperature == temperature;

  @override
  int get hashCode => Object.hash(baseUrl, apiKey, model, temperature);

  @override
  String toString() =>
      'AiConfig(baseUrl: $baseUrl, model: $model, '
      'temperature: $temperature, apiKey: $maskedApiKey)';
}

const AiConfig defaultAiConfig = AiConfig();

/// 把外部读回来的设置洗成可用值：非 Map、坏字段、越界温度都各自回默认。
///
/// - `baseUrl`：去尾斜杠，必须是能解析出 host 的 http(s) 地址，否则回默认；
/// - `apiKey` / `model`：只认非空字符串，空了回默认 / 空串；
/// - `temperature`：只认有限数字，clamp 到 [minAiTemperature, maxAiTemperature]。
AiConfig normalizeAiConfig(Object? raw) {
  if (raw is! Map) return defaultAiConfig;
  final map = <String, Object?>{};
  for (final entry in raw.entries) {
    map['${entry.key}'] = entry.value;
  }

  final baseUrl = _cleanBaseUrl(map['baseUrl']);
  final apiKey = _cleanString(map['apiKey']);
  final modelRaw = _cleanString(map['model']);
  final temperature = _cleanTemperature(map['temperature']);

  return AiConfig(
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: modelRaw.isEmpty ? defaultAiModel : modelRaw,
    temperature: temperature,
  );
}

/// 序列化（写进 SharedPreferences 用）。key 会跟着走，但落盘位置由调用方决定。
Map<String, Object?> aiConfigToJson(AiConfig config) => <String, Object?>{
      'baseUrl': config.baseUrl,
      'apiKey': config.apiKey,
      'model': config.model,
      'temperature': config.temperature,
    };

String _cleanString(Object? raw) => raw is String ? raw.trim() : '';

String _cleanBaseUrl(Object? raw) {
  final value = _cleanString(raw);
  if (value.isEmpty) return defaultAiBaseUrl;
  final trimmed = value.replaceAll(RegExp(r'/+$'), '').trimRight();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return defaultAiBaseUrl;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return defaultAiBaseUrl;
  }
  return trimmed;
}

double _cleanTemperature(Object? raw) {
  if (raw is num) {
    final value = raw.toDouble();
    if (value.isFinite) {
      return value.clamp(minAiTemperature, maxAiTemperature).toDouble();
    }
  }
  return defaultAiTemperature;
}
